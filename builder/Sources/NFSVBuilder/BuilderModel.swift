import AppKit
import BuilderCore

/// Owns the checklist state, runs the pipeline commands and drives the build.
final class BuilderModel: ObservableObject {
    enum Phase: Equatable {
        case checklist
        case building(stepID: String, fraction: Double, log: [String])
        case finished(URL)
        case failed(step: String, message: String, log: [String])
        /// The build finished but NFSV is running; installing waits until the user quits it.
        case quitToInstall(built: URL)
    }

    @Published private(set) var states: [CheckID: CheckState]
    @Published private(set) var phase: Phase = .checklist
    @Published private(set) var gamePath: URL?
    @Published private(set) var destination: URL
    /// True once Cancel was pressed or the app started installing, so Cancel can no longer act.
    @Published private(set) var cancelDisabled = false
    @Published private(set) var buildFilesRemoved = false
    /// A plain message shown as an alert over the checklist.
    @Published var notice: String?
    /// Output of the last failed build tools install, for Copy details.
    @Published private(set) var setupDetails: String?
    /// True while the game row is red because the chosen copy was checked and rejected.
    @Published private(set) var gameRejected = false
    /// The rejection message plus what the check logged (detected checksums), for Copy details.
    @Published private(set) var gameDetails: String?
    /// True while the game source is the installed NFSV.app found on start, not one the user chose.
    @Published private(set) var usingInstalledApp = false
    /// Why the installed NFSV.app found on start could not be reused, shown on the empty game row.
    private var gameNote: String?
    /// Whether the "Which copy works?" sheet is open. Quitting closes it first.
    @Published var showingSupported = false
    /// The accepted releases for the "Which copy works?" sheet, loaded once from the pipeline.
    @Published private(set) var supported: SupportedCopies?
    @Published private(set) var supportedFailed = false

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
    private var supportedRunner: PipelineRunner?

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

    var buildTitle: String {
        buildButtonTitle(game: gamePath, oldStamp: gamePath.flatMap(builderStamp(ofApp:)), newVersion: version)
    }

