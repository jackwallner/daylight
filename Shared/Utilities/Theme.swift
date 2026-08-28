import SwiftUI
#if !os(watchOS)
import UIKit
#endif

enum Theme {
    #if os(watchOS)
    static let background = Color.black
    static let surface = Color(red: 0.10, green: 0.09, blue: 0.07)
    static let elevated = Color(red: 0.16, green: 0.14, blue: 0.10)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.7)
    #else
    static let background = Color(light: .init(1.0, 0.98, 0.94), dark: .init(0.05, 0.05, 0.07))
    static let surface = Color(light: .init(1, 1, 1), dark: .init(0.10, 0.09, 0.08))
    static let elevated = Color(light: .init(0.99, 0.95, 0.87), dark: .init(0.15, 0.13, 0.10))
    static let textPrimary = Color(light: .init(0.13, 0.10, 0.05), dark: .init(1, 1, 1))
    static let textSecondary = Color(light: .init(0.45, 0.40, 0.33), dark: .init(0.72, 0.69, 0.64))
    #endif

    /// The sun. Everything the app is counting is measured in this colour.
    static let amber = Color(red: 0.98, green: 0.70, blue: 0.20)
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.36)
    /// Dusk, used for the part of the day that is already gone.
    static let dusk = Color(red: 0.36, green: 0.32, blue: 0.62)
    static let night = Color(red: 0.16, green: 0.18, blue: 0.34)
    static let mint = Color(red: 0.25, green: 0.82, blue: 0.60)
    static let warning = Color(red: 0.96, green: 0.45, blue: 0.28)
    static let cardRadius: CGFloat = 24

    /// Sunrise through to sunset, used for the day arc and the primary CTA.
    static var dayGradient: LinearGradient {
        LinearGradient(
            colors: [gold, amber, dusk],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var sunGradient: LinearGradient {
        LinearGradient(colors: [gold, amber], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

#if !os(watchOS)
private extension Color {
    struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    init(light: RGB, dark: RGB) {
        self.init(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: 1)
        })
    }
}
#endif
