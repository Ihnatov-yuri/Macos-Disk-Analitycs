import SwiftUI
import AppKit

// MARK: - Color palette

enum ColorPalette {
    static func color(for node: FileNode) -> Color {
        if node.isDirectory {
            return Color(nsColor: .systemBlue)
        }
        let ext = node.url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif",
             "bmp", "webp", "raw", "arw", "cr2", "nef", "dng", "psd", "svg":
            return Color(nsColor: .systemTeal)
        case "mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv", "flv", "mpg", "mpeg":
            return Color(nsColor: .systemPurple)
        case "mp3", "m4a", "wav", "flac", "aac", "ogg", "aif", "aiff", "alac":
            return Color(nsColor: .systemOrange)
        case "pdf":
            return Color(nsColor: .systemRed)
        case "doc", "docx", "pages", "rtf", "txt", "md", "markdown", "odt", "epub":
            return Color(nsColor: .systemIndigo)
        case "xls", "xlsx", "numbers", "csv", "tsv":
            return Color(nsColor: .systemGreen)
        case "ppt", "pptx", "key":
            return Color(nsColor: .systemPink)
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso", "tgz":
            return Color(nsColor: .systemBrown)
        case "swift", "py", "js", "jsx", "ts", "tsx", "rb", "go", "rs", "java",
             "kt", "c", "cpp", "cc", "h", "hpp", "m", "mm", "cs", "php",
             "html", "htm", "css", "scss", "sh", "json", "xml", "yaml", "yml", "toml":
            return Color(red: 0.35, green: 0.72, blue: 0.45)
        case "app", "ipa", "pkg", "deb":
            return Color(nsColor: .systemGray)
        case "log":
            return Color(nsColor: .systemMint)
        default:
            return Color(nsColor: .systemYellow)
        }
    }
}

// MARK: - Layout item

struct TreemapItem: Equatable {
    let node: FileNode
    let rect: CGRect
    static func == (l: TreemapItem, r: TreemapItem) -> Bool { l.node.id == r.node.id }
}

// MARK: - Treemap view

struct TreemapView: View {
    let node: FileNode
    let selectedId: UUID?
    let onSelect: (FileNode) -> Void
    let onDrillIn: (FileNode) -> Void
    let onHover: (FileNode?) -> Void

    @State private var hoveredId: UUID? = nil

    var body: some View {
        GeometryReader { geo in
            // Derive the layout inline so it stays in lockstep with `node`.
            // Storing it in @State and updating via .onChange caused gesture
            // closures to capture stale items for one render cycle, which
            // made clicks "miss" right after drilling into a folder.
            let items = TreemapLayout.layout(
                children: node.children.filter { $0.size > 0 },
                in: CGRect(origin: .zero, size: geo.size)
            )

            Canvas(rendersAsynchronously: false) { context, _ in
                for item in items {
                    drawCell(item: item, baseCtx: context)
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
            .onChange(of: node) { _ in
                hoveredId = nil
                onHover(nil)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    let hit = items.last(where: { $0.rect.contains(p) })
                    if hit?.node.id != hoveredId {
                        hoveredId = hit?.node.id
                        onHover(hit?.node)
                    }
                case .ended:
                    if hoveredId != nil {
                        hoveredId = nil
                        onHover(nil)
                    }
                }
            }
            .gesture(
                SpatialTapGesture(count: 2)
                    .onEnded { v in
                        if let hit = items.last(where: { $0.rect.contains(v.location) }),
                           hit.node.isDirectory, !hit.node.children.isEmpty {
                            onDrillIn(hit.node)
                        }
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 1)
                    .onEnded { v in
                        if let hit = items.last(where: { $0.rect.contains(v.location) }) {
                            onSelect(hit.node)
                        }
                    }
            )
        }
    }

    // MARK: Drawing

    private func drawCell(item: TreemapItem, baseCtx: GraphicsContext) {
        let ctx = baseCtx
        let rect = item.rect
        let path = Path(roundedRect: rect, cornerRadius: 1.5)
        let base = ColorPalette.color(for: item.node)

        // Vertical gradient for subtle depth
        let gradient = Gradient(colors: [
            base.opacity(0.95),
            base.opacity(0.65)
        ])
        ctx.fill(path,
                 with: .linearGradient(gradient,
                                       startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                       endPoint: CGPoint(x: rect.midX, y: rect.maxY)))

        // Border / selection / hover
        let isSel = item.node.id == selectedId
        let isHov = item.node.id == hoveredId
        let strokeColor: GraphicsContext.Shading
        let strokeWidth: CGFloat
        if isSel {
            strokeColor = .color(.white)
            strokeWidth = 2.5
        } else if isHov {
            strokeColor = .color(.white.opacity(0.85))
            strokeWidth = 1.5
        } else {
            strokeColor = .color(.black.opacity(0.28))
            strokeWidth = 0.5
        }
        ctx.stroke(path, with: strokeColor, lineWidth: strokeWidth)

        // Labels with shadow for readability on any color
        guard rect.width > 48, rect.height > 24 else { return }

        var textCtx = ctx
        textCtx.addFilter(.shadow(color: .black.opacity(0.55), radius: 1.5, x: 0, y: 1))

        let nameText = Text(item.node.name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)

        let resolved = textCtx.resolve(nameText)
        let textSize = resolved.measure(in: CGSize(width: rect.width - 10, height: rect.height))
        textCtx.draw(resolved,
                     at: CGPoint(x: rect.minX + 6, y: rect.minY + 5),
                     anchor: .topLeading)

        if rect.height > 38 && textSize.height < rect.height - 22 {
            let sizeText = Text(item.node.size.formattedSize)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.95))
            textCtx.draw(sizeText,
                         at: CGPoint(x: rect.minX + 6, y: rect.minY + 6 + textSize.height + 1),
                         anchor: .topLeading)
        }
    }
}

