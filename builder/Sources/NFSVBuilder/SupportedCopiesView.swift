import BuilderCore
import SwiftUI

/// "Which copy works?": the accepted releases with file counts, sizes and SHA-256 values.
struct SupportedCopiesView: View {
    @ObservedObject var model: BuilderModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which copy works?").font(.title2).fontWeight(.semibold)
            if let copies = model.supported {
                Text(copies.summary).fixedSize(horizontal: false, vertical: true)
                Text("Game data (GameData, FEData, fe.txt and install.txt), one of:").fontWeight(.semibold)
                ForEach(copies.data, id: \.sha256) { item in
                    entry(item.version, "\(item.files) files, \(size(item.bytes))", item.sha256)
                }
                Text("Porsche.exe, one of:").fontWeight(.semibold)
                ForEach(copies.executables, id: \.sha256) { item in
                    entry(item.version, size(item.bytes), item.sha256)
                }
                Text(SupportedCopies.checksumNote)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.supportedFailed {
                Text("Could not load the list of supported copies.").foregroundColor(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            HStack {
                Spacer()
                if let copies = model.supported {
                    Button("Copy") { copyToPasteboard(copies.plainText) }
                }
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear(perform: model.loadSupported)
    }

    private func entry(_ title: String, _ detail: String, _ sha256: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title): \(detail)")
            Text(sha256)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundColor(.secondary)
        }
        .padding(.leading, 12)
    }

    private func size(_ bytes: Int64) -> String {
        "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) (\(bytes.formatted()) bytes)"
    }
}
