// MurphPlusTests/PhoneAcknowledgementTests.swift
import XCTest
import SwiftData
@testable import MurphPlus

/// What the phone tells the Watch it already holds — the half of the durable
/// channel that lets a journal ever be deleted, and lets a lost one be resent.
@MainActor
final class PhoneAcknowledgementTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: WorkoutTemplate.self, MurphSession.self, RunSplit.self, RoundLog.self,
            configurations: config
        )
        context = container.mainContext
    }

    @discardableResult
    private func session(
        origin: SessionOrigin, status: SessionStatus, daysAgo: Int = 0
    ) -> MurphSession {
        let session = MurphSession(template: WorkoutTemplate(name: "Full Murph"), vestOn: false)
        session.origin = origin
        session.status = status
        session.date = Date.now.addingTimeInterval(Double(-daysAgo) * 86400)
        context.insert(session)
        return session
    }

    func test_acknowledgesAFinishedWatchSession() {
        let done = session(origin: .watch, status: .completed)
        XCTAssertEqual(PhoneSyncCoordinator.acknowledgements(from: [done]).ids, [done.id])
    }

    func test_acknowledgesAnAbandonedWatchSession() {
        let quit = session(origin: .watch, status: .abandoned)
        XCTAssertEqual(PhoneSyncCoordinator.acknowledgements(from: [quit]).ids, [quit.id])
    }

    /// The one that matters most. A session the phone holds part-way through is
    /// one whose terminal checkpoint never landed — acknowledging it would
    /// invite the Watch to delete the only remaining copy of a workout the
    /// phone will show as in-progress forever.
    func test_neverAcknowledgesAnInProgressSession() {
        let live = session(origin: .watch, status: .inProgress)
        XCTAssertTrue(PhoneSyncCoordinator.acknowledgements(from: [live]).ids.isEmpty)
    }

    /// Phone-owned sessions have no journal on the Watch, so naming them would
    /// be noise in a context with a size ceiling.
    func test_ignoresPhoneOwnedSessions() {
        let phone = session(origin: .phone, status: .completed)
        XCTAssertTrue(PhoneSyncCoordinator.acknowledgements(from: [phone]).ids.isEmpty)
    }

    func test_capsTheListAtTheHundredMostRecent() {
        let sessions = (0..<130).map { session(origin: .watch, status: .completed, daysAgo: $0) }
        let acknowledged = PhoneSyncCoordinator.acknowledgements(from: sessions)

        XCTAssertEqual(acknowledged.ids.count, 100)
        XCTAssertEqual(
            Set(acknowledged.ids), Set(sessions.prefix(100).map(\.id)),
            "The most recent hundred, since older journals are the ones already long gone"
        )
    }

    /// Without the horizon the cap is a trap: a journal outside the window can
    /// never be named, so the Watch would resend it on every pass forever and
    /// retention would never reclaim it.
    func test_aCappedListReportsItsHorizon() {
        let sessions = (0..<130).map { session(origin: .watch, status: .completed, daysAgo: $0) }
        let acknowledged = PhoneSyncCoordinator.acknowledgements(from: sessions)
        XCTAssertEqual(acknowledged.horizon, sessions[99].date)
    }

    /// A list that named everything has nothing beyond it, and a horizon there
    /// would make the Watch discard journals the phone simply has not seen yet.
    func test_anUncappedListReportsNoHorizon() {
        let sessions = (0..<5).map { session(origin: .watch, status: .completed, daysAgo: $0) }
        XCTAssertNil(PhoneSyncCoordinator.acknowledgements(from: sessions).horizon)
    }

    func test_exactlyTheLimitIsNotCapped() {
        let limit = PhoneSyncCoordinator.acknowledgementLimit
        let sessions = (0..<limit).map { session(origin: .watch, status: .completed, daysAgo: $0) }
        let acknowledged = PhoneSyncCoordinator.acknowledgements(from: sessions)
        XCTAssertEqual(acknowledged.ids.count, limit)
        XCTAssertNil(acknowledged.horizon)
    }
}
