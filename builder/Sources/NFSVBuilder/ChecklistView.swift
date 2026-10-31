import AppKit
import BuilderCore
import SwiftUI
import UniformTypeIdentifiers

struct ChecklistView: View {
    @ObservedObject var model: BuilderModel
    @State private var dropTargeted = false
    @State private var showSupported = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(CheckID.allCases, id: \.self) { id in
                CheckRow(title: id.title, state: model.states[id] ?? .checking("Checking..."), buttons: buttons(for: id))
                if id != CheckID.allCases.last { Divider() }
            }
            Button(action: model.build) {
                Text("Build NFSV.app")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.buildEnabled)
            .padding(.top, 16)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 3)
                .padding(-10)
                .opacity(dropTargeted ? 1 : 0)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted, perform: drop)
        .sheet(isPresented: $showSupported) { SupportedCopiesView(model: model) }
    }

    private func buttons(for id: CheckID) -> [RowButton] {
        let state = model.states[id]
        switch (id, state) {
        case (.commandLineTools, .blocked?):
            return [RowButton(label: "Install...", action: model.installCommandLineTools)]
        case (.buildTools, .blocked?):
            let install = RowButton(label: "Install", action: model.installBuildTools)
            guard let details = model.setupDetails else { return [install] }
            return [RowButton(label: "Copy details", action: { copyToPasteboard(details) }), install]
        case (.patches, .automatic?) where model.toolsReady:
            return [RowButton(label: "Download", action: model.downloadPatches)]
        case (.gameCopy, .blocked?) where model.gameRejected:
            return [RowButton(label: "Which copy works?", action: { showSupported = true }),
                    RowButton(label: "Choose...", action: chooseGame)]
        case (.gameCopy, _):
            return [RowButton(label: "Choose...", action: chooseGame)]
        case (.destination, _):
            return [RowButton(label: "Change...", action: chooseDestination)]
        default:
            return []
        }
    }

    private func chooseGame() {
        let panel = NSOpenPanel()
        panel.message = "Choose your game folder, or its .iso, .bin or .cue disc image"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["iso", "bin", "cue"].compactMap { UTType(filenameExtension: $0) } + [.folder]
        if let current = model.gamePath { panel.directoryURL = current.deletingLastPathComponent() }
        if panel.runModal() == .OK, let url = panel.url { model.setGame(url) }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.message = "Choose where to put NFSV.app"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.destination
        if panel.runModal() == .OK, let url = panel.url { model.setDestination(url) }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard model.phase == .checklist, let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) } ?? (item as? URL)
            guard let url = url, BuilderModel.isGameCandidate(url) else { return }
            DispatchQueue.main.async { model.setGame(url) }
        }
        return true
    }
}

struct RowButton {
    let label: String
    let action: () -> Void
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

struct CheckRow: View {
    let title: String
    let state: CheckState
    let buttons: [RowButton]

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(state.color)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(BuilderModel.plain(state.message))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ForEach(buttons, id: \.label) { button in
                Button(button.label, action: button.action)
            }
        }
        .padding(.vertical, 9)
    }
}

extension CheckID {
    var title: String {
        switch self {
        case .mac: return "Mac"
        case .commandLineTools: return "Xcode command line tools"
        case .buildTools: return "Build tools (Python)"
        case .patches: return "Patches"
        case .gameCopy: return "Game copy"
        case .destination: return "Destination"
        case .diskSpace: return "Free disk space"
        }
    }
}

extension CheckState {
    var message: String {
        switch self {
        case let .checking(text), let .ready(text), let .automatic(text), let .blocked(text): return text
        }
    }

    var color: Color {
        switch self {
        case .checking: return Color(NSColor.systemGray)
        case .ready: return Color(NSColor.systemGreen)
        case .automatic: return Color(NSColor.systemOrange)
        case .blocked: return Color(NSColor.systemRed)
        }
    }
}
