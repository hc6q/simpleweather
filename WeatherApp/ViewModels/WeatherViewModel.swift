import CoreLocation
import Foundation
import Observation
import WidgetKit

enum WeatherScreenState: Equatable {
    case idle, loading, loaded, stale, permissionDenied, error
}

@MainActor @Observable
final class WeatherViewModel {
    private(set) var state: WeatherScreenState = .idle
    private(set) var snapshot: WeatherSnapshot?
    private(set) var unit: TemperatureUnit
    private(set) var attribution: WeatherAttributionRecord?
    private(set) var message: String?
    let automaticDiagnostics = WeatherDiagnosticReport()
    let isolatedDiagnostics = WeatherDiagnosticReport()
    private(set) var isDiagnosing = false

    var diagnosticReport: WeatherDiagnosticReport {
        isolatedDiagnostics.startedAt == nil ? automaticDiagnostics : isolatedDiagnostics
    }

    @ObservationIgnored private let location = LocationService()
    @ObservationIgnored private let geocoding = GeocodingService()
    @ObservationIgnored private let client = WeatherClient()
    @ObservationIgnored private let cache: WeatherCache
    @ObservationIgnored private let preferences: SharedPreferences
    @ObservationIgnored private var didLoadCache = false
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var refreshInFlight = false

    init(cache: WeatherCache = .shared, preferences: SharedPreferences = SharedPreferences()) {
        self.cache = cache
        self.preferences = preferences
        unit = preferences.unit
        attribution = preferences.attribution
        location.authorizationDidChange = { [weak self] status in
            guard let self else { return }
            self.automaticDiagnostics.updateAuthorization(status)
            if self.isDiagnosing { self.isolatedDiagnostics.updateAuthorization(status) }
            self.preferences.widgetRefreshAllowed = status == .authorizedAlways || status == .authorizedWhenInUse
            if status == .denied || status == .restricted {
                self.state = .permissionDenied
                self.message = L10n.text("location.permission.message")
                self.reloadWidgets()
            }
        }
    }

    var isRefreshing: Bool { state == .loading || isDiagnosing }

    func activate() async {
        guard !isDiagnosing else { return }
        automaticDiagnostics.updateAuthorization(location.authorization)
        if !didLoadCache {
            didLoadCache = true
            snapshot = await cache.load()
            if let snapshot { state = snapshot.isStale() ? .stale : .loaded }
        }
        unit = preferences.unit
        preferences.widgetRefreshAllowed = location.isAuthorized
        if location.authorization == .denied || location.authorization == .restricted {
            state = .permissionDenied
            message = L10n.text("location.permission.message")
            return
        }
        // Avoid duplicate refreshes when the permission dialog changes scenePhase.
        guard state != .loading else { return }
        if let lastAttempt, Date.now.timeIntervalSince(lastAttempt) < 30,
           state != .permissionDenied { return }
        // Reacquire a one-shot location after five minutes, even when the forecast is recent.
        let locationOld = preferences.lastLocation.map { Date.now.timeIntervalSince($0.locatedAt) >= 5 * 60 } ?? true
        if snapshot == nil || snapshot?.isStale() == true || locationOld {
            await refresh(forceWeather: false)
        }
    }

