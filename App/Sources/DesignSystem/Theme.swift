import PolkaCore
import SwiftUI

enum PanelMetrics {
    static let wingWidth: CGFloat = 74
    static let expandedCorner: CGFloat = 30
    static let shoulder: CGFloat = 12
    static let contentPadding: CGFloat = 18
}

/// Colors and shapes of the panel. It is always dark — it extends the black
/// camera housing — so these do not follow the system appearance.
enum Theme {
    static let card = Color.white.opacity(0.065)
    static let cardHover = Color.white.opacity(0.1)
    static let hairline = Color.white.opacity(0.08)
    static let secondary = Color.white.opacity(0.64)
    static let tertiary = Color.white.opacity(0.46)
    static let active = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let accent = Color(red: 0.42, green: 0.64, blue: 1)
    static let warning = Color(red: 1, green: 0.62, blue: 0.04)
    static let cornerRadius: CGFloat = 16
}

extension GroupColor {
    var color: Color {
        switch self {
        case .blue: Color(red: 0.37, green: 0.61, blue: 1)
        case .green: Color(red: 0.19, green: 0.82, blue: 0.35)
        case .orange: Color(red: 1, green: 0.62, blue: 0.04)
        case .red: Color(red: 1, green: 0.41, blue: 0.38)
        case .purple: Color(red: 0.75, green: 0.35, blue: 0.95)
        case .teal: Color(red: 0.39, green: 0.82, blue: 1)
        case .pink: Color(red: 1, green: 0.42, blue: 0.67)
        case .gray: Color(white: 0.6)
        }
    }

    var name: LocalizedStringResource {
        switch self {
        case .blue: "Blue"
        case .green: "Green"
        case .orange: "Orange"
        case .red: "Red"
        case .purple: "Purple"
        case .teal: "Teal"
        case .pink: "Pink"
        case .gray: "Gray"
        }
    }
}

extension Color {
    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    var highlight: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.card, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(highlight ?? Theme.hairline, lineWidth: highlight == nil ? 1 : 1.5)
            }
    }
}

struct CardLabel: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.3)
            .foregroundStyle(Theme.tertiary)
    }
}

struct CapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 13)
            .frame(height: 30)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .background(prominent ? tint : Color.white.opacity(configuration.isPressed ? 0.16 : 0.09), in: .capsule)
            .opacity(configuration.isPressed && prominent ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(.capsule)
    }
}

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 30
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(filled ? Color.black : Color.white)
            .background(
                filled ? Color.white : Color.white.opacity(configuration.isPressed ? 0.14 : 0.0001),
                in: .circle
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .contentShape(.circle)
    }
}

/// Hover highlight for list rows and tiles.
struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 12
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                isHovered ? Theme.cardHover : .clear,
                in: .rect(cornerRadius: cornerRadius, style: .continuous)
            )
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = 12) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }
}

/// Empty and permission states share this layout.
struct Placeholder<Actions: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.secondary)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 8) { actions }.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Placeholder where Actions == EmptyView {
    init(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// A letter tile used when a site's icon is not available. Polka never fetches
/// favicons, so no request is made to the sites you save.
struct SiteBadge: View {
    let site: String
    var size: CGFloat = 28

    var body: some View {
        let letter = site.first.map { String($0).uppercased() } ?? "•"
        let hue = Double(site.stableHash % 360) / 360
        Text(letter)
            .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
            .foregroundStyle(Color(hue: hue, saturation: 0.55, brightness: 1))
            .frame(width: size, height: size)
            .background(Color(hue: hue, saturation: 0.6, brightness: 0.55).opacity(0.35), in: .rect(cornerRadius: size * 0.28))
    }
}

extension String {
    /// Same value on every launch, unlike `hashValue`.
    fileprivate var stableHash: UInt {
        unicodeScalars.reduce(UInt(5381)) { ($0 &* 33) &+ UInt($1.value) }
    }
}
