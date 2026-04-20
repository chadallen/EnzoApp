import SwiftUI

extension Color {
    // MARK: - Adaptive (light / dark)
    // Uses UIColor trait-based initializer so the value resolves at render time.
    static let enzoBg = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(hex: "1C1C1E") : UIColor(hex: "FAFAFA")
    })
    static let enzoCard = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(hex: "2C2C2E") : UIColor(hex: "F7F7FA")
    })
    static let enzoPrimary = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(hex: "FFFFFF") : UIColor(hex: "000000")
    })
    static let enzoSecondary = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(hex: "AEAEB2") : UIColor(hex: "666666")
    })
    // User message bubble — always dark; lighter in dark mode to contrast against bg.
    static let enzoUserBubble = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(hex: "3A3A52") : UIColor(hex: "1C1C2E")
    })

    // MARK: - Fixed (same in both modes)
    static let enzoAccent          = Color(hex: "FC5201")
    static let enzoGoal            = Color(hex: "81C784")
    static let enzoAmber           = Color(hex: "FFB74D")
    static let enzoChartPrimary    = Color(hex: "1E88E5")
    static let enzoChartSecondary  = Color(hex: "90CAF9")
    static let enzoRingHigh        = Color(hex: "27AE60")
    static let enzoRingLow         = Color(hex: "E67E22")
}
