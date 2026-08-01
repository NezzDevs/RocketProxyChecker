import SwiftUI

enum Theme {
    static let background     = Color(hex: 0x07080A)
    static let panel          = Color(hex: 0x0D0F12)
    static let panelRaised    = Color(hex: 0x141719)
    static let headerRow      = Color(hex: 0x1B1E22)
    static let rowAlt         = Color(hex: 0x0F1113)
    static let rowHover       = Color(hex: 0x17191D)
    static let hairline       = Color.white.opacity(0.07)
    static let hairlineStrong = Color.white.opacity(0.12)

    static let textPrimary    = Color(hex: 0xE9EBEE)
    static let textSecondary  = Color(hex: 0x8B9198)
    static let textFaint      = Color(hex: 0x5C6167)

    static let good      = Color(hex: 0x3FD68C)
    static let slow      = Color(hex: 0xF2C14E)
    static let timeout   = Color(hex: 0xE8833A)
    static let failed    = Color(hex: 0xEF5B5B)
    static let neutral   = Color(hex: 0x6B7280)

    static let corner: CGFloat = 10
    static let rowHeight: CGFloat = 49

    static func color(for status: ProxyStatus) -> Color {
        switch status {
        case .good: return good
        case .slow: return slow
        case .timeout: return timeout
        case .failed: return failed
        case .checking: return Color(hex: 0x9AA3AD)
        case .notTested: return neutral
        }
    }

    static func speedColor(_ ms: Int) -> Color {
        switch ms {
        case ..<1000: return good
        case ..<3000: return slow
        default: return failed
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func panel() -> some View { modifier(PanelBackground()) }
}

struct BarButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(prominent ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent ? Theme.panelRaised : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(prominent ? Theme.hairlineStrong : Theme.hairline, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.65 : 1)
            .contentShape(Rectangle())
    }
}

struct StableLabel: View {
    let title: String
    let systemImage: String

    let candidates: [String]

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .frame(width: 15)

            ZStack(alignment: .leading) {

                ForEach(candidates, id: \.self) { candidate in
                    Text(candidate).hidden()
                }
                Text(title)
            }
        }
    }
}
