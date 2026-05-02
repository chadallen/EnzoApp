import Testing
import Foundation
@testable import EnzoApp

// MARK: - MockURLProtocol
//
// A URLProtocol subclass that intercepts requests and returns canned responses.
// Each test creates its own ephemeral URLSession with a fresh protocol class
// registration so tests can run independently.
//
// httpBody is read from the httpBodyStream when present because URLSession moves
// the body into a stream before handing the request to a URLProtocol handler.

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    // Closure set per-test session. Keyed by session configuration identifier so
    // concurrent tests do not share state.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        // Reconstitute body from stream if needed so tests can inspect it.
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            var data = Data()
            stream.open()
            let bufSize = 1024
            var buf = [UInt8](repeating: 0, count: bufSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buf, maxLength: bufSize)
                if read > 0 { data.append(contentsOf: buf[0..<read]) }
            }
            stream.close()
            captured.httpBody = data
        }

        do {
            let (response, data) = try handler(captured)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeHTTPResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

// MARK: - SyncService.starSegment tests
//
// Tests are serialized to avoid concurrent mutation of MockURLProtocol.handler.

@Suite("SyncService — starSegment", .serialized)
struct StarSegmentTests {

    private func makeService(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> SyncService {
        MockURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return SyncService(stravaService: StravaService(), urlSession: session)
    }

    private func successHandler(statusCode: Int = 200) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        return { request in
            let url = request.url ?? URL(string: "https://example.com")!
            return (makeHTTPResponse(url: url, statusCode: statusCode), Data())
        }
    }

    // MARK: - Success paths

    @Test("starSegment succeeds on HTTP 200")
    func starSegmentSuccess() async throws {
        let service = makeService(handler: successHandler(statusCode: 200))
        // Should not throw
        try await service.starSegment(segmentId: 12345, starred: true, accessToken: "test-token")
    }

    @Test("unstarSegment succeeds on HTTP 200")
    func unstarSegmentSuccess() async throws {
        let service = makeService(handler: successHandler(statusCode: 200))
        try await service.starSegment(segmentId: 12345, starred: false, accessToken: "test-token")
    }

    @Test("starSegment succeeds on HTTP 201")
    func starSegmentSucceeds201() async throws {
        let service = makeService(handler: successHandler(statusCode: 201))
        try await service.starSegment(segmentId: 1, starred: true, accessToken: "tok")
    }

    // MARK: - Request shape

    @Test("starSegment sends PUT request")
    func starSegmentUsesPUT() async throws {
        var capturedMethod: String?
        let service = makeService { request in
            capturedMethod = request.httpMethod
            let url = request.url ?? URL(string: "https://example.com")!
            return (makeHTTPResponse(url: url, statusCode: 200), Data())
        }

        try await service.starSegment(segmentId: 99, starred: true, accessToken: "tok")
        #expect(capturedMethod == "PUT")
    }

    @Test("starSegment targets correct URL")
    func starSegmentTargetsCorrectURL() async throws {
        var capturedURL: URL?
        let service = makeService { request in
            capturedURL = request.url
            let url = request.url ?? URL(string: "https://example.com")!
            return (makeHTTPResponse(url: url, statusCode: 200), Data())
        }

        try await service.starSegment(segmentId: 42, starred: true, accessToken: "tok")
        #expect(capturedURL?.absoluteString == "https://www.strava.com/api/v3/segments/42/starred")
    }

    @Test("starSegment sends Authorization header")
    func starSegmentAuthorizationHeader() async throws {
        var capturedAuth: String?
        let service = makeService { request in
            capturedAuth = request.value(forHTTPHeaderField: "Authorization")
            let url = request.url ?? URL(string: "https://example.com")!
            return (makeHTTPResponse(url: url, statusCode: 200), Data())
        }

        try await service.starSegment(segmentId: 7, starred: true, accessToken: "my-token")
        #expect(capturedAuth == "Bearer my-token")
    }

    @Test("starSegment sends starred=true in JSON body")
    func starSegmentBodyStarredTrue() async throws {
        var capturedBody: [String: Bool]?
        let service = makeService { request in
            if let data = request.httpBody {
                capturedBody = try? JSONDecoder().decode([String: Bool].self, from: data)
            }
            let url = request.url ?? URL(string: "https://example.com")!
            return (makeHTTPResponse(url: url, statusCode: 200), Data())
        }

        try await service.starSegment(segmentId: 1, starred: true, accessToken: "tok")
        #expect(capturedBody?["starred"] == true)
    }

    @Test("starSegment sends starred=false in JSON body for unstar")
    func starSegmentBodyStarredFalse() async throws {
        var capturedBody: [String: Bool]?
        let service = makeService { request in
            if let data = request.httpBody {
                capturedBody = try? JSONDecoder().decode([String: Bool].self, from: data)
            }
            let url = request.url ?? URL(string: "https://example.com")!
            return (makeHTTPResponse(url: url, statusCode: 200), Data())
        }

        try await service.starSegment(segmentId: 1, starred: false, accessToken: "tok")
        #expect(capturedBody?["starred"] == false)
    }

    // MARK: - Error paths

    @Test("starSegment throws rateLimited on HTTP 429")
    func starSegmentRateLimited() async throws {
        let service = makeService { request in
            let url = request.url ?? URL(string: "https://example.com")!
            return (makeHTTPResponse(url: url, statusCode: 429), Data())
        }

        var caughtRateLimited = false
        do {
            try await service.starSegment(segmentId: 1, starred: true, accessToken: "tok")
        } catch SyncError.rateLimited {
            caughtRateLimited = true
        }
        #expect(caughtRateLimited, "Expected SyncError.rateLimited on HTTP 429")
    }

    @Test("starSegment throws fetchFailed on HTTP 401")
    func starSegmentUnauthorized() async throws {
        let service = makeService { request in
            let url = request.url ?? URL(string: "https://example.com")!
            return (makeHTTPResponse(url: url, statusCode: 401), Data())
        }

        var threw = false
        do {
            try await service.starSegment(segmentId: 1, starred: true, accessToken: "tok")
        } catch SyncError.fetchFailed {
            threw = true
        }
        #expect(threw, "Expected SyncError.fetchFailed on HTTP 401")
    }

    @Test("starSegment throws fetchFailed on HTTP 500")
    func starSegmentServerError() async throws {
        let service = makeService { request in
            let url = request.url ?? URL(string: "https://example.com")!
            return (makeHTTPResponse(url: url, statusCode: 500), Data())
        }

        var threw = false
        do {
            try await service.starSegment(segmentId: 1, starred: true, accessToken: "tok")
        } catch SyncError.fetchFailed {
            threw = true
        }
        #expect(threw, "Expected SyncError.fetchFailed on HTTP 500")
    }

    @Test("starSegment throws on network error")
    func starSegmentNetworkError() async throws {
        let service = makeService { _ in
            throw URLError(.notConnectedToInternet)
        }

        var threw = false
        do {
            try await service.starSegment(segmentId: 1, starred: true, accessToken: "tok")
        } catch {
            threw = true
        }
        #expect(threw, "Expected error to be thrown on network failure")
    }
}
