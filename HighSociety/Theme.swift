import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255.0,
                  green: CGFloat((hex >> 8) & 0xff) / 255.0,
                  blue: CGFloat(hex & 0xff) / 255.0,
                  alpha: 1)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

enum Theme {
    static let bg = Color(light: 0xE8EDF1, dark: 0x0D161D)
    static let surface = Color(light: 0xF6F8FA, dark: 0x15222C)
    static let surface2 = Color(light: 0xDBE3E9, dark: 0x1E3140)
    static let fg = Color(light: 0x14212B, dark: 0xE7EEF3)
    static let muted = Color(light: 0x566774, dark: 0x8EA2B0)
    static let line = Color(light: 0xC2CDD6, dark: 0x2A3F4F)
    static let accent = Color(light: 0x1769B3, dark: 0x4AA8F0)
    static let accentFg = Color(light: 0xFFFFFF, dark: 0x04121C)
    static let paper = Color(light: 0xFFFEF9, dark: 0xEFEDE5)
    static let ink = Color(hex: 0x1A1F24)
    static let red = Color(hex: 0xC2322B)
    static let good = Color(light: 0x1F7A4D, dark: 0x52C28A)
    static let bad = Color(light: 0xB3261E, dark: 0xF07A70)
}

extension Color {
    init(hex: UInt32) {
        self.init(UIColor(hex: hex))
    }
}

struct PrimaryButton: ButtonStyle {
    var ghost = false
    var color: Color? = nil
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(ghost ? Theme.fg : Theme.accentFg)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .background(ghost ? Theme.surface : (color ?? Theme.accent))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(ghost ? Theme.line : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

struct Panel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
