import CryptoKit
import Foundation

public struct PKCEPair: Sendable, Equatable {
    public let verifier: String
    public let challenge: String
    public let method: String

    public init(verifier: String, challenge: String, method: String = "S256") {
        self.verifier = verifier
        self.challenge = challenge
        self.method = method
    }
}

public enum PKCEGenerator {
    /// Generates a fresh PKCE pair using SHA256 challenge.
    /// Verifier length is 64 unreserved characters per RFC 7636.
    public static func make() -> PKCEPair {
        let verifier = randomURLSafe(length: 64)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncodedString()
        return PKCEPair(verifier: verifier, challenge: challenge)
    }

    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func randomURLSafe(length: Int) -> String {
        var out = ""
        out.reserveCapacity(length)
        for _ in 0..<length {
            let idx = Int.random(in: 0..<alphabet.count)
            out.append(alphabet[idx])
        }
        return out
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
