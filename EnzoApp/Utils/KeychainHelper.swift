import Foundation
import Security

enum KeychainHelper {

    static func save(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    static func load(for key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    @discardableResult
    static func delete(for key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]

        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

// MARK: - Key constants

extension KeychainHelper {
    static let stravaAccessToken = "strava_access_token"
    static let stravaRefreshToken = "strava_refresh_token"
    static let stravaTokenExpiry = "strava_token_expiry"
    static let stravaAthleteId = "strava_athlete_id"
    static let supabaseUserId = "supabase_user_id"
}
