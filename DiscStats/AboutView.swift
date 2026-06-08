import SwiftUI

struct AboutView: View {
    private let appVersion: String = {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(v) (\(b))"
    }()

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(.white)
            }
            .padding(.top, 4)

            VStack(spacing: 4) {
                Text("DiscStats")
                    .font(.title.weight(.semibold))
                Text(appVersion)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text("A small, native Mac app that scans a folder and shows where your disk space is going. Each rectangle is a file or folder, sized by how much space it takes up. Double-click a folder to drill in, then move what you don’t need to the Trash.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            Divider().padding(.horizontal, 24)

            VStack(spacing: 6) {
                Text("Made by Yuri Ihnatov")
                    .font(.callout)
                Link(destination: URL(string: "https://ihnatov.nl")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                        Text("ihnatov.nl")
                            .underline()
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .pointerStyleLinkIfAvailable()
                .help("Open ihnatov.nl in your browser")
            }

            Text("© \(currentYear) Yuri Ihnatov")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(28)
        .frame(width: 380)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var currentYear: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f.string(from: Date())
    }
}

private extension View {
    @ViewBuilder
    func pointerStyleLinkIfAvailable() -> some View {
        if #available(macOS 15.0, *) {
            self.pointerStyle(.link)
        } else {
            self
        }
    }
}

#Preview {
    AboutView()
}
