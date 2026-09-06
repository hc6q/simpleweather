import Foundation
import CoreLocation
import WidgetKit

struct WeatherEntry: TimelineEntry {
    let date: Date
    let snapshot: WeatherSnapshot?
    let unit: TemperatureUnit
}

struct WeatherTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: .now, snapshot: nil, unit: .celsius)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        Task {
            let cached = await newestCachedSnapshot()
            completion(WeatherEntry(date: .now, snapshot: cached, unit: SharedPreferences().unit))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        Task {
            let preferences = SharedPreferences()
            var snapshot = await newestCachedSnapshot()
            let now = Date.now
            // No GPS in the extension. Only recently authorized app coordinates may be reused.
            if preferences.widgetRefreshAllowed,
               let place = preferences.lastLocation,
               now.timeIntervalSince(place.locatedAt) >= -60,
               now.timeIntervalSince(place.locatedAt) < 12 * 60 * 60,
               snapshot == nil || snapshot?.isStale(at: now) == true,
               let fresh = try? await WeatherClient().fetch(for: place),
               SharedPreferences().widgetRefreshAllowed {
                snapshot = fresh
                await WeatherCache.widget.save(fresh)
            }
            let date = Date.now
            let entry = WeatherEntry(date: date, snapshot: snapshot, unit: preferences.unit)
            var entries = [entry]
            if let snapshot, !snapshot.isStale(at: date) {
                let staleAt = min(snapshot.updatedAt.addingTimeInterval(30 * 60),
                                  snapshot.current.date.addingTimeInterval(60 * 60))
                entries.append(WeatherEntry(date: staleAt, snapshot: snapshot, unit: preferences.unit))
            }
            completion(Timeline(entries: entries, policy: .after(date.addingTimeInterval(30 * 60))))
        }
    }

    private func newestCachedSnapshot() async -> WeatherSnapshot? {
        let app = await WeatherCache.shared.load()
        guard let place = SharedPreferences().lastLocation,
              let widget = await WeatherCache.widget.load() else { return app }
        let reference = CLLocation(latitude: place.coordinates.latitude, longitude: place.coordinates.longitude)
        let cachedLocation = CLLocation(latitude: widget.place.coordinates.latitude,
                                        longitude: widget.place.coordinates.longitude)
        guard reference.distance(from: cachedLocation) < 2_000 else { return app }
        if let app, app.updatedAt >= widget.updatedAt { return app }
        return widget
    }
}
