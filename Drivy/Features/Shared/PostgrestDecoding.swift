import Foundation

/// PostgREST serialization tolerance for the columns the core screens read.
///
/// A Postgres `numeric` may arrive as a JSON number or as a string, and a
/// `timestamptz` may or may not carry fractional seconds. Accepting both shapes
/// keeps a formatting detail from failing a whole screen, which is the same
/// stance `SupabaseDriveRepository` already takes for the daily score.
extension KeyedDecodingContainer {

    func decodeDecimal(forKey key: Key) throws -> Double {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Double(value)
        }

        let text = try decode(String.self, forKey: key)
        guard let value = Double(text) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Not a decimal: \(text)"
            )
        }
        return value
    }

    func decodeInteger(forKey key: Key) throws -> Int {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(Double.self, forKey: key) {
            return Int(value.rounded())
        }

        let text = try decode(String.self, forKey: key)
        if let value = Int(text) {
            return value
        }
        if let value = Double(text) {
            return Int(value.rounded())
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Not an integer: \(text)"
        )
    }

    func decodeTimestamp(forKey key: Key) throws -> Date {
        let text = try decode(String.self, forKey: key)
        guard let date = PostgrestTimestamp.date(from: text) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Not an ISO-8601 timestamp: \(text)"
            )
        }
        return date
    }
}

/// `timestamptz` parsing, with and without fractional seconds.
enum PostgrestTimestamp {

    static func date(from text: String) -> Date? {
        if let date = withFractionalSeconds.date(from: text) {
            return date
        }
        return plain.date(from: text)
    }

    private static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
