// MurphPlusWatch/Session/WorkoutSessionController.swift
import Foundation
import HealthKit
import Observation

/// Wraps `HKWorkoutSession` and `HKLiveWorkoutBuilder`.
///
/// One workout session typed `.crossTraining` spans the whole Murph, so it
/// appears in Fitness as a single workout rather than three. Inside it,
/// activity segmentation marks the runs `.running` and the rounds
/// `.functionalStrengthTraining`.
///
/// That segmentation is load-bearing for calorie accuracy: with
/// `.functionalStrengthTraining`, active energy is estimated primarily from
/// heart-rate elevation, which is the correct model for calisthenics — a
/// motion-driven estimate would badly under-count pull-ups, since the user
/// burns energy while going nowhere.
///
/// Every capability here is optional to the app functioning. If authorization
/// is denied, the session still runs to completion with no heart rate and no
/// distance; nothing in this type may block the workout.
///
/// Isolated to the main actor: `HKLiveWorkoutBuilderDelegate` callbacks arrive
/// on a HealthKit-managed background queue, but every stored property here is
/// also touched from caller-invoked methods on the main actor. The delegate
/// methods below are `nonisolated` and hop back to the main actor before
/// touching any stored property, so all mutation is single-threaded.
@MainActor
@Observable
final class WorkoutSessionController: NSObject, WorkoutControlling {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private(set) var currentHeartRate: Int?
    private(set) var currentRunDistanceMeters: Double?
    private(set) var isAuthorized = false

    /// Fires at most once per 5 seconds; the caller journals each one.
    var onHeartRate: ((Int) -> Void)?
    private var lastHeartRateEmit: Date?
    private static let heartRateThrottle: TimeInterval = 5

    /// Distance accumulated before the current run began, so a run's distance
    /// is its own and not the workout's total.
    private var distanceAtRunStart: Double = 0
    private var isInRunActivity = false

    private let heartRateType = HKQuantityType(.heartRate)
    private let distanceType = HKQuantityType(.distanceWalkingRunning)

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKQuantityType.workoutType()]
        let read: Set<HKObjectType> = [heartRateType, distanceType]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            isAuthorized = true
        } catch {
            // A denial is a normal outcome, not a failure state. The session
            // proceeds without heart rate or distance.
            isAuthorized = false
        }
    }

    func start(indoor: Bool) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .crossTraining
        configuration.locationType = indoor ? .indoor : .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore, workoutConfiguration: configuration
            )
            builder.delegate = self

            self.session = session
            self.builder = builder

            session.startActivity(with: .now)
            try await builder.beginCollection(at: .now)
        } catch {
            // Leave `session`/`builder` nil: every later call is a no-op and the
            // workout continues without HealthKit.
            self.session = nil
            self.builder = nil
        }
    }

    /// Reattaches to an `HKWorkoutSession` watchOS kept alive across an app
    /// relaunch (the process was killed mid-workout, but the session — a
    /// system-owned resource — was not). Only the session itself survives:
    /// the builder's delegate and data source are this process's objects and
    /// must be rebuilt from scratch, same as a fresh `start(indoor:)`.
    ///
    /// Returns `false` if there was nothing to recover, or recovery threw —
    /// either way the caller should fall back to `start(indoor:)` for the
    /// remainder of the workout. A second `HKWorkout` in Fitness is a much
    /// smaller loss than an hour of unrecorded heart rate.
    func recover(indoor: Bool) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            guard let session = try await healthStore.recoverActiveWorkoutSession() else {
                return false
            }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .crossTraining
            configuration.locationType = indoor ? .indoor : .outdoor

            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore, workoutConfiguration: configuration
            )
            builder.delegate = self

            self.session = session
            self.builder = builder
            return true
        } catch {
            return false
        }
    }

    /// See `WorkoutControlling.beginRunActivity(resetDistanceBaseline:)`.
    ///
    /// The baseline is what makes a run's distance its own rather than the
    /// workout's total. It must be re-snapshotted when a run *begins*, and must
    /// not be when a run already in progress is merely re-segmented after a
    /// relaunch: on that path the recovered builder already reports the miles
    /// covered before the crash, and snapshotting would subtract them away.
    func beginRunActivity(resetDistanceBaseline: Bool) {
        if resetDistanceBaseline {
            distanceAtRunStart = currentTotalDistance()
        }
        isInRunActivity = true
        currentRunDistanceMeters = max(0, currentTotalDistance() - distanceAtRunStart)
        beginActivity(.running)
    }

    func beginRoundsActivity() {
        isInRunActivity = false
        currentRunDistanceMeters = nil
        beginActivity(.functionalStrengthTraining)
    }

    private func beginActivity(_ type: HKWorkoutActivityType) {
        // Activity segmentation is a method on the session, not the builder —
        // the builder only records what the session's activities produce.
        guard let session else { return }
        session.endCurrentActivity(on: .now)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = type
        session.beginNewActivity(configuration: configuration, date: .now, metadata: nil)
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    func finish() async {
        guard let session, let builder else { return }
        session.end()
        try? await builder.endCollection(at: .now)
        _ = try? await builder.finishWorkout()

        // Only clear the fields if they still hold the session this call
        // captured. `finishWorkout()` on an hour-long workout is slow, and
        // callers fire `finish()` as a detached `Task`; a user who taps Done
        // and starts a new Murph can install a fresh session and builder while
        // this call is still suspended. Nil-ing unconditionally would strand
        // that new `HKWorkoutSession` behind every `guard let session` here —
        // no segmentation, no distance, and never ended, so it stays live and
        // blocks all future workouts until the watch reboots. Identity, not a
        // separate in-flight flag, because it is exactly the right question:
        // is what I finished still what we are using?
        if self.session === session {
            self.session = nil
            self.builder = nil
        }
    }

    private func currentTotalDistance() -> Double {
        builder?.statistics(for: distanceType)?
            .sumQuantity()?
            .doubleValue(for: .meter()) ?? 0
    }
}

extension WorkoutSessionController: HKLiveWorkoutBuilderDelegate {
    // The protocol makes no main-actor promise, so these cannot inherit the
    // class's isolation. Each one reads only from the `workoutBuilder`
    // parameter (a HealthKit-managed, not our-stored, object) before hopping
    // to the main actor to touch any property of `self`.
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            if quantityType == heartRateType {
                guard let bpm = workoutBuilder.statistics(for: quantityType)?
                    .mostRecentQuantity()?
                    .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                else { continue }

                let rounded = Int(bpm.rounded())
                Task { @MainActor in
                    self.currentHeartRate = rounded

                    // Live display updates every sample; the journal gets one
                    // every 5 seconds, which is ~700 events across a long Murph.
                    let now = Date.now
                    if self.lastHeartRateEmit.map({ now.timeIntervalSince($0) >= Self.heartRateThrottle }) ?? true {
                        self.lastHeartRateEmit = now
                        self.onHeartRate?(rounded)
                    }
                }
            }

            if quantityType == distanceType {
                Task { @MainActor in
                    guard self.isInRunActivity else { return }
                    // Distance accumulated during the rounds is discarded
                    // rather than added to a run — pacing between pull-up
                    // sets must not inflate the mile.
                    self.currentRunDistanceMeters = max(0, self.currentTotalDistance() - self.distanceAtRunStart)
                }
            }
        }
    }
}
