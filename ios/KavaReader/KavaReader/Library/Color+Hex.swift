import SwiftUI

extension Color {
    init?(hex: String) {
        let trimmed = hex
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "#")))
        guard trimmed.count == 6 || trimmed.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: trimmed).scanHexInt64(&value) else { return nil }

        let hasAlpha = trimmed.count == 8
        let alpha = hasAlpha ? Double((value & 0xFF00_0000) >> 24) / 255 : 1
        let red = Double((value & 0x00FF_0000) >> 16) / 255
        let green = Double((value & 0x0000_FF00) >> 8) / 255
        let blue = Double(value & 0x0000_00FF) / 255

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
