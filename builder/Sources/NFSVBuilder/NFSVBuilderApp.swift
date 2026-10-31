import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BuilderModel()
    private var terminateSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when started with `swift run`, where there is no app bundle to say so.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // The pipeline runs in its own process group, so a plain SIGTERM to the Builder would
        // orphan it; route the signal through the normal quit path instead. terminate(_:) is
        // started from the run loop, not from inside a main-queue block: while it waits for the
        // pipeline to exit, the runner's main-queue callbacks must still be able to run.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { RunLoop.main.perform { NSApp.terminate(nil) } }
        source.resume()
        terminateSignal = source
        model.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Closing the window or quitting during a build first stops the pipeline and waits for it to exit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.hasRunningWork else { return .terminateNow }
        var replied = false
        let reply = {
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        model.stopAll(then: reply)
        // PipelineRunner escalates to SIGKILL after 5 s; never hang the quit beyond that.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: reply)
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopAll(then: {})
    }
}

@main
struct NFSVBuilderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("NFSV Builder") {
            RootView(model: delegate.model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct RootView: View {
    @ObservedObject var model: BuilderModel

    var body: some View {
        Group {
            switch model.phase {
            case .checklist:
                ChecklistView(model: model)
            case let .building(stepID, fraction, log):
                BuildView(model: model, stepID: stepID, fraction: fraction, log: log)
            case let .finished(app):
                ResultView(model: model, outcome: .success(app))
            case let .failed(step, message, log):
                ResultView(model: model, outcome: .failure(step: step, message: message, log: log))
            case .quitToInstall:
                ResultView(model: model, outcome: .quitToInstall)
            }
        }
        .alert(isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Alert(title: Text(model.notice ?? ""))
        }
        .padding(20)
        .frame(width: 560)
        .frame(minHeight: 470, alignment: .top)
    }
}
