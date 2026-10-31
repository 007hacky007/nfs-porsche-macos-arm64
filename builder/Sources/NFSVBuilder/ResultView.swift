import AppKit
import SwiftUI

struct ResultView: View {
    enum Outcome {
        case success(URL)
        case failure(step: String, message: String, log: [String])
    }

    @ObservedObject var model: BuilderModel
    let outcome: Outcome

    var body: some View {
        switch outcome {
        case let .success(app): success(app)
        case let .failure(step, message, log): failure(step: step, message: message, log: log)
        }
    }

    private func success(_ app: URL) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(Color(NSColor.systemGreen))
            Text("Ready").font(.title).fontWeight(.semibold)
            Text("NFSV.app is in \(app.deletingLastPathComponent().path).")
                .foregroundColor(.secondary)
            HStack {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app]) }
                Button("Play") { NSWorkspace.shared.open(app) }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            Spacer()
            if model.buildFilesRemoved {
                Text("Build files removed").font(.caption).foregroundColor(.secondary)
            } else {
                Button("Remove build files", action: model.removeBuildFiles)
                    .controlSize(.small)
                    .help("Frees the space used while building. Python and the downloaded patches are kept.")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 430)
    }

    private func failure(step: String, message: String, log: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Color(NSColor.systemRed))
                Text("\(step) failed").font(.title2).fontWeight(.semibold)
            }
            Text(message).fixedSize(horizontal: false, vertical: true)
            Text("Details").font(.headline).padding(.top, 4)
            LogView(lines: log)
            HStack {
                Button("Copy log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.joined(separator: "\n"), forType: .string)
                }
                Spacer()
                Button("Try again", action: model.tryAgain)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
