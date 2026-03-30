import Foundation
import Testing
@testable import EnzoApp

@Suite("KeychainHelper")
struct KeychainHelperTests {

    // Use test-specific keys to avoid colliding with real app data
    private let testKey = "test_keychain_helper_\(UUID().uuidString)"

    @Test("saves and loads a string value")
    func saveAndLoad() {
        KeychainHelper.save("hello_world", for: testKey)
        let loaded = KeychainHelper.load(for: testKey)
        #expect(loaded == "hello_world")
        KeychainHelper.delete(for: testKey)
    }

    @Test("returns nil for missing key")
    func loadMissing() {
        let loaded = KeychainHelper.load(for: "nonexistent_key_\(UUID().uuidString)")
        #expect(loaded == nil)
    }

    @Test("overwrites existing value on second save")
    func overwrite() {
        KeychainHelper.save("first", for: testKey)
        KeychainHelper.save("second", for: testKey)
        let loaded = KeychainHelper.load(for: testKey)
        #expect(loaded == "second")
        KeychainHelper.delete(for: testKey)
    }

    @Test("delete removes the value")
    func deleteRemoves() {
        KeychainHelper.save("to_delete", for: testKey)
        KeychainHelper.delete(for: testKey)
        let loaded = KeychainHelper.load(for: testKey)
        #expect(loaded == nil)
    }

    @Test("delete returns true when item existed")
    func deleteReturnsTrueOnHit() {
        KeychainHelper.save("value", for: testKey)
        let result = KeychainHelper.delete(for: testKey)
        #expect(result == true)
    }

    @Test("delete returns false when item did not exist")
    func deleteReturnsFalseOnMiss() {
        let result = KeychainHelper.delete(for: "nonexistent_\(UUID().uuidString)")
        #expect(result == false)
    }

    @Test("round-trips Strava access token key constant")
    func stravaAccessTokenConstant() {
        KeychainHelper.save("test_access_token", for: KeychainHelper.stravaAccessToken)
        let loaded = KeychainHelper.load(for: KeychainHelper.stravaAccessToken)
        #expect(loaded == "test_access_token")
        KeychainHelper.delete(for: KeychainHelper.stravaAccessToken)
    }
}
