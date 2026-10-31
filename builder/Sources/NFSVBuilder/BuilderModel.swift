import AppKit
import BuilderCore

/// Owns the checklist state, runs the pipeline commands and drives the build.
final class BuilderModel: ObservableObject {
    enum Phase: Equatable {
        case checklist
        case building(stepID: String, fraction: Double, log: [String])
        case finished(URL)
        case failed(step: String, message: String, log: [String])
    }

    @Published private(set) var states: [CheckID: CheckState]
    @Published private(set) var phase: Phase = .checklist
    @Published private(set) var gamePath: URL?
    @Published private(set) var destination: URL
    /// True once Cancel was pressed or the app started installing, so Cancel can no longer act.
    @Published private(set) var cancelDisabled = false
    @Published private(set) var buildFilesRemoved = false

    let paths = BuilderPaths()
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0-dev"
    private let sources = BuilderModel.findSources()
    private let defaults = UserDefaults.standard
    private static let patchesPending = CheckState.automatic("Will be downloaded during the build (15 MB)")

    private var live: [ObjectIdentifier: PipelineRunner] = [:]
    private var idleHandlers: [() -> Void] = []
    private var shuttingDown = false
    private var workspaceReady = false
    private var installingTools = false
    private var downloadTask: URLSessionDownloadTask?
    private var downloadProgress: NSKeyValueObservation?
    private var cltTimer: Timer?
    private var gameRunner: PipelineRunner?
    private var checkedGame: URL?
    private var patchesRunner: PipelineRunner?

    private var buildRunner: PipelineRunner?
    private var buildLog: [String] = []
    private var buildStep = ""
    private var buildError: String?
    private var builtApp: URL?
    private var userCancelled = false
    private var flushScheduled = false

    init() {
        var initial = Dictionary(uniqueKeysWithValues: CheckID.allCases.map { ($0, CheckState.checking("Checking...")) })
        initial[.patches] = Self.patchesPending
        states = initial
        let saved = UserDefaults.standard
        gamePath = saved.string(forKey: "gamePath").map { URL(fileURLWithPath: $0) }
        destination = saved.string(forKey: "destination").map { URL(fileURLWithPath: $0) } ?? defaultDestination
    }

    // MARK: - Checklist

    var toolsReady: Bool { states[.buildTools]?.isReady == true }
    var buildEnabled: Bool { canBuild(states) }

    func start() {
        refresh()
        prepare { [self] _ in refreshBuildTools() }
    }

    /// Re-evaluates every row. Expensive checks (the game copy) only run again when their input changed.
    func refresh() {
        guard phase == .checklist, !shuttingDown else { return }
        states[.mac] = macCheck(isAppleSilicon: Self.isAppleSilicon, version: ProcessInfo.processInfo.operatingSystemVersion)
        states[.destination] = destinationCheck(destination)
        states[.diskSpace] = diskSpaceState()
        refreshCommandLineTools()
        refreshBuildTools()
    }

    private func refreshBuildTools() {
        if workspaceReady && !installingTools {
            states[.buildTools] = buildToolsCheck(paths: paths, version: version)
        }
        refreshPatches()
        refreshGame()
    }

    private func refreshCommandLineTools() {
        DispatchQueue.global(qos: .userInitiated).async {
            let state = CommandLineTools().state()
            DispatchQueue.main.async { [self] in
                states[.commandLineTools] = state
                if state.isReady { cltTimer?.invalidate(); cltTimer = nil }
            }
        }
    }

