# Authentication Reference — Sign in with Apple + OAuth

## Table of Contents
1. Sign in with Apple (primary)
2. Critical gotchas
3. Server-side verification
4. OAuth with ASWebAuthenticationSession
5. Token storage
6. Auth state management

---

## 1. Sign in with Apple (primary)

Sign in with Apple is mandatory if your app offers any third-party social login (App Store Review
Guideline 4.8). Make it the primary auth path regardless — it's the smoothest UX on iOS.

```swift
import AuthenticationServices
import CryptoKit

struct SignInView: View {
    @Environment(\.authManager) private var authManager
    @State private var currentNonce: String?

    var body: some View {
        VStack(spacing: 24) {
            // App logo, welcome text, etc.

            SignInWithAppleButton(.signIn) { request in
                let nonce = randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = sha256(nonce)
            } onCompletion: { result in
                switch result {
                case .success(let auth):
                    guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
                    Task {
                        await handleAppleSignIn(credential: credential)
                    }
                case .failure(let error):
                    // Log error, show alert
                    print("Sign in failed: \(error.localizedDescription)")
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
        }
        .padding()
    }

    private func handleAppleSignIn(credential: ASAuthorizationAppleIDCredential) async {
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8),
              let nonce = currentNonce else { return }

        // Send to your backend:
        // - identityToken (JWT to verify server-side)
        // - nonce (to prevent replay attacks)
        // - fullName (ONLY sent on first sign-in — persist immediately)
        // - email (may be private relay — don't use as primary key)

        do {
            let tokens = try await authManager.signInWithApple(
                identityToken: tokenString,
                nonce: nonce,
                fullName: credential.fullName,
                email: credential.email
            )
            await authManager.setTokens(tokens)
        } catch {
            // Handle error
        }
    }
}

// MARK: - Nonce generation

private func randomNonceString(length: Int = 32) -> String {
    var bytes = [UInt8](repeating: 0, count: length)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    return bytes.map { charset[Int($0) % charset.count] }.map(String.init).joined()
}

private func sha256(_ input: String) -> String {
    let data = Data(input.utf8)
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}
```

## 2. Critical gotchas

### Apple sends name/email ONLY on first sign-in

After the first authorization, subsequent logins return only the `user` identifier (sub).
Your backend MUST persist `fullName` and `email` on the very first call. If you miss it,
the user has to revoke your app in Settings > Apple ID > Sign-In & Security and re-authorize.

### Use `sub` as the primary key, not email

Apple may provide a private-relay email (e.g., `abc123@privaterelay.appleid.com`) that can
change. The `user` property (maps to `sub` in the JWT) is the immutable account identifier.

### Nonce is required

Always generate a cryptographically random nonce with `SecRandomCopyBytes`, hash it with SHA-256,
and send the hash in the request. Verify the nonce server-side to prevent replay attacks.

## 3. Server-side verification

Your backend must:
1. Fetch Apple's public keys from `https://appleid.apple.com/auth/keys`
2. Verify the JWT signature against Apple's JWKS
3. Check `iss` == `https://appleid.apple.com`
4. Check `aud` == your app's bundle ID
5. Check `exp` is in the future
6. Check the nonce matches what the client sent

Never trust the identity token without server-side verification.

## 4. OAuth with ASWebAuthenticationSession

For third-party OAuth (Google, GitHub, etc.), use `ASWebAuthenticationSession` — not an embedded
`WKWebView`. Apple requires it for many flows and gives users the trusted system sign-in sheet.

```swift
import AuthenticationServices

@MainActor
final class OAuthHandler: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }

    func signInWithGoogle() async throws -> String {
        let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth?...")!
        let callbackScheme = "yourapp"

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url = callbackURL,
                      let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                          .queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: APIError.invalidResponse)
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }
    }
}
```

## 5. Token storage — Keychain

Store auth tokens in the Keychain, never in UserDefaults or files:

```swift
import Security

enum KeychainHelper {
    static func save(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)  // Remove existing
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(for key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }

    static func delete(for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case saveFailed(OSStatus)
    }
}
```

## 6. Auth state management

Combine the AuthManager actor with an observable auth state for the UI:

```swift
@MainActor
@Observable
final class AuthState {
    enum Status: Sendable {
        case unknown    // checking keychain
        case signedOut
        case signedIn(User)
    }

    private(set) var status: Status = .unknown
    private let authManager: AuthManager

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    func checkExistingSession() async {
        if let user = await authManager.restoreSession() {
            status = .signedIn(user)
        } else {
            status = .signedOut
        }
    }

    func signOut() async {
        await authManager.clearTokens()
        status = .signedOut
    }
}

// In App.swift — gate content on auth state
struct ContentView: View {
    @State private var authState: AuthState

    var body: some View {
        Group {
            switch authState.status {
            case .unknown:
                ProgressView()
            case .signedOut:
                SignInView()
            case .signedIn:
                MainTabView()
            }
        }
        .task { await authState.checkExistingSession() }
    }
}
```
