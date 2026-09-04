// MurphCore/PersonalBestCheck.swift
import Foundation

/// Decides whether a just-finished session beat its own record.
///
/// In MurphCore because both devices ask the question: the Watch badges the
/// completion screen from synced context, and the phone computes the records
/// that are synced down.
enum PersonalBestCheck {
    /// - Returns: `true` only when a record for this exact template *and* vest
    ///   state already exists and this time is strictly faster than it.
    ///
    /// Vest state is part of the identity, never a tiebreak: a vested Murph is
    /// a materially harder workout, so beating an unvested record says nothing
    /// about it. With no matching record there is nothing to beat, so a first
    /// attempt is not badged — otherwise every debut would claim a best.
    static func isPersonalBest(
        elapsed: TimeInterval,
        templateID: UUID?,
        vestOn: Bool,
        among bests: [PersonalBest]
    ) -> Bool {
        guard let templateID else { return false }
        guard let best = bests.first(where: {
            $0.templateID == templateID && $0.vestOn == vestOn
        }) else { return false }
        return elapsed < best.seconds
    }
}
