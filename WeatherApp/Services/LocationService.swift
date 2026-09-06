import CoreLocation
import Foundation

enum LocationFailure: Error { case permissionDenied, unavailable, timedOut, alreadyRequesting }

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

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationDidChange?(manager.authorizationStatus)
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: beginLocationRequest()
        case .denied, .restricted: finish(.failure(LocationFailure.permissionDenied))
        case .notDetermined: break
        @unknown default: finish(.failure(LocationFailure.unavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last(where: {
            $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 5 * 60 &&
            CLLocationCoordinate2DIsValid($0.coordinate)
        }) else {
            finish(.failure(LocationFailure.unavailable))
            return
        }
        lastLocation = location
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        finish(.failure(denied ? LocationFailure.permissionDenied : LocationFailure.unavailable))
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
