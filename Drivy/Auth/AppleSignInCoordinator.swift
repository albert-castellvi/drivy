import AuthenticationServices
import Foundation
import UIKit

/// Sign in with Apple through `ASAuthorizationController` (the native flow, not
/// a web OAuth redirect), wrapped in async/await so the view model can await a
/// single credential.
@MainActor
final class AppleSignInCoordinator: NSObject, AppleSignInProviding {

    private var continuation: CheckedContinuation<AppleCredential, Error>?
    private var rawNonce: String?

    func requestCredential() async throws -> AppleCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let rawNonce = AppleNonce.random()
            self.rawNonce = rawNonce

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            // Apple signs the hash into the token; Supabase receives the raw
            // nonce and verifies the pair.
            request.nonce = AppleNonce.sha256Hex(rawNonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(with result: Result<AppleCredential, Error>) {
        guard let continuation = continuation else { return }
        self.continuation = nil
        self.rawNonce = nil

        switch result {
        case .success(let credential):
            continuation.resume(returning: credential)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(with: .failure(AppleSignInError.missingIdentityToken))
            return
        }

        guard let identityTokenData = credential.identityToken,
              let idToken = String(data: identityTokenData, encoding: .utf8),
              let rawNonce = self.rawNonce else {
            finish(with: .failure(AppleSignInError.missingIdentityToken))
            return
        }

        finish(with: .success(AppleCredential(idToken: idToken, rawNonce: rawNonce)))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            finish(with: .failure(AppleSignInError.cancelled))
            return
        }

        // The upstream description is dropped (S5): an `ASAuthorizationError`
        // description can name the account or the failure context, and it used
        // to reach Sentry through this payload. Nothing reads it any more; the
        // view model reports `CrashReport.appleSignInFailed`.
        finish(with: .failure(AppleSignInError.failed(CrashReport.appleSignInFailed.code)))
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = windowScenes.first { $0.activationState == .foregroundActive } ?? windowScenes.first
        return activeScene?.keyWindow ?? ASPresentationAnchor()
    }
}
