import Foundation

public extension JSONDecoder {
    /// Decoder configured for Jira REST API responses.
    /// Atlassian timestamps come in ISO 8601 with milliseconds and timezone offset,
    /// e.g. "2025-02-12T10:34:01.123+0000".
    static var jira: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            for formatter in jiraDateFormatters {
                if let date = formatter.date(from: raw) { return date }
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised Jira date format: \(raw)"
            )
        }
        return d
    }
}

private let jiraDateFormatters: [DateFormatter] = {
    let formats = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXX",
        "yyyy-MM-dd"
    ]
    return formats.map { f in
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = f
        return df
    }
}()
