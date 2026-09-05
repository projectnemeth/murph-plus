// MurphPlusWatch/Debug/WatchLayoutHarness.swift
#if DEBUG
import SwiftUI

/// Opens the live workout pages directly, with a session already running, so
/// their layout can be screenshotted from the command line.
///
/// This exists because the watch simulator cannot be driven: `simctl` can boot,
/// launch and screenshot, but it cannot tap — so reaching the live pages the
/// normal way (Start, wait, swipe) is impossible without a person at the
/// keyboard, and every layout question about those pages was being answered by
/// reading code instead of looking. The first two bugs it was built for — the
/// status band colliding with the system clock, and the phase chip sitting a
/// row too low — were both invisible to inspection and obvious in a screenshot.
///
/// HealthKit is stubbed rather than authorised: the real controller would put
/// a permission sheet over the very pixels being measured, and `StubWorkout`
/// costs nothing since `WorkoutControlling` is already the seam the tests use.
///
/// Usage:
/// ```
/// xcrun simctl launch <device> com.projectnemeth.MurphPlus.watchkitapp \
///   -MurphLayoutHarness page 2 phase rounds
/// xcrun simctl io <device> screenshot out.png
/// ```
enum WatchLayoutHarness {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-MurphLayoutHarness")
    }

    /// Which slot to open: 0 controls, 1 primary, 2 clock, 3 now playing.
    static var page: Int {
        value(after: "page").flatMap(Int.init) ?? 1
    }

    /// `run1`, `rounds`, or `paused` (which is `rounds`, paused).
    static var phase: String { value(after: "phase") ?? "rounds" }

    /// `live` (the paged workout screens) or `countdown`. The countdown is
    /// otherwise unreachable without a tap on Start.
    static var screen: String { value(after: "screen") ?? "live" }

    private static func value(after key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}

/// Fixed, plausible numbers — a mid-workout heart rate and a part-run distance.
/// Nothing here varies over time: a screenshot that changes between runs cannot
/// be compared against the last one.
@MainActor
private final class StubWorkout: WorkoutControlling {
    var currentHeartRate: Int? = 142
    var currentRunDistanceMeters: Double? = 1_207
    var onHeartRate: ((Int) -> Void)?

    func requestAuthorization() async {}
    func start(indoor: Bool) async {}
    func recover(indoor: Bool) async -> Bool { false }
    func beginRunActivity(resetDistanceBaseline: Bool) {}
    func beginRoundsActivity() {}
    func pause() {}
    func resume() {}
    func finish() async {}
}

struct WatchLayoutHarnessView: View {
    @State private var controller = WatchSessionController(
        workout: StubWorkout(),
        // A throwaway directory, so a harness run never touches — or resumes
        // from — a real journal left by ordinary use of the app.
        journalDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("layout-harness", isDirectory: true)
    )
    @State private var sync = WatchSyncCoordinator()
    @State private var ready = false

    var body: some View {
        Group {
            if WatchLayoutHarness.screen == "countdown" {
                WatchCountdownView(value: 3) {}
            } else if ready {
                // Inside a `NavigationStack` because the real app reaches this
                // view through one (`WatchSetupView`'s `navigationDestination`),
                // and `.toolbar` — where the phase chip lives — renders nothing
                // without one. A harness that drops the stack silently loses a
                // piece of the layout it exists to photograph.
                NavigationStack {
                    WatchLiveView(
                        controller: controller,
                        sync: sync,
                        onDone: {},
                        initialPage: WatchLayoutHarness.page
                    )
                }
            } else {
                Color.black
            }
        }
        .task {
            await controller.startSession(
                template: TemplateSpec(
                    id: UUID(), name: "Full Murph", runDistanceMiles: 1,
                    totalPullUps: 100, totalPushUps: 200, totalSquats: 300, rounds: 20
                ),
                vestOn: false, vestWeightLbs: nil, indoor: true
            )

            if WatchLayoutHarness.phase != "run1" {
                // Run 1 → rounds, then bank a few so the round counter shows
                // something other than 0 and Undo is enabled.
                controller.advance()
                for _ in 0..<7 { controller.advance() }
            }
            if WatchLayoutHarness.phase == "paused" {
                controller.pause()
            }
            ready = true
        }
    }
}
#endif
