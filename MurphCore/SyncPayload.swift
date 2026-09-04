// MurphCore/SyncPayload.swift
import Foundation

enum SessionOrigin: String, Codable {
    case phone
    case watch
}

/// A durable handoff: the **entire journal so far**, not a delta, stamped with
/// a monotonically increasing sequence number.
///
/// Sending the whole journal every time is what makes the merge rule trivial —
/// the receiver keeps whichever sequence is highest and replays it wholesale,
/// so duplicate deliveries are harmless, out-of-order deliveries are harmless,
/// and a session cut short by a dead Watch battery has already landed up to its
/// last round.
struct SyncPayload: Codable, Equatable {
    var sessionID: UUID
    var checkpointSeq: Int
    var origin: SessionOrigin
    var events: [SessionEvent]

    /// Heart-rate events are bulky (~700 per long session), already aggregated
    /// into per-segment summaries, and their raw form lives in HealthKit. The
    /// phone stores the journal without them.
    func strippingHeartRate() -> SyncPayload {
        SyncPayload(
            sessionID: sessionID,
            checkpointSeq: checkpointSeq,
            origin: origin,
            events: events.filter { !$0.isHeartRate }
        )
    }
}

struct PersonalBest: Codable, Equatable {
    var templateID: UUID
    var vestOn: Bool
    var seconds: Double
}

/// Phone → Watch reference data. Latest-value-wins: a stale intermediate
/// template list is never interesting.
struct SyncContext: Codable, Equatable {
    var templates: [TemplateSpec]
    var personalBests: [PersonalBest]
}

enum SessionMerge {
    /// Apply only a strictly newer checkpoint.
    static func shouldApply(incoming: SyncPayload, storedSeq: Int) -> Bool {
        incoming.checkpointSeq > storedSeq
    }
}
