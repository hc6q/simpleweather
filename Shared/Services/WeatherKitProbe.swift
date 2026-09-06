import CoreLocation
import Foundation
import WeatherKit

enum WeatherKitProbe {
    // No app timeout wrapper: surface the NSError actually returned by WeatherKit.
    static func run(location: CLLocation, sink: @escaping WeatherDiagnosticSink) async {
        await runQueries(operation: { query in
            switch query {
            case "current":
                _ = try await WeatherService.shared.weather(for: location, including: .current)
            case "hourly":
                _ = try await WeatherService.shared.weather(for: location, including: .hourly)
            case "daily":
                _ = try await WeatherService.shared.weather(for: location, including: .daily)
            default: preconditionFailure("Unsupported diagnostic query")
            }
        }, sink: sink)
    }

    // Injectable operation verifies sequencing and failure attribution without querying Apple in CI.
    static func runQueries(operation: @Sendable (String) async throws -> Void,
                           sink: @escaping WeatherDiagnosticSink) async {
        let queries = ["current", "hourly", "daily"]
        for (index, query) in queries.enumerated() {
            do {
                try Task.checkCancellation()
                try await tracedWeatherRequest(query: query, sink: sink) { try await operation(query) }
            } catch {
                if query == "current" || Task.isCancelled || error is CancellationError {
                    for skipped in queries.dropFirst(index + 1) {
                        await sink(WeatherRequestEvent(query: skipped, status: "NOT RUN (\(query) failed or cancelled)"))
                    }
                    return
                }
                // A failed hourly request does not prevent testing daily independently.
            }
        }
    }
}
