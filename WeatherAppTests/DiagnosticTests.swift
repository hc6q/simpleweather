import CoreLocation
import Foundation
import XCTest
@testable import WeatherApp

private actor ProbeRecorder {
    var calls: [String] = []
    var events: [WeatherRequestEvent] = []
    func called(_ query: String) { calls.append(query) }
    func received(_ event: WeatherRequestEvent) { events.append(event) }
}

@MainActor
final class DiagnosticTests: XCTestCase {
    func testNSErrorDetailsAndUnderlyingChainArePreserved() {
        let leaf = NSError(domain: NSURLErrorDomain, code: -1009,
                           userInfo: [NSLocalizedDescriptionKey: "Offline", "reason": "network unavailable"])
        let middle = NSError(domain: "TestDaemon", code: 2, userInfo: [NSUnderlyingErrorKey: leaf])
        let original = NSError(domain: "TestWeatherKit", code: 401,
                               userInfo: [NSLocalizedDescriptionKey: "Request rejected", NSUnderlyingErrorKey: middle])
        let result = DiagnosticError(original)
        XCTAssertEqual(result.domain, "TestWeatherKit")
        XCTAssertEqual(result.code, 401)
        XCTAssertEqual(result.description, original.localizedDescription)
        XCTAssertEqual(result.underlying.first?.domain, "TestDaemon")
        XCTAssertEqual(result.underlying.first?.underlying.first?.code, -1009)
        XCTAssertTrue(result.text.contains("network unavailable"))
    }

    func testCredentialsAreRedactedAtTopLevelAndInNestedUserInfo() {
        let error = NSError(domain: "TestDomain", code: 8, userInfo: [
            NSLocalizedDescriptionKey: "Failed https://user:pass@example.com/?token=hidden-query",
            "password": "top-secret-value",
            "headers": ["Authorization": "Bearer nested-secret-value", "Cookie": "session=hidden-cookie"],
            "url": "https://example.com/?api_key=hidden-key",
            "other": "Bearer hidden-bearer",
            "jwt": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijk",
            "reason": "WeatherDaemon rejected the request"
        ])
        let text = DiagnosticError(error).text
        for secret in ["top-secret-value", "nested-secret-value", "hidden-cookie", "hidden-query", "hidden-key", "hidden-bearer", "user:pass", "eyJhbGci"] {
            XCTAssertFalse(text.contains(secret), "Secret survived redaction: \(secret)")
        }
        XCTAssertTrue(text.contains("WeatherDaemon rejected the request"))
        XCTAssertTrue(text.contains("[REDACTED"))
    }

    func testLongUnderlyingChainHasABoundedTraversal() {
        var error = NSError(domain: "Leaf", code: 0)
        for index in 1...30 { error = NSError(domain: "Nested", code: index, userInfo: [NSUnderlyingErrorKey: error]) }
        XCTAssertTrue(DiagnosticError(error).text.contains("depth limit (16)"))
    }

    func testProbeRequestsCurrentHourlyDailyInOrder() async {
        let recorder = ProbeRecorder()
        await WeatherKitProbe.runQueries(operation: { await recorder.called($0) }, sink: { await recorder.received($0) })
        let calls = await recorder.calls
        let events = await recorder.events
        XCTAssertEqual(calls, ["current", "hourly", "daily"])
        XCTAssertEqual(events.map(\.status), ["RUNNING", "OK", "RUNNING", "OK", "RUNNING", "OK"])
    }

    func testCurrentFailureSkipsHourlyAndDailyAndPreservesNativeError() async {
        let recorder = ProbeRecorder()
        let error = NSError(domain: "TestNativeWeatherError", code: 77,
                            userInfo: [NSLocalizedDescriptionKey: "Actual test error"])
        await WeatherKitProbe.runQueries(operation: { query in
            await recorder.called(query)
            throw error
        }, sink: { await recorder.received($0) })
        let calls = await recorder.calls
        let events = await recorder.events
        XCTAssertEqual(calls, ["current"])
        XCTAssertEqual(events.first(where: { $0.status == "ERROR" })?.error?.domain, error.domain)
        XCTAssertEqual(events.first(where: { $0.status == "ERROR" })?.error?.code, 77)
        XCTAssertEqual(events.filter { $0.status.hasPrefix("NOT RUN") }.map(\.query), ["hourly", "daily"])
    }

