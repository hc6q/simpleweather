import CoreLocation
import Foundation

@MainActor
final class GeocodingService {
    private let geocoder = CLGeocoder()
    private var continuation: CheckedContinuation<CLPlacemark?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var requestID: UUID?
    private var resolvedPlace: WeatherPlace?

    func resolve(_ location: CLLocation, previous: WeatherPlace?) async -> WeatherPlace {
        let coordinates = Coordinates(latitude: location.coordinate.latitude,
                                      longitude: location.coordinate.longitude)
        // Only reuse a name near the same coordinates; never label a new region with an old city.
        let reference = resolvedPlace ?? previous
        if let reference, distance(from: reference, to: location) < 2_000,
           Date.now.timeIntervalSince(reference.locatedAt) < 60 * 60 {
            // Keep the original geocoding position/time so many small moves cannot extend it forever.
            resolvedPlace = reference
            return WeatherPlace(coordinates: coordinates, name: reference.name,
                timeZoneIdentifier: reference.timeZoneIdentifier, locatedAt: location.timestamp)
        }
        let placemark = await reverseGeocode(location)
        let nearby = previous.flatMap { distance(from: $0, to: location) < 2_000 ? $0 : nil }
        let candidates = [placemark?.locality, placemark?.subAdministrativeArea, placemark?.administrativeArea]
        let name = candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? nearby?.name ?? L10n.text("location.current")
        let place = WeatherPlace(coordinates: coordinates, name: name,
            timeZoneIdentifier: placemark?.timeZone?.identifier ?? nearby?.timeZoneIdentifier ?? TimeZone.current.identifier,
            locatedAt: location.timestamp)
        if placemark != nil { resolvedPlace = place }
        return place
    }

    private func reverseGeocode(_ location: CLLocation) async -> CLPlacemark? {
        let id = UUID()
        requestID = id
        return await withTaskCancellationHandler {
            if Task.isCancelled { return nil }
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 8_000_000_000) }
                    catch { return }
                    self?.finish(nil, id: id)
                }
                geocoder.reverseGeocodeLocation(location, preferredLocale: .current) { [weak self] marks, _ in
                    Task { @MainActor in self?.finish(marks?.first, id: id) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(nil, id: id) }
        }
    }

    private func finish(_ placemark: CLPlacemark?, id: UUID) {
        guard requestID == id else { return }
        requestID = nil
        let pending = continuation
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        geocoder.cancelGeocode()
        pending?.resume(returning: placemark)
    }

    private func distance(from place: WeatherPlace, to location: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: place.coordinates.latitude, longitude: place.coordinates.longitude).distance(from: location)
    }
}