    func start() {
        selectInstalledApp()
        refresh()
        prepare(sweep: true) { [self] _ in refreshBuildTools() }
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

    /// A game folder, disc image or NFSV.app (an app bundle is a folder).
    static func isGameCandidate(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        return isDir.boolValue || ["iso", "bin", "cue"].contains(url.pathExtension.lowercased())
    }

    /// An update reuses the game inside the installed app, so the original copy is not needed again.
    private func selectInstalledApp() {
        guard let app = findInstalledApp(destination: destination) else { return }
        gamePath = app
        usingInstalledApp = true
        checkedGame = nil
    }

    func setGame(_ url: URL) {
        guard phase == .checklist else { return }
        usingInstalledApp = false
        gameNote = nil
        gamePath = url
        defaults.set(url.path, forKey: "gamePath")
        checkedGame = nil
        refreshGame()
    }

    private func refreshGame() {
        guard let game = gamePath else {
            gameRejected = false
            gameDetails = nil
            states[.gameCopy] = .blocked(gameNote ?? "Choose a game folder, .iso, .bin, .cue or NFSV.app")
            return
        }
        guard toolsReady else {
            gameRunner?.cancel()
            gameRunner = nil
            checkedGame = nil
            gameRejected = false
            gameDetails = nil
            states[.gameCopy] = .checking("Checked once build tools are installed")
            return
        }
        guard checkedGame != game else { return }
        gameRunner?.cancel()
        checkedGame = game
        gameRejected = false
        gameDetails = nil
        states[.gameCopy] = .checking("Checking your game copy...")
        let runner = PipelineRunner.checkGame(paths: paths, version: version, game: game)
        gameRunner = runner
        var detected: String?
        var message: String?
        var output: [String] = []
        run(runner, onEvent: { event in
            switch event {
            case let .game(version): detected = version
            case let .error(text): message = text
            case let .log(line): output.append(line)
            default: break
            }
        }, onExit: { [self] status in
            guard gameRunner === runner else { return }
            gameRunner = nil
            if status == 0, let detected = detected {
                states[.gameCopy] = .ready(isAppBundle(game)
                    ? appGameMessage(version: detected, app: game, destination: destination) : detected)
            } else if usingInstalledApp, let note = message {
                // The installed app's game is missing or changed: back to the empty row, with the reason.
                usingInstalledApp = false
                gameNote = Self.plain(note)
                gamePath = nil
                checkedGame = nil
                refreshGame()
            } else {
                let text = Self.plain(message ?? "Could not check this game copy")
                gameRejected = message != nil && FileManager.default.fileExists(atPath: game.path)
                gameDetails = gameRejected ? gameCheckDetails(message: text, log: output) : nil
                states[.gameCopy] = .blocked(text)
            }
        })
    }

    /// Loads the accepted releases from `builder_cli supported`, which needs the build tools.
    func loadSupported() {
        guard supported == nil, supportedRunner == nil, toolsReady else { return }
        supportedFailed = false
        let runner = PipelineRunner.supported(paths: paths, version: version)
        supportedRunner = runner
        var copies: SupportedCopies?
        run(runner, onEvent: { event in
            if case let .supported(value) = event { copies = value }
        }, onExit: { [self] _ in
            supportedRunner = nil
            supported = copies
            supportedFailed = copies == nil
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

    /// `sweep` (only on start, when nothing else uses the support folder) first deletes what an
    /// interrupted removal or copy left behind and, once the workspace is ready, old versions.
    private func prepare(sweep: Bool = false, _ completion: @escaping (Bool) -> Void) {
        if workspaceReady { return completion(true) }
        guard let sources = sources else {
            states[.buildTools] = .blocked("This copy of NFSV Builder is incomplete. Download it again.")
            return completion(false)
        }
        states[.buildTools] = .checking("Preparing build files...")
        let (paths, version) = (paths, version)
        DispatchQueue.global(qos: .userInitiated).async {
            if sweep { sweepLeftovers(paths) }
            let result = Result {
                try prepareWorkspace(sources: sources, destination: paths.workspace(version: version), version: version)
            }
            if sweep, case .success = result {
                DispatchQueue.global(qos: .utility).async { removeOldWorkspaces(paths, keeping: version) }
            }
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
        setupDetails = nil
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
                toolsFailed(text, details: String(describing: error))
            }
        })
    }

    private func runSetup() {
        states[.buildTools] = .checking("Setting up build tools...")
        var output: [String] = []
        var error: String?
        run(.setup(paths: paths, version: version), onEvent: { event in
            switch event {
            case let .log(line): output.append(line)
            case let .step(_, title): output.append(title)
            case let .error(message):
                error = message
                output.append("Error: \(message)")
            default: break
            }
        }, onExit: { [self] status in
            installingTools = false
            let details = (output + ["Setup exited with status \(status)."]).joined(separator: "\n")
            guard status == 0 else {
                let message = error.map(Self.plain)
                    ?? "Could not set up the build tools. Check your internet connection and try again."
                return toolsFailed(message, details: details)
            }
            refreshBuildTools()
            if !toolsReady { toolsFailed("The build tools are incomplete. Try again.", details: details) }
        })
    }

    private func toolsFailed(_ message: String, details: String? = nil) {
        installingTools = false
        setupDetails = details
        states[.buildTools] = .blocked(message)
        refreshGame()
    }

    // MARK: - Build

    func build() {
        guard phase == .checklist, buildEnabled, let game = gamePath, !shuttingDown else { return }
        if isNFSVRunning() {
            notice = "Quit NFSV first, then try again."
            return
        }
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

    /// Retries only the install of an already built app, after the user quit NFSV.
    func installAgain() {
        guard case let .quitToInstall(built) = phase else { return }
        install(built)
    }

    private func install(_ built: URL) {
        cancelDisabled = true
        if case .quitToInstall = phase {
            guard !isNFSVRunning() else {
                notice = "NFSV is still running. Quit it, then click Install again."
                return
            }
            phase = .building(stepID: buildStep, fraction: 0, log: buildLog)
        } else if isNFSVRunning() {
            appendLog("NFSV is running, so the new build was not installed yet.")
            phase = .quitToInstall(built: built)
            return
        }
        appendLog("Installing NFSV.app into \(destination.path)")
        flushLog()
        let directory = destination
        DispatchQueue.global(qos: .userInitiated).async {
            // Checked again here in case the game was started since; NSRunningApplication is thread safe.
            let result = Result { try installApp(built, into: directory, isRunning: isNFSVRunning) }
            DispatchQueue.main.async { [self] in
                switch result {
                case let .success(app):
                    buildFilesRemoved = false
                    phase = .finished(app)
                case let .failure(error as InstallError) where error.details == nil && isNFSVRunning():
                    appendLog(error.message)
                    phase = .quitToInstall(built: built)
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

    /// The workspace is renamed aside first, so quitting during the slow delete cannot leave a
    /// marked but incomplete workspace behind; the next start sweeps whatever is left.
    func removeBuildFiles() {
        let workspace = paths.workspace(version: version)
        workspaceReady = false
        if let trash = try? moveToTrash(workspace) {
            DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: trash) }
        }
        buildFilesRemoved = !FileManager.default.fileExists(atPath: workspace.path)
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

    /// The bundled sources. Only outside an app bundle (`swift run`) does it fall back to the
    /// repository the executable was built from.
    private static func findSources() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("BuildSources"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("build.sh").path) {
            return bundled
        }
        guard Bundle.main.bundleURL.pathExtension != "app",
              var url = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
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
