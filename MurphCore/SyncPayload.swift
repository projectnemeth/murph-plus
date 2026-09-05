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

    /// The largest encoded payload that still goes by `transferUserInfo`.
    /// Anything at or above it takes the file-transfer path instead — same
    /// queued, guaranteed delivery, no size limit.
    ///
    /// Deliberately below WatchConnectivity's documented 65,536: that ceiling
    /// applies to the serialized `[String: Any]` **dictionary**, not to the
    /// `Data` inside it, and `transferUserInfo([SyncKey.payload: data])` adds
    /// property-list framing plus the key on top. A payload just under 65,536
    /// would pass this check and then breach the real limit — a silent drop, on
    /// the checkpoint most likely to be the terminal one. The margin costs
    /// nothing: the file-transfer path is equally durable, so the only price of
    /// crossing over early is a temporary file.
    static var userInfoByteLimit: Int {
        // Overridable in DEBUG so hardware tests 11 and 12 can force the
        // file-transfer path without editing this file — the real trigger is a
        // session past roughly 2h13m, which is not a thing to sit through, and
        // an edited-then-forgotten constant here drops checkpoints silently.
        DebugOverride.int("MurphUserInfoByteLimit") ?? defaultUserInfoByteLimit
    }

    static let defaultUserInfoByteLimit = 60_000

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

    /// Sessions the phone holds **in a terminal state**.
    ///
    /// This is the acknowledgement half of the durable channel, and the reason
    /// the Watch can ever delete a journal. Terminal specifically, not merely
    /// "seen": a session the phone holds mid-way is one whose final checkpoint
    /// never landed, and acknowledging that would let the Watch destroy the
    /// only remaining copy of a workout the phone will show as in-progress
    /// forever.
    ///
    /// Latest-value-wins like the rest of the context, so it is a full list
    /// each time rather than a delta.
    var acknowledgedSessionIDs: [UUID]

    /// The date of the oldest session in `acknowledgedSessionIDs`, when that
    /// list had to be capped — otherwise `nil`, meaning the list is complete.
    ///
    /// Without it the cap is a trap. A journal the phone already holds, but
    /// which has fallen outside the capped window, can never be named — so the
    /// Watch resends it, the phone ignores it as a stale sequence and its
    /// acknowledgement set never changes, and the same journal is re-transferred
    /// on every reconcile pass for the life of the install. The horizon closes
    /// that loop: a terminal journal older than it is provably beyond what the
    /// phone will ever acknowledge, so the Watch stops asking and lets it go.
    var acknowledgementHorizon: Date?

    init(
        templates: [TemplateSpec],
        personalBests: [PersonalBest],
        acknowledgedSessionIDs: [UUID] = [],
        acknowledgementHorizon: Date? = nil
    ) {
        self.templates = templates
        self.personalBests = personalBests
        self.acknowledgedSessionIDs = acknowledgedSessionIDs
        self.acknowledgementHorizon = acknowledgementHorizon
    }

    /// Hand-written for one key only: `acknowledgedSessionIDs` must decode as
    /// empty when absent rather than failing the whole context.
    ///
    /// A user updates one device before the other — routinely, since the Watch
    /// app updates with the phone app but on the Watch's own schedule — so a
    /// new Watch will meet an old phone's context. Synthesised `Codable` throws
    /// on a missing key, and a context that fails to decode is dropped in
    /// silence, taking the template list and personal bests with it. Empty is
    /// also the safe value: it acknowledges nothing, so the Watch keeps every
    /// journal.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        templates = try container.decode([TemplateSpec].self, forKey: .templates)
        personalBests = try container.decode([PersonalBest].self, forKey: .personalBests)
        acknowledgedSessionIDs =
            try container.decodeIfPresent([UUID].self, forKey: .acknowledgedSessionIDs) ?? []
        // Absent means "the list is complete", which is also what an older
        // phone's context means — it acknowledged everything it had.
        acknowledgementHorizon =
            try container.decodeIfPresent(Date.self, forKey: .acknowledgementHorizon)
    }
}

enum SessionMerge {
    /// Apply only a strictly newer checkpoint.
    static func shouldApply(incoming: SyncPayload, storedSeq: Int) -> Bool {
        incoming.checkpointSeq > storedSeq
    }
}

/// All three channels carry a single JSON blob under one key, which sidesteps
/// WatchConnectivity's property-list type constraints entirely.
enum SyncKey {
    static let payload = "payload"
    static let liveEvent = "liveEvent"
    static let liveSessionID = "liveSessionID"
    static let context = "context"
}