    func refresh(forceLocation: Bool = false, forceWeather: Bool = true) async {
        guard !refreshInFlight, !isDiagnosing else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        lastAttempt = .now
        state = .loading
        message = nil
        let report = automaticDiagnostics
        report.begin(mode: "Automatic refresh (.current + .hourly + .daily)", authorization: location.authorization)
        do {
            let coordinate = try await diagnosedLocation(force: forceLocation, report: report)
            report.geocoding = DiagnosticStage(status: "RUNNING")
            report.event("Geocoding: START")
            let geocoded = await geocoding.resolve(coordinate, previous: preferences.lastLocation)
            report.received(geocoded)
            let place = geocoded.place
            try Task.checkCancellation()
            preferences.lastLocation = place
            preferences.widgetRefreshAllowed = location.isAuthorized
            if !forceWeather, !forceLocation, let snapshot, !snapshot.isStale(),
               CLLocation(latitude: snapshot.place.coordinates.latitude, longitude: snapshot.place.coordinates.longitude)
                .distance(from: coordinate) < 2_000 {
                state = .loaded
                report.pipeline = DiagnosticStage(status: "CACHED", detail: "Fresh forecast reused; no WeatherKit request.")
                return
            }
            let fresh = try await client.fetch(for: place, trace: { event in
                await report.receive(event)
            })
            try Task.checkCancellation()
            // Permission can be revoked while an earlier request is still in flight.
            guard location.isAuthorized else { throw LocationFailure.permissionDenied }
            snapshot = fresh
            report.pipeline = DiagnosticStage(status: "OK", detail: "Forecast displayed")
            state = fresh.isStale() ? .stale : .loaded
            if !(await cache.save(fresh)) {
                message = L10n.text("cache.unavailable")
            }
            reloadWidgets()
            if attribution == nil {
                attribution = await client.attribution()
                preferences.attribution = attribution
            }
        } catch is CancellationError {
            report.pipeline = DiagnosticStage(status: "CANCELLED")
            state = snapshot == nil ? .idle : .stale
        } catch LocationFailure.permissionDenied {
            report.pipeline = DiagnosticStage(status: "ERROR", detail: "CoreLocation permission denied")
            preferences.widgetRefreshAllowed = false
            state = .permissionDenied
            message = L10n.text("location.permission.message")
            reloadWidgets()
        } catch {
            report.pipeline = DiagnosticStage(status: "ERROR", error: DiagnosticLog.failure("App refresh pipeline", error))
            report.event("App refresh pipeline: ERROR (see separate stage errors)")
            state = snapshot == nil ? .error : .stale
            message = L10n.text("weather.error.message")
        }
    }

    private func diagnosedLocation(force: Bool, report: WeatherDiagnosticReport) async throws -> CLLocation {
        report.updateAuthorization(location.authorization)
        report.location = DiagnosticStage(status: "RUNNING")
        report.event("CLLocation: START")
        do {
            let coordinate = try await location.request(force: force)
            report.updateAuthorization(location.authorization)
            report.received(coordinate)
            return coordinate
        } catch {
            report.updateAuthorization(location.authorization)
            report.location = DiagnosticStage(status: error is CancellationError ? "CANCELLED" : "ERROR",
                error: DiagnosticLog.failure("CoreLocation", error))
            report.event("CoreLocation: \(report.location.status); WeatherKit NOT RUN")
            throw error
        }
    }

    func runDiagnostics() async {
        guard !refreshInFlight, !isDiagnosing else { return }
        isDiagnosing = true
        lastAttempt = .now
        let report = isolatedDiagnostics
        report.begin(mode: "Isolated WeatherKit probes: .current, then .hourly, then .daily",
                     authorization: location.authorization)
        defer {
            isDiagnosing = false
            lastAttempt = .now
            report.event("Diagnostic run finished")
        }
        do {
            let coordinate = try await diagnosedLocation(force: true, report: report)
            report.geocoding = DiagnosticStage(status: "RUNNING")
            report.event("Geocoding: START (fresh reverse geocoding)")
            let geocoded = await geocoding.resolve(coordinate, previous: preferences.lastLocation, force: true)
            report.received(geocoded)
            try Task.checkCancellation()
            // A geocoding failure never prevents probing WeatherKit with the valid CLLocation.
            await WeatherKitProbe.run(location: coordinate) { event in
                await report.receive(event)
            }
            report.pipeline = DiagnosticStage(status: Task.isCancelled ? "CANCELLED" : "COMPLETED",
                                              detail: "See the individual WeatherKit results")
        } catch {
            report.pipeline = DiagnosticStage(status: error is CancellationError ? "CANCELLED" : "ERROR",
                                               error: DiagnosticError(error))
        }
    }

    func setUnit(_ selected: TemperatureUnit) {
        guard unit != selected else { return }
        unit = selected
        preferences.unit = selected
        reloadWidgets()
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: SharedConfiguration.smallWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedConfiguration.mediumWidgetKind)
    }
}
