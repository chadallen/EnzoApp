import Foundation
import Testing
@testable import EnzoApp

@Suite("StravaService")
struct StravaServiceTests {

    // MARK: - Authorization URL construction

    @Test("authorization URL has correct base")
    func authURLBase() throws {
        let url = try #require(StravaService.authorizationURL(clientID: "12345"))
        #expect(url.scheme == "https")
        #expect(url.host == "www.strava.com")
        #expect(url.path == "/oauth/authorize")
    }

    @Test("authorization URL contains client_id")
    func authURLClientID() throws {
        let url = try #require(StravaService.authorizationURL(clientID: "99999"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let clientID = items.first(where: { $0.name == "client_id" })?.value
        #expect(clientID == "99999")
    }

    @Test("authorization URL contains correct redirect_uri")
    func authURLRedirectURI() throws {
        let url = try #require(StravaService.authorizationURL(clientID: "1"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let redirectURI = items.first(where: { $0.name == "redirect_uri" })?.value
        #expect(redirectURI == "enzo://oauth")
    }

    @Test("authorization URL includes activity:read_all scope")
    func authURLScope() throws {
        let url = try #require(StravaService.authorizationURL(clientID: "1"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let scope = items.first(where: { $0.name == "scope" })?.value ?? ""
        #expect(scope.contains("activity:read_all"))
        #expect(scope.contains("read"))
    }

    @Test("authorization URL uses response_type=code")
    func authURLResponseType() throws {
        let url = try #require(StravaService.authorizationURL(clientID: "1"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let responseType = items.first(where: { $0.name == "response_type" })?.value
        #expect(responseType == "code")
    }

    // MARK: - Token response decoding

    @Test("decodes token response JSON correctly")
    func tokenResponseDecoding() throws {
        let json = """
        {
            "access_token": "abc123",
            "refresh_token": "refresh456",
            "expires_at": 1999999999,
            "athlete": {
                "id": 12345678,
                "firstname": "Chad",
                "lastname": "Allen"
            }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(StravaTokenResponse.self, from: data)

        #expect(response.accessToken == "abc123")
        #expect(response.refreshToken == "refresh456")
        #expect(response.expiresAt == 1999999999)
        #expect(response.athlete?.id == 12345678)
        #expect(response.athlete?.firstName == "Chad")
        #expect(response.athlete?.lastName == "Allen")
    }

    @Test("decodes token response without embedded athlete")
    func tokenResponseNoAthlete() throws {
        let json = """
        {
            "access_token": "tok",
            "refresh_token": "ref",
            "expires_at": 1000000000
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
        #expect(response.athlete == nil)
    }

    // MARK: - StravaAthlete model

    @Test("displayName concatenates first and last name")
    func displayName() {
        let athlete = StravaAthlete(id: 1, firstName: "Chad", lastName: "Allen")
        #expect(athlete.displayName == "Chad Allen")
    }

    @Test("athlete decodes from JSON")
    func athleteDecoding() throws {
        let json = """
        {"id": 987654321, "firstname": "Jane", "lastname": "Doe"}
        """
        let data = try #require(json.data(using: .utf8))
        let athlete = try JSONDecoder().decode(StravaAthlete.self, from: data)
        #expect(athlete.id == 987654321)
        #expect(athlete.displayName == "Jane Doe")
    }
}
