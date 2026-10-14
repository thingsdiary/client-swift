import Foundation

extension ThingsDiaryClient {
    @discardableResult
    public func register(
        login: String,
        password: String,
        secretKey: String,
        kdfSalt: String
    ) async throws -> ThingsDiaryAuthState {
        let credentials = try ThingsDiaryCrypto.deriveCredentials(
            secretKey: secretKey,
            salt: kdfSalt
        )
        let body = RegisterRequest(
            login: login,
            password: password,
            kdfSalt: kdfSalt,
            encryptionPublicKey: credentials.encryptionPublicKey.base64EncodedString(),
            signingPublicKey: credentials.signingPublicKey.base64EncodedString()
        )
        let encodedBody = try JSONEncoder().encode(body)
        let request = ThingsDiaryHTTPRequest(
            url: url(["v1", "auth", "register"]),
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: encodedBody
        )
        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw ThingsDiaryClientError.httpStatus(response.statusCode, body: response.body)
        }

        let result = try JSONDecoder().decode(RegisterResponse.self, from: response.body)
        let state = ThingsDiaryAuthState(token: result.token, credentials: credentials)
        authentication = state
        return state
    }
}

private struct RegisterRequest: Encodable {
    let login: String
    let password: String
    let kdfSalt: String
    let encryptionPublicKey: String
    let signingPublicKey: String

    enum CodingKeys: String, CodingKey {
        case login, password
        case kdfSalt = "kdf_salt"
        case encryptionPublicKey = "encryption_public_key"
        case signingPublicKey = "signature_public_key"
    }
}

private struct RegisterResponse: Decodable, Sendable {
    let token: String
}