// MARK: - Squarified treemap layout

enum TreemapLayout {
    static func layout(children: [FileNode], in rect: CGRect) -> [TreemapItem] {
        guard !children.isEmpty, rect.width > 1, rect.height > 1 else { return [] }
        let total = children.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0 else { return [] }

        let sorted = children.sorted { $0.size > $1.size }
        let area = Double(rect.width) * Double(rect.height)
        let pairs: [(FileNode, Double)] = sorted.map {
            ($0, (Double($0.size) / Double(total)) * area)
        }

        var result: [TreemapItem] = []
        squarify(items: pairs, rect: rect, into: &result)
        return result
    }

    private static func squarify(items: [(FileNode, Double)],
                                 rect: CGRect,
                                 into result: inout [TreemapItem]) {
        var remaining = items
        var current = rect

        while !remaining.isEmpty, current.width > 0.5, current.height > 0.5 {
            var row: [(FileNode, Double)] = []
            let shortSide = Double(min(current.width, current.height))

            while !remaining.isEmpty {
                let candidate = row + [remaining[0]]
                if row.isEmpty
                    || worstRatio(row: candidate, shortSide: shortSide)
                        <= worstRatio(row: row, shortSide: shortSide) {
                    row = candidate
                    remaining.removeFirst()
                } else {
                    break
                }
            }

            let (rowRects, newRect) = layoutRow(row: row, in: current)
            for (pair, r) in zip(row, rowRects) {
                let inset = r.insetBy(dx: 0.5, dy: 0.5)
                if inset.width > 0 && inset.height > 0 {
                    result.append(TreemapItem(node: pair.0, rect: inset))
                }
            }
            current = newRect
        }
    }

    private static func worstRatio(row: [(FileNode, Double)], shortSide: Double) -> Double {
        guard !row.isEmpty, shortSide > 0 else { return .infinity }
        let sum = row.reduce(0.0) { $0 + $1.1 }
        guard sum > 0 else { return .infinity }
        let s2 = shortSide * shortSide
        let sum2 = sum * sum
        var worst = 0.0
        for (_, area) in row {
            guard area > 0 else { continue }
            let ratio = max((s2 * area) / sum2, sum2 / (s2 * area))
            worst = max(worst, ratio)
        }
        return worst
    }

    private static func layoutRow(row: [(FileNode, Double)],
                                  in rect: CGRect) -> ([CGRect], CGRect) {
        let sum = row.reduce(0.0) { $0 + $1.1 }
        guard sum > 0 else { return ([], rect) }

        var rects: [CGRect] = []
        if rect.width >= rect.height {
            let sliceWidth = CGFloat(sum / Double(rect.height))
            var y = rect.minY
            for (_, area) in row {
                let h = CGFloat(area / sum) * rect.height
                rects.append(CGRect(x: rect.minX, y: y, width: sliceWidth, height: h))
                y += h
            }
            let newRect = CGRect(x: rect.minX + sliceWidth,
                                 y: rect.minY,
                                 width: max(0, rect.width - sliceWidth),
                                 height: rect.height)
            return (rects, newRect)
        } else {
            let sliceHeight = CGFloat(sum / Double(rect.width))
            var x = rect.minX
            for (_, area) in row {
                let w = CGFloat(area / sum) * rect.width
                rects.append(CGRect(x: x, y: rect.minY, width: w, height: sliceHeight))
                x += w
            }
            let newRect = CGRect(x: rect.minX,
                                 y: rect.minY + sliceHeight,
                                 width: rect.width,
                                 height: max(0, rect.height - sliceHeight))
            return (rects, newRect)
        }
    }
}
