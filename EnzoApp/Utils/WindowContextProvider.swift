import AuthenticationServices
import UIKit

/// Provides the key window as the presentation anchor for ASWebAuthenticationSession.
/// Used by AppState.authenticate(contextProvider:) to present the Strava OAuth sheet.
final class WindowContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
