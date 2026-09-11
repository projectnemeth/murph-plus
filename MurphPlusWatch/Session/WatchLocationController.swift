// MurphPlusWatch/Session/WatchLocationController.swift
import CoreLocation
import Foundation
import Observation

/// Wraps `CLLocationManager`.
///
/// Its only job is to keep the GPS receiver powered while a run is in
/// progress. It never computes distance: that still comes from HealthKit's
/// `distanceWalkingRunning`, which fuses GPS with the accelerometer and beats
/// either alone — notably under tree cover, where raw GPS would not.
///
/// Isolated to the main actor for the same reason `WorkoutSessionController`
/// is: `CLLocationManagerDelegate` callbacks arrive off the main actor, so the
/// delegate methods below are `nonisolated` and hop back to the main actor
/// before touching any stored property. All mutation stays single-threaded.
///
/// Like every sensor in this app, it is optional to the app functioning: a
/// denial yields a complete workout with an estimated distance, never a
/// blocked one.
@MainActor
@Observable
final class WatchLocationController: NSObject, LocationProviding {
    /// A fix this good or better counts as usable. Apple Watch typically
    /// reaches 5-10 m outdoors; 20 m is loose enough not to stall the start
    /// gate and tight enough to exclude a fix that is still settling.
    static let usableAccuracyMeters: CLLocationAccuracy = 20

    private let manager = CLLocationManager()
    private(set) var fixState: GPSFixState = .off
    private var isUpdating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        // No `pausesLocationUpdatesAutomatically` here: the property is
        // `API_UNAVAILABLE(watchos, tvos)` in CoreLocation's header — it does
        // not exist on this platform, so there is no automatic-pause behavior
        // to disable in the first place (unlike iOS, where leaving it at its
        // default would be poison for a workout that includes standing still
        // at a pull-up bar).
        // Requires `UIBackgroundModes: [location]` in the built Info.plist.
        // Without it this line is a fatal error that terminates the app, which
        // is why the plist key and this property ship in one commit.
        manager.allowsBackgroundLocationUpdates = true
    }

    func requestAuthorization() async {
        // When In Use is sufficient: `allowsBackgroundLocationUpdates`
        // extends its reach into the background, so Always would be a second
        // prompt for nothing.
        //
        // Not actually asynchronous — CoreLocation answers through
        // `locationManagerDidChangeAuthorization`, not a return value. The
        // signature matches `LocationProviding`, whose other conformer
        // (HealthKit's) genuinely does await.
        guard manager.authorizationStatus == .notDetermined else {
            reflectAuthorization(manager.authorizationStatus)
            return
        }
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        guard !isUpdating else { return }

        switch manager.authorizationStatus {
        case .denied, .restricted:
            // Nothing to wait for. The gate reads this and starts at once.
            fixState = .denied
            return
        default:
            break
        }

        isUpdating = true
        fixState = .acquiring
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
        fixState = .off
    }

    private func reflectAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .denied, .restricted:
            if isUpdating {
                isUpdating = false
                manager.stopUpdatingLocation()
            }
            fixState = .denied
        default:
            // Newly granted while the setup screen is warming: pick up where
            // `startUpdating` left off rather than waiting for another tap.
            if fixState == .denied { fixState = .off }
        }
    }
}

extension WatchLocationController: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        // A negative `horizontalAccuracy` means the fix is invalid, not
        // precise — the sign is the validity flag, so this check must come
        // before the threshold comparison.
        guard let latest = locations.last,
              latest.horizontalAccuracy >= 0,
              latest.horizontalAccuracy <= Self.usableAccuracyMeters
        else { return }

        Task { @MainActor in
            guard self.isUpdating else { return }
            self.fixState = .fixed
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.reflectAuthorization(status)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: Error
    ) {
        guard (error as? CLError)?.code == .denied else { return }
        Task { @MainActor in
            self.reflectAuthorization(.denied)
        }
    }
}
