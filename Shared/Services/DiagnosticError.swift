import Foundation
import OSLog

// Diagnostics are available in Release for the temporary physical-device investigation.
// Never interpolate an NSError or arbitrary userInfo object directly into logs.
struct DiagnosticError: Equatable, Sendable {
    let domain: String
    let code: Int
    let description: String
    let userInfo: String
    let underlying: [DiagnosticError]
    let traversalNote: String?

    init(_ error: Error) {
        self = Self.capture(error as NSError, visited: [], depth: 0)
    }

    private static func capture(_ error: NSError, visited: Set<ObjectIdentifier>, depth: Int) -> Self {
        var visited = visited
        let repeated = !visited.insert(ObjectIdentifier(error)).inserted
        let stop = repeated || depth >= 16
        let child = error.userInfo[NSUnderlyingErrorKey] as? Error
        let safeInfo = sanitize(error.userInfo)
        let data = try? JSONSerialization.data(withJSONObject: safeInfo, options: [.prettyPrinted, .sortedKeys])
        return Self(domain: redact(error.domain), code: error.code,
                    description: redact(error.localizedDescription),
                    userInfo: data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}",
                    underlying: stop ? [] : child.map { [capture($0 as NSError, visited: visited, depth: depth + 1)] } ?? [],
                    traversalNote: stop ? "Underlying traversal stopped: cycle or depth limit (16)." : nil)
    }

    private init(domain: String, code: Int, description: String, userInfo: String,
                 underlying: [DiagnosticError], traversalNote: String?) {
        self.domain = domain
        self.code = code
        self.description = description
        self.userInfo = userInfo
        self.underlying = underlying
        self.traversalNote = traversalNote
    }

    static func sensitiveKey(_ key: String) -> Bool {
        let key = key.lowercased()
        return ["token", "password", "secret", "authorization", "cookie", "credential",
                "api_key", "apikey", "api-key", "privatekey", "private_key", "p12"].contains { key.contains($0) }
    }

    private static func sanitize(_ value: Any, depth: Int = 0) -> Any {
        guard depth < 12 else { return "[nested value omitted]" }
        if value is NSError { return "[NSError: see Underlying Error when present]" }
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, entry in
                result[entry.key] = sensitiveKey(entry.key) ? "[REDACTED]" : sanitize(entry.value, depth: depth + 1)
            }
        }
        if let array = value as? [Any] { return array.map { sanitize($0, depth: depth + 1) } }
        if let string = value as? String { return redact(string) }
        if let url = value as? URL { return redact(url.absoluteString) }
        if let number = value as? NSNumber { return number }
        if value is NSNull { return NSNull() }
        if let date = value as? Date { return ISO8601DateFormatter().string(from: date) }
        if let data = value as? Data { return "[\(data.count) bytes omitted]" }
        return "[\(String(describing: type(of: value))) value omitted]"
    }

    static func redact(_ string: String) -> String {
        let patterns = [
            (#"(?i)\b(?:Bearer|Basic)\s+[A-Za-z0-9+/_.=~-]+"#, "[REDACTED]"),
            (#"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#, "[REDACTED JWT]"),
            (#"(?i)((?:access_token|refresh_token|token|api[_-]?key|password|secret|authorization|cookie)\s*[\"']?\s*[:=]\s*[\"']?)[^\s\"'&,;}]+"#, "$1[REDACTED]"),
            (#"(https?://)[^/@\s]+:[^/@\s]+@"#, "$1[REDACTED]@"),
            (#"(?s)-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----"#, "[REDACTED PRIVATE KEY]")
        ]
        return patterns.reduce(string) { value, pattern in
            value.replacingOccurrences(of: pattern.0, with: pattern.1, options: .regularExpression)
        }
    }

    var text: String {
        var value = "Domain: \(domain)\nCode: \(code)\nDescription: \(description)\nuserInfo: \(userInfo)"
        for (index, child) in underlying.enumerated() {
            value += "\nUnderlying Error \(index + 1):\n\(child.text)"
        }
        if let traversalNote { value += "\n\(traversalNote)" }
        return value
    }
}

enum DiagnosticLog {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SimpleWeather", category: "Diagnostics")

    static func event(_ stage: String, _ detail: String) {
        logger.info("\(stage, privacy: .public): \(detail, privacy: .private)")
    }

    @discardableResult static func failure(_ stage: String, _ error: Error) -> DiagnosticError {
        let nsError = error as NSError
        let captured = DiagnosticError(nsError)
        log(stage, captured)
        return captured
    }

    private static func log(_ stage: String, _ error: DiagnosticError) {
        logger.error("\(stage, privacy: .public) domain=\(error.domain, privacy: .public) code=\(error.code, privacy: .public) localizedDescription=\(error.description, privacy: .private) userInfo=\(error.userInfo, privacy: .private)")
        for child in error.underlying { log(stage + ".NSUnderlyingErrorKey", child) }
    }
}

struct WeatherRequestEvent: Sendable {
    let query: String
    let status: String
    var error: DiagnosticError?
}

typealias WeatherDiagnosticSink = @Sendable (WeatherRequestEvent) async -> Void

func tracedWeatherRequest<T>(query: String, sink: WeatherDiagnosticSink?,
                             operation: () async throws -> T) async throws -> T {
    DiagnosticLog.event("WeatherKit \(query)", "START")
    await sink?(WeatherRequestEvent(query: query, status: "RUNNING"))
    do {
        let result = try await operation()
        DiagnosticLog.event("WeatherKit \(query)", "OK")
        await sink?(WeatherRequestEvent(query: query, status: "OK"))
        return result
    } catch {
        let captured = DiagnosticLog.failure("WeatherKit \(query)", error)
        await sink?(WeatherRequestEvent(query: query, status: error is CancellationError ? "CANCELLED" : "ERROR", error: captured))
        throw error // Preserve the exact native error for the caller.
    }
}
