import CryptoKit
import Foundation
import Security

/// Nonce helpers for "Sign in with Apple".
///
/// Apple signs the SHA256 hash of the nonce into the identity token, while
/// Supabase expects the raw nonce and re-computes the hash when verifying, so
/// both values must come from the same random string.
enum AppleNonce {

    /// Allowed nonce characters (alphanumeric plus `-._`). Apple rejects
    /// anything else.
    static let charset: [Character] = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
    )

    /// Cryptographically random nonce.
    static func random(length: Int = 32) -> String {
        guard length > 0 else { return "" }

        var result = ""
        result.reserveCapacity(length)
        var remaining = length

        while remaining > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            guard status == errSecSuccess else {
                preconditionFailure("SecRandomCopyBytes failed with status \(status)")
            }

            for byte in randomBytes {
                guard remaining > 0 else { break }
                // Reject the values that fall outside the charset so every
                // character is uniformly distributed.
                if Int(byte) < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }

        return result
    }

    /// Lowercase hexadecimal SHA256 digest, as required by Apple.
    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
