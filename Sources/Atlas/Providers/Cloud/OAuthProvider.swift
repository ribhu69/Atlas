import Foundation
import AuthenticationServices

struct OAuthToken: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scope: String?

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60) // Refresh 60s early
    }
}

@MainActor
class OAuthProviderBase: NSObject {
    var token: OAuthToken?
    let clientID: String
    let clientSecret: String
    let authURL: URL
    let tokenURL: URL
    let redirectURI: String
    let scopes: [String]
    private let keychainKey: String

    init(clientID: String, clientSecret: String, authURL: URL, tokenURL: URL, redirectURI: String, scopes: [String], keychainKey: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.authURL = authURL
        self.tokenURL = tokenURL
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.keychainKey = keychainKey
        super.init()
        self.token = loadToken()
    }

    func authenticate(presentingWindow: ASPresentationAnchor? = nil) async throws {
        var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
        ]

        let authURL = components.url!
        let callbackScheme = URL(string: redirectURI)!.scheme!

        let code: String = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: ProviderError.authenticationFailed(error.localizedDescription))
                    return
                }
                guard let url = callbackURL,
                      let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                          .queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: ProviderError.authenticationFailed("No authorization code"))
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        try await exchangeCodeForToken(code: code)
    }

    func validAccessToken() async throws -> String {
        guard let token else { throw ProviderError.authenticationFailed("Not authenticated") }
        if token.isExpired, let refresh = token.refreshToken {
            try await refreshToken(refreshToken: refresh)
        }
        guard let current = self.token else { throw ProviderError.authenticationFailed("Token expired") }
        return current.accessToken
    }

    func signOut() {
        self.token = nil
        deleteToken()
    }

    private func exchangeCodeForToken(code: String) async throws {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectURI)&client_id=\(clientID)&client_secret=\(clientSecret)"
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONDecoder().decode(TokenResponse.self, from: data)
        self.token = OAuthToken(
            accessToken: json.access_token,
            refreshToken: json.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(json.expires_in ?? 3600)),
            scope: json.scope
        )
        saveToken()
    }

    func refreshToken(refreshToken: String) async throws {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientID)&client_secret=\(clientSecret)"
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONDecoder().decode(TokenResponse.self, from: data)
        self.token = OAuthToken(
            accessToken: json.access_token,
            refreshToken: json.refresh_token ?? refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(json.expires_in ?? 3600)),
            scope: json.scope
        )
        saveToken()
    }

    private func saveToken() {
        guard let data = try? JSONEncoder().encode(token) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadToken() -> OAuthToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(OAuthToken.self, from: data)
    }

    private func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private struct TokenResponse: Codable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int?
        let scope: String?
    }
}

extension OAuthProviderBase: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