    func installCommandLineTools() {
        DispatchQueue.global(qos: .userInitiated).async { CommandLineTools().startInstall() }
        cltTimer?.invalidate()
        cltTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshCommandLineTools()
        }
    }

    private func diskSpaceState() -> CheckState {
        var url = paths.support
        while !FileManager.default.fileExists(atPath: url.path) && url.path != "/" {
            url = url.deletingLastPathComponent()
        }
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else {
            return .blocked("Could not read the free space on this disk")
        }
        return diskSpaceCheck(available: available)
    }

    func setDestination(_ url: URL) {
        destination = url
        defaults.set(url.path, forKey: "destination")
        states[.destination] = destinationCheck(url)
    }

    static func isGameCandidate(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        return isDir.boolValue || ["iso", "bin", "cue"].contains(url.pathExtension.lowercased())
    }

    func setGame(_ url: URL) {
        guard phase == .checklist else { return }
        gamePath = url
        defaults.set(url.path, forKey: "gamePath")
        checkedGame = nil
        refreshGame()
    }

    private func refreshGame() {
        guard let game = gamePath else {
            states[.gameCopy] = .blocked("Choose a game folder, .iso, .bin or .cue")
            return
        }
        guard toolsReady else {
            gameRunner?.cancel()
            gameRunner = nil
            checkedGame = nil
            states[.gameCopy] = .checking("Checked once build tools are installed")
            return
        }
        guard checkedGame != game else { return }
        gameRunner?.cancel()
        checkedGame = game
        states[.gameCopy] = .checking("Checking your game copy...")
        let runner = PipelineRunner.checkGame(paths: paths, version: version, game: game)
        gameRunner = runner
        var detected: String?
        var message: String?
        run(runner, onEvent: { event in
            if case let .game(version) = event { detected = version }
            if case let .error(text) = event { message = text }
        }, onExit: { [self] status in
            guard gameRunner === runner else { return }
            gameRunner = nil
            if status == 0, let detected = detected {
                states[.gameCopy] = .ready(detected)
            } else {
                states[.gameCopy] = .blocked(Self.plain(message ?? "Could not check this game copy"))
            }
        })
    }

    private func refreshPatches() {
        guard toolsReady else {
            states[.patches] = Self.patchesPending
            return
        }
        guard patchesRunner == nil, states[.patches]?.isReady != true else { return }
        runPatches(.patchesStatus(paths: paths, version: version), failure: Self.patchesPending)
    }

    func downloadPatches() {
        guard toolsReady else { return }
        patchesRunner?.cancel()
        states[.patches] = .checking("Downloading...")
        runPatches(.fetchPatches(paths: paths, version: version),
                   failure: .automatic("Download failed, will try again during the build"))
    }

    private func runPatches(_ runner: PipelineRunner, failure: CheckState) {
        patchesRunner = runner
        var ready = false
        run(runner, onEvent: { event in
            if case let .patches(value) = event { ready = value }
        }, onExit: { [self] status in
            guard patchesRunner === runner else { return }
            patchesRunner = nil
            states[.patches] = status == 0 && ready ? .ready("Downloaded and verified") : failure
        })
    }

    // MARK: - Build tools

    private func prepare(_ completion: @escaping (Bool) -> Void) {
        if workspaceReady { return completion(true) }
        guard let sources = sources else {
            states[.buildTools] = .blocked("The build files are missing from this app. Download NFSV Builder again.")
            return completion(false)
        }
        states[.buildTools] = .checking("Preparing build files...")
        let (destination, version) = (paths.workspace(version: version), version)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try prepareWorkspace(sources: sources, destination: destination, version: version) }
            DispatchQueue.main.async { [self] in
                if case let .failure(error) = result {
                    states[.buildTools] = .blocked("Could not copy the build files: \(error.localizedDescription)")
                } else {
                    workspaceReady = true
                }
                completion(workspaceReady)
            }
        }
    }

    func installBuildTools() {
        guard !installingTools, !shuttingDown else { return }
        installingTools = true
        states[.buildTools] = .checking("Installing...")
        refreshGame()
        prepare { [self] ready in
            guard ready else { installingTools = false; return }
            if PythonRuntime.isInstalled(paths) { runSetup() } else { downloadPython() }
        }
    }

    private func downloadPython() {
        states[.buildTools] = .checking("Downloading Python...")
        PythonRuntime.install(paths, download: { url, done in
            let task = URLSession.shared.downloadTask(with: url) { file, response, error in
                if let file = file, (response as? HTTPURLResponse)?.statusCode == 200 {
                    done(.success(file))
                } else {
                    done(.failure(error ?? URLError(.badServerResponse)))
                }
            }
            var shown = -1
            downloadProgress = task.progress.observe(\.fractionCompleted) { progress, _ in
                let percent = Int(progress.fractionCompleted * 100)
                guard percent != shown else { return }
                shown = percent
                DispatchQueue.main.async { [self] in
                    guard downloadTask === task else { return }
                    states[.buildTools] = .checking(percent >= 100 ? "Unpacking Python..." : "Downloading Python, \(percent)%")
                }
            }
            downloadTask = task
            task.resume()
        }, completion: { [self] result in
            downloadTask = nil
            downloadProgress = nil
            switch result {
            case .success:
                runSetup()
            case let .failure(error):
                let text = error is URLError ? "Could not download Python. Check your internet connection and try again."
                    : Self.plain(error.localizedDescription)
                toolsFailed(text)
            }
        })
    }

    private func runSetup() {
        states[.buildTools] = .checking("Setting up build tools...")
        run(.setup(paths: paths, version: version), onEvent: { _ in }, onExit: { [self] status in
            installingTools = false
            guard status == 0 else {
                return toolsFailed("Could not set up the build tools. Check your internet connection and try again.")
            }
            refreshBuildTools()
            if !toolsReady { toolsFailed("The build tools are incomplete. Try again.") }
        })
    }

    private func toolsFailed(_ message: String) {
        installingTools = false
        states[.buildTools] = .blocked(message)
        refreshGame()
    }

    // MARK: - Build

    func build() {
        guard phase == .checklist, buildEnabled, let game = gamePath, !shuttingDown else { return }
        gameRunner?.cancel()
        patchesRunner?.cancel()
        (buildLog, buildStep, buildError, builtApp) = ([], "", nil, nil)
        (userCancelled, cancelDisabled) = (false, false)
        phase = .building(stepID: "", fraction: 0, log: [])
        let runner = PipelineRunner.build(paths: paths, version: version, game: game)
        buildRunner = runner
        run(runner, onEvent: { [self] event in
            switch event {
            case let .step(id, title):
                appendLog(title)
                if buildSteps.contains(where: { $0.id == id }) {
                    buildStep = id
                    flushLog()
                }
            case let .log(line): appendLog(line)
            case let .error(message):
                buildError = message
                appendLog("Error: \(message)")
            case let .done(url): builtApp = url
            default: break
            }
        }, onExit: { [self] status in
            buildRunner = nil
            if status != 0 { appendLog("The build exited with status \(status).") }
            if userCancelled || shuttingDown {
                phase = .checklist
                checkedGame = nil
                return refresh()
            }
            if status == 0, buildError == nil, let built = builtApp {
                install(built)
            } else {
                fail(step: buildStepNames[buildStep] ?? "Getting ready",
                     message: buildError ?? "The build stopped unexpectedly.")
            }
        })
    }

    func cancelBuild() {
        guard let runner = buildRunner else { return }
        userCancelled = true
        cancelDisabled = true
        appendLog("Cancelling...")
        runner.cancel()
    }

    private func install(_ built: URL) {
        cancelDisabled = true
        appendLog("Installing NFSV.app into \(destination.path)")
        flushLog()
        let running = isNFSVRunning()
        let directory = destination
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try installApp(built, into: directory, isRunning: { running }) }
            DispatchQueue.main.async { [self] in
                switch result {
                case let .success(app):
                    buildFilesRemoved = false
                    phase = .finished(app)
                case let .failure(error):
                    if let details = (error as? InstallError)?.details { appendLog(details) }
                    fail(step: "Install", message: error.localizedDescription)
                }
            }
        }
    }

    private func fail(step: String, message: String) {
        phase = .failed(step: step, message: Self.plain(message), log: buildLog)
    }

    func tryAgain() {
        phase = .checklist
        checkedGame = nil
        refresh()
    }

    func removeBuildFiles() {
        let workspace = paths.workspace(version: version)
        workspaceReady = false
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: workspace)
            let gone = !FileManager.default.fileExists(atPath: workspace.path)
            DispatchQueue.main.async { [self] in buildFilesRemoved = gone }
        }
    }

    /// Lines arrive faster than SwiftUI should redraw, so they are published at most four times a second.
    private func appendLog(_ line: String) {
        buildLog.append(line)
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in flushLog() }
    }

    private func flushLog() {
        flushScheduled = false
        guard case .building = phase else { return }
        let fraction = buildStep.isEmpty ? 0 : progressFraction(atStart: buildStep)
        phase = .building(stepID: buildStep, fraction: fraction, log: buildLog)
    }

    // MARK: - Processes and shutdown

    var hasRunningWork: Bool { !live.isEmpty || downloadTask != nil }

    private func run(_ runner: PipelineRunner, onEvent: @escaping (PipelineEvent) -> Void,
                     onExit: @escaping (Int32) -> Void) {
        guard !shuttingDown else { return }
        let key = ObjectIdentifier(runner)
        live[key] = runner
        do {
            try runner.start(onEvent: onEvent, onExit: { [self] status in
                live[key] = nil
                onExit(status)
                notifyIfIdle()
            })
        } catch {
            live[key] = nil
            DispatchQueue.main.async {
                onEvent(.log(error.localizedDescription))
                onExit(-1)
            }
        }
    }

    /// Cancels every running command and calls `completion` once all of them have exited.
    func stopAll(then completion: @escaping () -> Void) {
        shuttingDown = true
        cltTimer?.invalidate()
        downloadTask?.cancel()
        downloadTask = nil
        idleHandlers.append(completion)
        live.values.forEach { $0.cancel() }
        notifyIfIdle()
    }

    private func notifyIfIdle() {
        guard live.isEmpty, !idleHandlers.isEmpty else { return }
        let handlers = idleHandlers
        idleHandlers = []
        handlers.forEach { $0() }
    }

    // MARK: - Helpers

    private static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    /// The bundled sources, or in `swift run` the repository the executable was built from.
    private static func findSources() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("BuildSources"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("build.sh").path) {
            return bundled
        }
        guard var url = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        while url.path != "/" {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("build.sh").path) { return url }
        }
        return nil
    }

    /// Pipeline messages start in lower case; the window shows them as sentences.
    static func plain(_ message: String) -> String {
        message.prefix(1).uppercased() + message.dropFirst()
    }
}
