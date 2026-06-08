import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var progress = ScanProgress()
    @Environment(\.openWindow) private var openWindow
    @State private var currentNode: FileNode? = nil
    @State private var path: [FileNode] = []
    @State private var selectedNode: FileNode? = nil
    @State private var hoveredNode: FileNode? = nil
    @State private var showDeleteConfirm = false
    @State private var deleteError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            toolbarBar
            Divider()
            if !path.isEmpty {
                breadcrumbBar
                Divider()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            statusBar
        }
        .navigationTitle(windowTitle)
        .onChange(of: progress.root) { newRoot in
            if let r = newRoot {
                currentNode = r
                path = [r]
                selectedNode = nil
                hoveredNode = nil
            }
        }
        .alert("Move to Trash?", isPresented: $showDeleteConfirm, presenting: selectedNode) { node in
            Button("Move to Trash", role: .destructive) { moveToTrash(node) }
            Button("Cancel", role: .cancel) { }
        } message: { node in
            Text("“\(node.name)” (\(node.size.formattedSize)) will be moved to the Trash. You can restore it from there.")
        }
        .alert("Couldn’t delete", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .background(KeyShortcutsView(
            onUp: goUp,
            onClearSelection: { selectedNode = nil }
        ))
    }

    private var windowTitle: String {
        if let n = currentNode {
            return "DiscStats — \(n.name)"
        }
        return "DiscStats"
    }

    // MARK: - Toolbar

    private var toolbarBar: some View {
        HStack(spacing: 8) {
            Button {
                pickFolder()
            } label: {
                Label("Choose Folder", systemImage: "folder.badge.plus")
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(progress.isScanning)
            .help("Choose a folder to scan (⌘O)")

            Button {
                if let r = progress.root {
                    startScan(url: r.url)
                }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(progress.isScanning || progress.root == nil)
            .help("Re-scan current folder (⌘R)")

            Button {
                goUp()
            } label: {
                Label("Up", systemImage: "arrow.up")
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(path.count <= 1)
            .help("Go up one folder (⌘[)")

            if progress.isScanning {
                Button {
                    progress.cancelled = true
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .help("Cancel scan")
            }

            Spacer()

            if let current = currentNode, !progress.isScanning {
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(.secondary)
                    Text(current.size.formattedSize)
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(current.itemCount.formatted()) items")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor),
                            in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(path.enumerated()), id: \.element.id) { idx, node in
                    if idx > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 1)
                    }
                    Button {
                        navigate(to: idx)
                    } label: {
                        HStack(spacing: 4) {
                            if idx == 0 {
                                Image(systemName: "folder")
                                    .font(.caption)
                            }
                            Text(node.name)
                                .font(.callout)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(idx == path.count - 1
                                      ? Color.accentColor.opacity(0.15)
                                      : Color.clear)
                        )
                        .foregroundStyle(idx == path.count - 1
                                         ? Color.primary
                                         : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Content area

    @ViewBuilder
    private var content: some View {
        if progress.isScanning {
            scanningView
        } else if let current = currentNode {
            HSplitView {
                treemapPanel(current: current)
                    .frame(minWidth: 500)
                sidePanel
                    .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
            }
            // Only re-key on tree mutations (delete). Plain drill/back navigation
            // updates the node prop in place so the split view + side panel don't
            // tear down — that was the main source of switching lag.
            .id(progress.dataVersion)
        } else {
            emptyState
        }
    }

    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Scanning…")
                .font(.title3.weight(.semibold))
            VStack(spacing: 4) {
                Text("\(progress.filesScanned.formatted()) files · \(progress.bytesSeen.formattedSize)")
                    .font(.callout)
                    .monospacedDigit()
                if progress.scanElapsed > 0.5 {
                    let rate = Double(progress.filesScanned) / max(progress.scanElapsed, 0.001)
                    Text("\(formatElapsed(progress.scanElapsed)) · \(Int(rate).formatted()) files/sec")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Text(progress.currentPath)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 600)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "internaldrive")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .opacity(0.85)
            Text("Welcome to DiscStats")
                .font(.title2.weight(.semibold))
            Text("Choose a folder to see how disk space is being used.\nClick a rectangle to inspect it · Double-click a folder to drill in.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
            Button {
                pickFolder()
            } label: {
                Label("Choose Folder…", systemImage: "folder.badge.plus")
                    .padding(.horizontal, 8)
            }
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: .command)
            .padding(.top, 4)

            Button {
                openWindow(id: "about")
            } label: {
                Text("About DiscStats")
                    .font(.caption)
            }
            .buttonStyle(.link)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func treemapPanel(current: FileNode) -> some View {
        ZStack {
            if current.children.isEmpty || current.size == 0 {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 44))
                        .foregroundStyle(.tertiary)
                    Text(current.children.isEmpty ? "This folder is empty." : "All items report 0 bytes.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TreemapView(
                    node: current,
                    selectedId: selectedNode?.id,
                    onSelect: { selectedNode = $0 },
                    onDrillIn: { drillInto($0) },
                    onHover: { hoveredNode = $0 }
                )
            }
        }
    }

    // MARK: - Side panel

    private var sidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let node = selectedNode {
                    selectionHeader(node: node)
                    Divider()
                    selectionDetails(node: node)
                    Divider()
                    actionButtons(node: node)
                    if node.isDirectory, !node.children.isEmpty {
                        Divider()
                        topItems(node: node)
                    }
                } else {
                    placeholderPanel
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func selectionHeader(node: FileNode) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(for: node))
                .font(.title)
                .foregroundStyle(ColorPalette.color(for: node))
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(node.size.formattedSize)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func selectionDetails(node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(node.isDirectory ? "Folder" : "File")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                if node.isDirectory {
                    Text("\(node.children.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let parent = currentNode, parent.size > 0 {
                let pct = Double(node.size) / Double(parent.size) * 100
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.18))
                            Capsule()
                                .fill(ColorPalette.color(for: node))
                                .frame(width: geo.size.width * CGFloat(pct / 100))
                        }
                    }
                    .frame(height: 6)
                    Text(String(format: "%.1f%%", pct))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
            Text(node.url.path)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func actionButtons(node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if node.isDirectory, !node.children.isEmpty {
                Button {
                    drillInto(node)
                } label: {
                    Label("Open Folder", systemImage: "arrow.down.right.square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            } label: {
                Label("Reveal in Finder", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(.red)
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
    }

    private func topItems(node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top items")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(Array(node.children.prefix(8))) { child in
                HStack(spacing: 6) {
                    Image(systemName: iconName(for: child))
                        .font(.caption)
                        .foregroundStyle(ColorPalette.color(for: child))
                        .frame(width: 14)
                    Text(child.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(child.size.formattedSize)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var placeholderPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "hand.point.up.left")
                    .foregroundStyle(.tint)
                Text("Nothing selected")
                    .font(.headline)
            }
            Text("Click a rectangle to inspect it. Double-click a folder to drill in.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 6) {
                shortcutRow(keys: "⌘O", desc: "Choose folder")
                shortcutRow(keys: "⌘R", desc: "Rescan")
                shortcutRow(keys: "⌘[", desc: "Go up")
                shortcutRow(keys: "⌘⌫", desc: "Move selection to Trash")
                shortcutRow(keys: "Esc", desc: "Clear selection")
            }
            .padding(.top, 2)
        }
    }

    private func shortcutRow(keys: String, desc: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 3))
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            if progress.isScanning {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Scanning… \(progress.filesScanned.formatted()) files")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if let hov = hoveredNode {
                Image(systemName: iconName(for: hov))
                    .foregroundStyle(ColorPalette.color(for: hov))
                Text(hov.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(hov.size.formattedSize)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let parent = currentNode, parent.size > 0 {
                    let pct = Double(hov.size) / Double(parent.size) * 100
                    Text(String(format: "(%.1f%%)", pct))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            } else if let sel = selectedNode {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.tint)
                Text(sel.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(sel.size.formattedSize)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if currentNode != nil {
                Text("Ready")
                    .foregroundStyle(.tertiary)
            } else {
                Text("No folder loaded")
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if !progress.isScanning, progress.scanElapsed > 0, currentNode != nil {
                Text("Scanned in \(formatElapsed(progress.scanElapsed))")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Actions

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to scan"
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            startScan(url: url)
        }
    }

    private func startScan(url: URL) {
        currentNode = nil
        path = []
        selectedNode = nil
        hoveredNode = nil
        Scanner.startScan(url: url, progress: progress)
    }

    private func drillInto(_ node: FileNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        path.append(node)
        currentNode = node
        selectedNode = nil
        hoveredNode = nil
    }

    private func navigate(to idx: Int) {
        guard idx >= 0, idx < path.count else { return }
        path = Array(path.prefix(idx + 1))
        currentNode = path.last
        selectedNode = nil
        hoveredNode = nil
    }

    private func goUp() {
        guard path.count > 1 else { return }
        navigate(to: path.count - 2)
    }

    private func moveToTrash(_ node: FileNode) {
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            removeFromTree(node)
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func removeFromTree(_ node: FileNode) {
        let sizeDelta = node.size
        let countDelta = node.itemCount
        if let parent = node.parent,
           let idx = parent.children.firstIndex(where: { $0.id == node.id }) {
            parent.children.remove(at: idx)
            var cursor: FileNode? = parent
            while let c = cursor {
                c.size -= sizeDelta
                c.itemCount -= countDelta
                cursor = c.parent
            }
        } else {
            currentNode = nil
            path = []
            progress.root = nil
        }
        if selectedNode?.id == node.id { selectedNode = nil }
        if hoveredNode?.id == node.id { hoveredNode = nil }
        progress.dataVersion &+= 1
    }

    // MARK: - Helpers

    private func iconName(for node: FileNode) -> String {
        if node.isDirectory { return "folder.fill" }
        let ext = node.url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif",
             "bmp", "webp", "svg":
            return "photo.fill"
        case "mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv":
            return "film.fill"
        case "mp3", "m4a", "wav", "flac", "aac", "ogg", "aif", "aiff":
            return "music.note"
        case "pdf":
            return "doc.richtext.fill"
        case "doc", "docx", "pages", "rtf", "txt", "md", "markdown":
            return "doc.text.fill"
        case "xls", "xlsx", "numbers", "csv":
            return "tablecells.fill"
        case "ppt", "pptx", "key":
            return "rectangle.on.rectangle.fill"
        case "zip", "rar", "7z", "tar", "gz", "bz2", "dmg", "iso":
            return "shippingbox.fill"
        case "app":
            return "app.fill"
        case "swift", "py", "js", "ts", "rb", "go", "rs", "java",
             "c", "cpp", "h", "json", "xml", "html", "css", "sh":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc.fill"
        }
    }

    private func formatElapsed(_ s: TimeInterval) -> String {
        if s < 60 { return String(format: "%.1fs", s) }
        let mins = Int(s) / 60
        let secs = Int(s) % 60
        return "\(mins)m \(secs)s"
    }
}

// MARK: - Hidden keyboard shortcut sink (Esc + macOS 13 arrow keys)
//
// SwiftUI `.keyboardShortcut` works on visible Buttons; for Esc and a
// few menu-less shortcuts we route through an invisible NSView responder.

struct KeyShortcutsView: NSViewRepresentable {
    var onUp: () -> Void
    var onClearSelection: () -> Void

    func makeNSView(context: Context) -> KeyHandlingView {
        let v = KeyHandlingView()
        v.onUp = onUp
        v.onClearSelection = onClearSelection
        return v
    }

    func updateNSView(_ nsView: KeyHandlingView, context: Context) {
        nsView.onUp = onUp
        nsView.onClearSelection = onClearSelection
    }
}

final class KeyHandlingView: NSView {
    var onUp: (() -> Void)?
    var onClearSelection: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        // Esc
        if event.keyCode == 53 {
            onClearSelection?()
            return
        }
        // Cmd + Up arrow
        if event.keyCode == 126, event.modifierFlags.contains(.command) {
            onUp?()
            return
        }
        super.keyDown(with: event)
    }
}
