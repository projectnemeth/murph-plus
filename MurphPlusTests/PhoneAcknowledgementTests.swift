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
        XCTAssertEqual(PhoneSyncCoordinator.acknowledgements(from: [done]), [done.id])
    }

    func test_acknowledgesAnAbandonedWatchSession() {
        let quit = session(origin: .watch, status: .abandoned)
        XCTAssertEqual(PhoneSyncCoordinator.acknowledgements(from: [quit]), [quit.id])
    }

    /// The one that matters most. A session the phone holds part-way through is
    /// one whose terminal checkpoint never landed — acknowledging it would
    /// invite the Watch to delete the only remaining copy of a workout the
    /// phone will show as in-progress forever.
    func test_neverAcknowledgesAnInProgressSession() {
        let live = session(origin: .watch, status: .inProgress)
        XCTAssertTrue(PhoneSyncCoordinator.acknowledgements(from: [live]).isEmpty)
    }

    /// Phone-owned sessions have no journal on the Watch, so naming them would
    /// be noise in a context with a size ceiling.
    func test_ignoresPhoneOwnedSessions() {
        let phone = session(origin: .phone, status: .completed)
        XCTAssertTrue(PhoneSyncCoordinator.acknowledgements(from: [phone]).isEmpty)
    }

    func test_capsTheListAtTheHundredMostRecent() {
        let sessions = (0..<130).map { session(origin: .watch, status: .completed, daysAgo: $0) }
        let acknowledged = PhoneSyncCoordinator.acknowledgements(from: sessions)

        XCTAssertEqual(acknowledged.count, 100)
        XCTAssertEqual(
            Set(acknowledged), Set(sessions.prefix(100).map(\.id)),
            "The most recent hundred, since older journals are the ones already long gone"
        )
    }
}
