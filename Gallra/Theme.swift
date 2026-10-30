import SwiftUI

/// Color tokens from `docs/DESIGN.md`.
enum Theme {
    static let window = Color(hex: 0x262624)
    static let sidebar = Color(hex: 0x30302E)
    static let canvas = Color(hex: 0x1F1E1D)
    static let raised = Color(hex: 0x3A3A37)
    static let hover = Color(hex: 0x444441)
    static let line = Color(hex: 0x4A4A46)
    static let textPrimary = Color(hex: 0xECEBE6)
    static let textSecondary = Color(hex: 0xA3A29B)
    static let textDisabled = Color(hex: 0x6B6A65)
    static let accent = Color(hex: 0x4C8DFF)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
