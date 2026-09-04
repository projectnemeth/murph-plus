// MurphPlusTests/PersonalBestCheckTests.swift
import XCTest
@testable import MurphPlus

final class PersonalBestCheckTests: XCTestCase {
    private let template = UUID()
    private let otherTemplate = UUID()

    private func bests(_ entries: (UUID, Bool, Double)...) -> [PersonalBest] {
        entries.map { PersonalBest(templateID: $0.0, vestOn: $0.1, seconds: $0.2) }
    }

    func test_aFasterTimeThanTheStoredBestIsAPersonalBest() {
        let isBest = PersonalBestCheck.isPersonalBest(
            elapsed: 3000, templateID: template, vestOn: false,
            among: bests((template, false, 3600))
        )

        XCTAssertTrue(isBest)
    }

    func test_aSlowerTimeIsNot() {
        let isBest = PersonalBestCheck.isPersonalBest(
            elapsed: 4000, templateID: template, vestOn: false,
            among: bests((template, false, 3600))
        )

        XCTAssertFalse(isBest)
    }

    /// Ties are not bests. Matching your own record is not beating it, and
    /// badging it would make the badge meaningless on a repeated time.
    func test_anIdenticalTimeIsNotAPersonalBest() {
        let isBest = PersonalBestCheck.isPersonalBest(
            elapsed: 3600, templateID: template, vestOn: false,
            among: bests((template, false, 3600))
        )

        XCTAssertFalse(isBest)
    }

    /// The first ever attempt at a template has nothing to beat. Badging it
    /// would put "Personal best" on every debut, which is noise.
    func test_theFirstAttemptAtATemplateIsNotBadged() {
        let isBest = PersonalBestCheck.isPersonalBest(
            elapsed: 3600, templateID: template, vestOn: false, among: []
        )

        XCTAssertFalse(isBest)
    }

    /// Vest and non-vest times are never mixed — a vested attempt is a harder
    /// workout, so beating an unvested record proves nothing about it.
    func test_aVestedAttemptIsNotComparedAgainstAnUnvestedBest() {
        let isBest = PersonalBestCheck.isPersonalBest(
            elapsed: 3000, templateID: template, vestOn: true,
            among: bests((template, false, 3600))
        )

        XCTAssertFalse(isBest, "No vested record exists yet, so there is nothing to beat")
    }

    func test_aVestedAttemptIsComparedAgainstTheVestedBest() {
        let isBest = PersonalBestCheck.isPersonalBest(
            elapsed: 3000, templateID: template, vestOn: true,
            among: bests((template, false, 2000), (template, true, 3600))
        )

        XCTAssertTrue(isBest, "Beats the vested record; the unvested one is irrelevant")
    }

    func test_anotherTemplatesBestIsIgnored() {
        let isBest = PersonalBestCheck.isPersonalBest(
            elapsed: 3000, templateID: template, vestOn: false,
            among: bests((otherTemplate, false, 1000))
        )

        XCTAssertFalse(isBest, "No record for this template, so nothing to beat")
    }

    func test_aSessionWithNoTemplateIsNeverABest() {
        let isBest = PersonalBestCheck.isPersonalBest(
            elapsed: 1, templateID: nil, vestOn: false,
            among: bests((template, false, 3600))
        )

        XCTAssertFalse(isBest)
    }
}
