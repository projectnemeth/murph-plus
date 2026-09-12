// MurphPlus/Session/PhoneLocationController.swift
import CoreLocation
import Foundation
import Observation

/// Wraps `CLLocationManager` for the phone.
///
/// The sibling of `WatchLocationController`, with one difference that matters:
/// the watch's manager only powers the receiver and reads distance from
/// HealthKit's fused `distanceWalkingRunning`. There is no
/// `HKLiveWorkoutBuilder` on iOS, and `distanceWalkingRunning` on an iPhone is
/// the pedometer stride estimate with no location in it - so this controller
/// derives distance itself, through `RunDistanceAccumulator`.
///
/// Isolated to the main actor because `CLLocationManagerDelegate` callbacks
/// arrive off it: the delegate methods are `nonisolated` and hop back before
/// touching any stored property. All mutation stays single-threaded.
///
/// Like every sensor in this app, it is optional to the app functioning: a
/// denial yields a complete workout with no distance, never a blocked one.
@MainActor
@Observable
final class PhoneLocationController: NSObject, LocationProviding, RunDistanceMeasuring {
    /// A fix this good or better counts as usable for the START GATE. The
    /// accumulator applies its own, separately tunable threshold to decide
    /// whether a delta is trustworthy.
    ///
    /// `nonisolated` because the delegate reads it off the main actor: an
    /// immutable Sendable value, so the isolation would buy nothing and cost a
    /// Swift 6 error.
    nonisolated static let usableAccuracyMeters: CLLocationAccuracy = 20

    private let manager = CLLocationManager()
    private(set) var fixState: GPSFixState = .off
    private(set) var runDistanceMeters: Double?

    private var accumulator = RunDistanceAccumulator()
    private var isUpdating = false
    private var isMeasuring = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        // Unlike watchOS, where this property does not exist, iOS really will
        // stop delivering updates when it decides the user has stopped moving.
        // Mid-Murph that is a silent undercount, and it is the likeliest way
        // this feature fails quietly on a phone after working on a watch.
        manager.pausesLocationUpdatesAutomatically = false
        // Requires `UIBackgroundModes: [location]` in the built Info.plist.
        // Without it this line is a fatal error that terminates the app, which
        // is why the plist key and this property ship in one commit.
        manager.allowsBackgroundLocationUpdates = true
    }

    // MARK: - LocationProviding

    func requestAuthorization() async {
        // When In Use is sufficient: `allowsBackgroundLocationUpdates` extends
        // its reach into the background, so Always would be a second prompt
        // for nothing.
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

    // MARK: - RunDistanceMeasuring

    func beginRun() {
        accumulator.reset()
        // nil, not 0: nothing has been measured yet, and a 0 that really means
        // "no usable sample has arrived" is a fabricated measurement. It
        // becomes a number in `ingest`, once the accumulator accepts a sample.
        runDistanceMeters = nil
        isMeasuring = true
    }

    func resumeRun() {
        // Anchor only. Keeping the total but dropping the anchor is what keeps
        // the walk taken during the pause out of the run.
        accumulator.resetAnchor()
        isMeasuring = true
    }

    func stopMeasuring() {
        isMeasuring = false
    }

    // MARK: - Private

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

    fileprivate func ingest(_ locations: [CLLocation], now: Date) {
        guard isUpdating else { return }

        for location in locations {
            let sample = LocationSample(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy,
                speed: location.speed,
                timestamp: location.timestamp
            )

            // The gate's threshold, applied independently of the
            // accumulator's: a negative accuracy means invalid, not precise,
            // so the sign test must come first.
            if sample.horizontalAccuracy >= 0,
               sample.horizontalAccuracy <= Self.usableAccuracyMeters {
                fixState = .fixed
            }

            if isMeasuring {
                let total = accumulator.add(sample, now: now)
                if accumulator.hasAcceptedSample { runDistanceMeters = total }
            }
        }
    }
}

extension PhoneLocationController: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        let now = Date()
        Task { @MainActor in self.ingest(locations, now: now) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.reflectAuthorization(status) }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: Error
    ) {
        guard (error as? CLError)?.code == .denied else { return }
        Task { @MainActor in self.reflectAuthorization(.denied) }
    }
}
