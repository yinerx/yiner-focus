import AppKit
import SwiftUI
import YinerFocusCore

enum Theme {
    static let focus = Color(red: 0.77, green: 0.42, blue: 0.28)
    static let rest = Color(red: 0.32, green: 0.48, blue: 0.62)
}

enum TagColor {
    static func color(hex: String) -> Color {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return Color(red: red, green: green, blue: blue)
    }

    static func hex(from color: Color) -> String {
        let nsColor = NSColor(color)
        guard let converted = nsColor.usingColorSpace(.sRGB) else { return "#7A6A58" }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        // macOS 27 SDK 里这个方法不再返回 Bool。
        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}

enum AppearanceBridge {
    static func apply(_ appearance: Appearance) {
        switch appearance {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum StatusPalette {
    static func color(for style: MenuBarLabel.Style) -> NSColor {
        switch style {
        case .focusRunning, .focusPaused, .focusIdle:
            return NSColor(srgbRed: 0.77, green: 0.42, blue: 0.28, alpha: 1)
        case .breakRunning, .breakPaused, .breakIdle:
            return NSColor(srgbRed: 0.32, green: 0.48, blue: 0.62, alpha: 1)
        }
    }
}
