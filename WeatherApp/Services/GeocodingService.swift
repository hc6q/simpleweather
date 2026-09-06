import CoreLocation
import Foundation

struct GeocodingResolution {
    let place: WeatherPlace
    let status: String
    let error: DiagnosticError?
}

@MainActor
final class GeocodingService {
    private let geocoder = CLGeocoder()
    private var continuation: CheckedContinuation<Result<CLPlacemark, Error>, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var requestID: UUID?
    private var resolvedPlace: WeatherPlace?

    func resolve(_ location: CLLocation, previous: WeatherPlace?, force: Bool = false) async -> GeocodingResolution {
        let coordinates = Coordinates(latitude: location.coordinate.latitude,
                                      longitude: location.coordinate.longitude)
        // Only reuse a name near the same coordinates; never label a new region with an old city.
        let reference = resolvedPlace ?? previous
        if !force, let reference, distance(from: reference, to: location) < 2_000,
           Date.now.timeIntervalSince(reference.locatedAt) < 60 * 60 {
            // Keep the original geocoding position/time so many small moves cannot extend it forever.
            resolvedPlace = reference
            return GeocodingResolution(place: WeatherPlace(coordinates: coordinates, name: reference.name,
                timeZoneIdentifier: reference.timeZoneIdentifier, locatedAt: location.timestamp),
                status: "CACHED — \(reference.name)", error: nil)
        }
        DiagnosticLog.event("Geocoding", "START")
        let result = await reverseGeocode(location)
        return resolution(result, location: location, previous: previous)
    }

    func resolution(_ result: Result<CLPlacemark, Error>, location: CLLocation,
                    previous: WeatherPlace?) -> GeocodingResolution {
        let coordinates = Coordinates(latitude: location.coordinate.latitude,
                                      longitude: location.coordinate.longitude)
        let placemark: CLPlacemark?
        let captured: DiagnosticError?
        switch result {
        case .success(let value): placemark = value; captured = nil
        case .failure(let error):
            placemark = nil
            captured = DiagnosticLog.failure("Geocoding", error)
        }
        let nearby = previous.flatMap { distance(from: $0, to: location) < 2_000 ? $0 : nil }
        let candidates = [placemark?.locality, placemark?.subAdministrativeArea, placemark?.administrativeArea]
        let name = candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? L10n.text("location.current")
        let place = WeatherPlace(coordinates: coordinates, name: name,
            timeZoneIdentifier: placemark?.timeZone?.identifier ?? nearby?.timeZoneIdentifier ?? TimeZone.current.identifier,
            locatedAt: location.timestamp)
        if placemark != nil {
            resolvedPlace = place
            DiagnosticLog.event("Geocoding", "OK — \(name)")
        }
        return GeocodingResolution(place: place, status: captured == nil ? "OK — \(name)" : "ERROR", error: captured)
    }

    private func reverseGeocode(_ location: CLLocation) async -> Result<CLPlacemark, Error> {
        let id = UUID()
        requestID = id
        return await withTaskCancellationHandler {
            if Task.isCancelled { return .failure(CancellationError()) }
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 8_000_000_000) }
                    catch { return }
                    self?.finish(.failure(NSError(domain: "SimpleWeather.Geocoding", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "App reverse-geocoding timeout after 8 seconds."])), id: id)
                }
                geocoder.reverseGeocodeLocation(location, preferredLocale: .current) { [weak self] marks, error in
                    let result: Result<CLPlacemark, Error>
                    if let error { result = .failure(error) }
                    else if let mark = marks?.first { result = .success(mark) }
                    else { result = .failure(NSError(domain: "SimpleWeather.Geocoding", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "CLGeocoder returned no placemark and no error."])) }
                    Task { @MainActor in self?.finish(result, id: id) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError()), id: id) }
        }
    }

    private func finish(_ result: Result<CLPlacemark, Error>, id: UUID) {
        guard requestID == id else { return }
        requestID = nil
        let pending = continuation
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        geocoder.cancelGeocode()
        pending?.resume(returning: result)
    }

    private func distance(from place: WeatherPlace, to location: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: place.coordinates.latitude, longitude: place.coordinates.longitude).distance(from: location)
    }
}
