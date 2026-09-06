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
            self.preferences.widgetRefreshAllowed = status == .authorizedAlways || status == .authorizedWhenInUse
            if status == .denied || status == .restricted {
                self.state = .permissionDenied
                self.message = L10n.text("location.permission.message")
                self.reloadWidgets()
            }
        }
    }

    var isRefreshing: Bool { state == .loading }

    func activate() async {
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
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        lastAttempt = .now
        state = .loading
        message = nil
        do {
            let coordinate = try await location.request(force: forceLocation)
            let place = await geocoding.resolve(coordinate, previous: preferences.lastLocation)
            try Task.checkCancellation()
            preferences.lastLocation = place
            preferences.widgetRefreshAllowed = location.isAuthorized
            if !forceWeather, !forceLocation, let snapshot, !snapshot.isStale(),
               CLLocation(latitude: snapshot.place.coordinates.latitude, longitude: snapshot.place.coordinates.longitude)
                .distance(from: coordinate) < 2_000 {
                state = .loaded
                return
            }
            let fresh = try await client.fetch(for: place)
            try Task.checkCancellation()
            // Permission can be revoked while an earlier request is still in flight.
            guard location.isAuthorized else { throw LocationFailure.permissionDenied }
            snapshot = fresh
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
            state = snapshot == nil ? .idle : .stale
        } catch LocationFailure.permissionDenied {
            preferences.widgetRefreshAllowed = false
            state = .permissionDenied
            message = L10n.text("location.permission.message")
            reloadWidgets()
        } catch {
            state = snapshot == nil ? .error : .stale
            message = L10n.text("weather.error.message")
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
