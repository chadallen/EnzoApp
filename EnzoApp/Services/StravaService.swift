import Foundation
import AuthenticationServices

// MARK: - Errors

enum StravaError: Error {
    case invalidURL
    case authCancelled
    case missingCode
    case tokenExchangeFailed(String?)
    case httpError(Int, String?)
    case decodingFailed
    case notAuthenticated
}

// MARK: - Response models

struct StravaTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int          // Unix timestamp
    let athlete: StravaAthlete?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case athlete
    }
}

struct StravaAthlete: Decodable {
    let id: Int64
    let firstName: String
    let lastName: String

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "firstname"
        case lastName = "lastname"
    }

    var displayName: String { "\(firstName) \(lastName)" }
}

// MARK: - StravaService

actor StravaService {

    static let redirectURI = "enzo://oauth"
    static let authorizationURL = "https://www.strava.com/oauth/authorize"
    static let tokenURL = "https://www.strava.com/oauth/token"
    static let athleteURL = "https://www.strava.com/api/v3/athlete"
    static let scope = "read,activity:read_all"

    // MARK: - Auth URL

    /// Builds the Strava OAuth authorization URL. Pure function — testable without network.
    static func authorizationURL(clientID: String) -> URL? {
        var components = URLComponents(string: authorizationURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: scope)
        ]
        return components?.url
    }

    // MARK: - OAuth flow

    /// Runs the full OAuth flow: opens Safari via ASWebAuthenticationSession, exchanges the code,
    /// stores tokens in Keychain, and returns the athlete profile.
    func authenticate(presentingFrom contextProvider: ASWebAuthenticationPresentationContextProviding) async throws -> StravaAthlete {
        let code = try await requestAuthCode(contextProvider: contextProvider)
        let tokenResponse = try await exchangeCode(code)
        storeTokens(tokenResponse)

        let athlete: StravaAthlete
        if let embedded = tokenResponse.athlete {
            athlete = embedded
        } else {
            athlete = try await fetchAthlete()
        }

        KeychainHelper.save(String(athlete.id), for: KeychainHelper.stravaAthleteId)
        return athlete
    }

    // MARK: - Token refresh

    /// Checks expiry and refreshes the access token if it expires within the next 5 minutes.
    func refreshTokenIfNeeded() async throws {
        guard let expiryString = KeychainHelper.load(for: KeychainHelper.stravaTokenExpiry),
              let expiry = Double(expiryString) else { return }

        let expiresAt = Date(timeIntervalSince1970: expiry)
        guard expiresAt.timeIntervalSinceNow < 300 else { return } // still valid for > 5 min

        guard let refreshToken = KeychainHelper.load(for: KeychainHelper.stravaRefreshToken) else {
            throw StravaError.notAuthenticated
        }

        let params: [String: String] = [
            "client_id": Config.stravaClientID,
            "client_secret": Config.stravaClientSecret,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]

        let response = try await postTokenRequest(params: params)
        storeTokens(response)
    }

    // MARK: - Fetch athlete profile

    func fetchAthlete() async throws -> StravaAthlete {
        try await refreshTokenIfNeeded()

        guard let accessToken = KeychainHelper.load(for: KeychainHelper.stravaAccessToken) else {
            throw StravaError.notAuthenticated
        }

        guard let url = URL(string: Self.athleteURL) else { throw StravaError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8)
            throw StravaError.httpError(statusCode, body)
        }

        do {
            return try JSONDecoder().decode(StravaAthlete.self, from: data)
        } catch {
            throw StravaError.decodingFailed
        }
    }

    // MARK: - Keychain state accessors

    var storedAthleteId: Int64? {
        guard let s = KeychainHelper.load(for: KeychainHelper.stravaAthleteId),
              let id = Int64(s) else { return nil }
        return id
    }

    var isAuthenticated: Bool {
        KeychainHelper.load(for: KeychainHelper.stravaAccessToken) != nil
    }

    // MARK: - Private helpers

    private func requestAuthCode(contextProvider: ASWebAuthenticationPresentationContextProviding) async throws -> String {
        guard let url = Self.authorizationURL(clientID: Config.stravaClientID) else {
            throw StravaError.invalidURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "enzo"
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: StravaError.authCancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: StravaError.missingCode)
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = contextProvider
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    private func exchangeCode(_ code: String) async throws -> StravaTokenResponse {
        let params: [String: String] = [
            "client_id": Config.stravaClientID,
            "client_secret": Config.stravaClientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ]
        return try await postTokenRequest(params: params)
    }

    private func postTokenRequest(params: [String: String]) async throws -> StravaTokenResponse {
        guard let url = URL(string: Self.tokenURL) else { throw StravaError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(params)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw StravaError.tokenExchangeFailed(body)
        }

        do {
            return try JSONDecoder().decode(StravaTokenResponse.self, from: data)
        } catch {
            throw StravaError.decodingFailed
        }
    }

    private func storeTokens(_ response: StravaTokenResponse) {
        KeychainHelper.save(response.accessToken, for: KeychainHelper.stravaAccessToken)
        KeychainHelper.save(response.refreshToken, for: KeychainHelper.stravaRefreshToken)
        KeychainHelper.save(String(response.expiresAt), for: KeychainHelper.stravaTokenExpiry)
    }
}
