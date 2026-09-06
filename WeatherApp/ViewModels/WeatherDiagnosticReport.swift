import CoreLocation
import Foundation
import Observation

struct DiagnosticStage {
    var status = "NOT RUN"
    var detail = ""
    var error: DiagnosticError?
    var text: String { status + (detail.isEmpty ? "" : " — " + detail) }
}

@MainActor @Observable
final class WeatherDiagnosticReport {
    var mode = "Automatic refresh"
    var startedAt: Date?
    var authorization = "NOT CHECKED"
    var location = DiagnosticStage()
    var coordinates: Coordinates?
    var geocoding = DiagnosticStage()
    var requests: [String: DiagnosticStage] = [:]
    var pipeline = DiagnosticStage()
    var events: [String] = []

    static func authorizationName(_ status: CLAuthorizationStatus) -> String {
        let name: String
        switch status {
        case .notDetermined: name = "notDetermined"
        case .restricted: name = "restricted"
        case .denied: name = "denied"
        case .authorizedAlways: name = "authorizedAlways"
        case .authorizedWhenInUse: name = "authorizedWhenInUse"
        @unknown default: name = "unknown"
        }
        return "\(name) (\(status.rawValue))"
    }

    func begin(mode: String, authorization: CLAuthorizationStatus) {
        self.mode = mode
        startedAt = .now
        location = DiagnosticStage()
        coordinates = nil
        geocoding = DiagnosticStage()
        pipeline = DiagnosticStage()
        requests = [:]
        events = []
        updateAuthorization(authorization)
    }

    func updateAuthorization(_ status: CLAuthorizationStatus) {
        authorization = Self.authorizationName(status)
        event("Location Authorization: \(authorization)")
    }

    func received(_ location: CLLocation) {
        coordinates = Coordinates(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        self.location = DiagnosticStage(status: "OK", detail: "accuracy=\(location.horizontalAccuracy)m; timestamp=\(location.timestamp.ISO8601Format())")
        event("CLLocation: \(self.location.text); Location: \(locationText)")
    }

    func received(_ result: GeocodingResolution) {
        geocoding = DiagnosticStage(status: result.status, detail: result.place.name, error: result.error)
        event("Geocoding: \(geocoding.text)")
    }

    func receive(_ event: WeatherRequestEvent) {
        requests[event.query] = DiagnosticStage(status: event.status, error: event.error)
        self.event("WeatherKit .\(event.query): \(event.status)" +
                   (event.error.map { " Domain=\($0.domain) Code=\($0.code)" } ?? ""))
    }

    func event(_ message: String) {
        events.append("\(Date.now.ISO8601Format()) \(message)")
        if events.count > 120 { events.removeFirst(events.count - 120) }
        DiagnosticLog.event(mode, message)
    }

    var locationText: String {
        coordinates.map { "\($0.latitude), \($0.longitude)" } ?? "NOT OBTAINED"
    }

    var weatherStatus: String {
        let values = requests.values.map(\.status)
        if values.contains("RUNNING") { return "RUNNING" }
        if values.contains("ERROR") { return "ERROR" }
        if values.contains("CANCELLED") { return "CANCELLED" }
        if !values.isEmpty && values.allSatisfy({ $0 == "OK" }) { return "OK" }
        return "NOT RUN"
    }

    var firstWeatherError: DiagnosticError? {
        ["current", "hourly", "daily", "combined"].compactMap { requests[$0]?.error }.first
    }

    var conclusion: String {
        if location.status == "ERROR" { return "CoreLocation failed; WeatherKit was not called." }
        if location.status == "OK" && weatherStatus == "ERROR" { return "CLLocation OK; WeatherKit returned an error. See Domain + Code." }
        if weatherStatus == "OK" && geocoding.error != nil { return "WeatherKit OK; reverse geocoding failed separately." }
        if weatherStatus == "OK" { return "WeatherKit OK in this attempt." }
        if pipeline.error != nil { return "App pipeline failed. This is separate from a native WeatherKit error." }
        return "No conclusion yet. Check each stage and run the isolated test."
    }

    var text: String {
        let error = firstWeatherError
        var lines = [
            "SimpleWeather Diagnostics v1", "Mode: \(mode)",
            "Date: \(startedAt?.ISO8601Format() ?? "NOT STARTED")",
            "Bundle Identifier: \(Bundle.main.bundleIdentifier ?? "nil")",
            "OS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Location Authorization: \(authorization)",
            "CLLocation: \(location.text)", "Location: \(locationText)",
            "Geocoding: \(geocoding.text)", "WeatherKit: \(weatherStatus)",
            "WeatherKit Error Domain: \(error?.domain ?? "NONE")",
            "WeatherKit Error Code: \(error.map { String($0.code) } ?? "NONE")",
            "WeatherKit Error Description: \(error?.description ?? "NONE")",
            "Underlying Error: \(error?.underlying.isEmpty == false ? error!.underlying.map(\.text).joined(separator: "\n") : "NONE")",
            "Conclusion: \(conclusion)"
        ]
        if let error = location.error { lines.append("\nCoreLocation error:\n\(error.text)") }
        if let error = geocoding.error { lines.append("\nGeocoding error:\n\(error.text)") }
        for query in ["combined", "current", "hourly", "daily"] {
            if let stage = requests[query] {
                lines.append("\nWeatherKit .\(query): \(stage.text)")
                if let error = stage.error { lines.append(error.text) }
            }
        }
        lines.append("\nApp pipeline: \(pipeline.text)")
        if let error = pipeline.error { lines.append(error.text) }
        lines.append("\nEvents:\n" + events.joined(separator: "\n"))
        return lines.joined(separator: "\n")
    }
}
