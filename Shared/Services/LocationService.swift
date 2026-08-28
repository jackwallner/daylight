import CoreLocation
import Foundation
import os

/// A single coarse location fix, used only to work out when the sun sets.
///
/// Deliberately minimal. The app asks for `whenInUse` at reduced accuracy,
/// takes one fix, caches the coordinates in the App Group for the widgets, and
/// stops. There is no tracking, no background updates, no significant-change
/// monitoring, and nothing leaves the device: the sun's position is computed
/// locally in `SolarCalculator`, so there is no server to send a location to.
@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    enum Status: Equatable {
        case unknown
        case denied
        case located(latitude: Double, longitude: Double)
        /// Asked, but nothing came back yet.
        case waiting
    }

    @Published private(set) var status: Status = .unknown

    private let manager = CLLocationManager()
    private let logger = Logger(subsystem: "com.jackwallner.daylight", category: "Location")

    private override init() {
        super.init()
        manager.delegate = self
        // Whole-degree accuracy would be enough; this is the coarsest setting
        // CoreLocation offers and is still far better than the sun needs.
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        restoreCached()
    }

    /// The coordinates to compute the sun from, always non-nil so the UI has
    /// something to draw. Check `isUsingFallback` before making a claim about
    /// the user's actual sunset.
    var coordinates: (latitude: Double, longitude: Double) {
        let cached = CachedLocation.current
        return (cached.latitude, cached.longitude)
    }

    var isUsingFallback: Bool { !CachedLocation.current.isReal }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestAccess() {
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .waiting
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = .denied
        default:
            refresh()
        }
    }

    /// Take one fix if we are allowed to. Cheap to call on every appearance.
    func refresh() {
        guard [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) else {
            return
        }
        if case .unknown = status { status = .waiting }
        manager.requestLocation()
    }

    private func restoreCached() {
        let cached = CachedLocation.current
        if cached.isReal {
            status = .located(latitude: cached.latitude, longitude: cached.longitude)
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        Task { @MainActor in
            CachedLocation.store(latitude: latitude, longitude: longitude)
            self.status = .located(latitude: latitude, longitude: longitude)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.logger.error("Location failed: \(String(describing: error), privacy: .public)")
            // Keep any cached fix rather than dropping back to the fallback:
            // yesterday's coordinates give a far better sunset than none.
            if !CachedLocation.current.isReal {
                self.status = .unknown
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorization = manager.authorizationStatus
        Task { @MainActor in
            switch authorization {
            case .authorizedAlways, .authorizedWhenInUse:
                self.refresh()
            case .denied, .restricted:
                self.status = .denied
            default:
                break
            }
        }
    }
}