    func testHourlyFailureStillTestsDaily() async {
        let recorder = ProbeRecorder()
        await WeatherKitProbe.runQueries(operation: { query in
            await recorder.called(query)
            if query == "hourly" { throw NSError(domain: "HourlyError", code: 503) }
        }, sink: { await recorder.received($0) })
        let calls = await recorder.calls
        let events = await recorder.events
        XCTAssertEqual(calls, ["current", "hourly", "daily"])
        XCTAssertEqual(events.last?.query, "daily")
        XCTAssertEqual(events.last?.status, "OK")
        XCTAssertEqual(events.first(where: { $0.status == "ERROR" })?.query, "hourly")
    }

    func testLocationErrorDoesNotBecomeAWeatherKitError() {
        let report = WeatherDiagnosticReport()
        report.begin(mode: "Test", authorization: .authorizedWhenInUse)
        report.location = DiagnosticStage(status: "ERROR", error: DiagnosticError(NSError(domain: kCLErrorDomain, code: 0)))
        XCTAssertEqual(report.weatherStatus, "NOT RUN")
        XCTAssertNil(report.firstWeatherError)
        XCTAssertTrue(report.conclusion.contains("CoreLocation failed"))
        XCTAssertTrue(report.text.contains("WeatherKit Error Domain: NONE"))
    }

    func testGeocodingFailureKeepsValidCoordinatesAndGenericPlace() {
        let service = GeocodingService()
        let location = CLLocation(latitude: -30.33, longitude: -54.32)
        let previous = WeatherPlace(coordinates: Coordinates(latitude: -30.33, longitude: -54.32),
                                    name: "Old city", timeZoneIdentifier: "America/Sao_Paulo", locatedAt: .now)
        let error = NSError(domain: kCLErrorDomain, code: 8, userInfo: [NSLocalizedDescriptionKey: "No geocoding result"])
        let result = service.resolution(.failure(error), location: location, previous: previous)
        XCTAssertEqual(result.error?.domain, kCLErrorDomain)
        XCTAssertEqual(result.error?.code, 8)
        XCTAssertEqual(result.place.name, L10n.text("location.current"))
        XCTAssertEqual(result.place.coordinates, previous.coordinates)
        let report = WeatherDiagnosticReport()
        report.received(location)
        report.received(result)
        report.receive(WeatherRequestEvent(query: "current", status: "OK"))
        XCTAssertEqual(report.weatherStatus, "OK")
        XCTAssertTrue(report.conclusion.contains("reverse geocoding failed separately"))
    }

    func testReportIncludesRealWeatherErrorAndUnderlyingFields() {
        let report = WeatherDiagnosticReport()
        report.begin(mode: "Test", authorization: .authorizedWhenInUse)
        report.received(CLLocation(latitude: 10, longitude: 20))
        report.receive(WeatherRequestEvent(query: "current", status: "ERROR", error: DiagnosticError(
            NSError(domain: "NativeDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Exact description"]))))
        XCTAssertTrue(report.text.contains("WeatherKit Error Domain: NativeDomain"))
        XCTAssertTrue(report.text.contains("WeatherKit Error Code: 42"))
        XCTAssertTrue(report.text.contains("WeatherKit Error Description: Exact description"))
        XCTAssertTrue(report.text.contains("Underlying Error: NONE"))
        XCTAssertTrue(report.text.contains("Location: 10.0, 20.0"))
        XCTAssertTrue(report.conclusion.contains("CLLocation OK; WeatherKit returned an error"))
    }
}
