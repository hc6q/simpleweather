import CoreLocation
import Foundation

enum LocationFailure: Int, CustomNSError, LocalizedError {
    case permissionDenied = 1, unavailable, timedOut, alreadyRequesting
    static var errorDomain: String { "SimpleWeather.CoreLocation" }
    var errorCode: Int { rawValue }
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Location permission is denied or restricted."
        case .unavailable: return "CoreLocation returned no valid, recent CLLocation."
        case .timedOut: return "App CLLocation timeout after 15 seconds."
        case .alreadyRequesting: return "An app CLLocation request is already in progress."
        }
    }
    var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: errorDescription ?? ""] }
}

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var lastLocation: CLLocation?
    var authorizationDidChange: ((CLAuthorizationStatus) -> Void)?

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }
    var isAuthorized: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request(force: Bool = false) async throws -> CLLocation {
        guard authorization != .denied, authorization != .restricted else {
            throw LocationFailure.permissionDenied
        }
        if !force, isAuthorized, let location = lastLocation,
           abs(location.timestamp.timeIntervalSinceNow) < 5 * 60 { return location }
        guard continuation == nil else { throw LocationFailure.alreadyRequesting }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if self.authorization == .notDetermined {
                    self.manager.requestWhenInUseAuthorization()
                } else {
                    self.beginLocationRequest()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    private func beginLocationRequest() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) }
            catch { return }
            self?.finish(.failure(LocationFailure.timedOut))
        }
        // One-shot request: no persistent GPS subscription or background location mode.
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in self?.handleAuthorization(status) }
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        authorizationDidChange?(status)
        guard continuation != nil else { return }
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: beginLocationRequest()
        case .denied, .restricted: finish(.failure(LocationFailure.permissionDenied))
        case .notDetermined: break
        @unknown default: finish(.failure(LocationFailure.unavailable))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last(where: {
            $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 5 * 60 &&
            CLLocationCoordinate2DIsValid($0.coordinate)
        })
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let location else {
                self.finish(.failure(LocationFailure.unavailable))
                return
            }
            self.lastLocation = location
            self.finish(.success(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.finish(.failure(error))
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        manager.stopUpdatingLocation()
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}
