import Foundation

enum Config {
    nonisolated(unsafe) static let claudeAPIKey: String =
        Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String ?? ""
    nonisolated(unsafe) static let stravaClientID: String =
        Bundle.main.infoDictionary?["STRAVA_CLIENT_ID"] as? String ?? ""
    nonisolated(unsafe) static let stravaClientSecret: String =
        Bundle.main.infoDictionary?["STRAVA_CLIENT_SECRET"] as? String ?? ""

    // MARK: - UI Copy

    static let connectWelcomeText = "Welcome to Enzo, your personal guide to hitting your Strava PRs. Connect your Strava account now."
}
