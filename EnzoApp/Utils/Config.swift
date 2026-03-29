import Foundation

enum Config {
    static var claudeAPIKey: String {
        Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String ?? ""
    }
    static var supabaseURL: String {
        Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
    }
    static var supabaseAnonKey: String {
        Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""
    }
    static var stravaClientID: String {
        Bundle.main.infoDictionary?["STRAVA_CLIENT_ID"] as? String ?? ""
    }
    static var stravaClientSecret: String {
        Bundle.main.infoDictionary?["STRAVA_CLIENT_SECRET"] as? String ?? ""
    }
}
