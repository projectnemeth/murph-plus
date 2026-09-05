// MurphPlus/Models/TemplateDeletion.swift
import Foundation
import SwiftData

/// Deleting a workout template.
///
/// Templates could be created and never removed, which left the Start tab
/// accumulating every experiment the user ever typed and made one hardware
/// test (05) unrunnable. The delete itself is one line; everything interesting
/// is what must survive it.
enum TemplateDeletion {
    enum Failure: Error, Equatable {
        /// A workout is running against this template right now.
        case sessionInProgress
    }

    /// Why the template cannot be deleted at this moment, or `nil`.
    ///
    /// A live session reads its template continuously — round totals, rep
    /// counts, the run distance it is measuring against. `WorkoutTemplate`
    /// nullifies rather than cascades, so deleting mid-workout does not destroy
    /// the session, but it does hand the live screen a `nil` template, and
    /// `template?.rounds ?? 0` turns a 20-round Murph into a 0-round one under
    /// the user's thumb. Refuse instead, and say why.
    static func blocker(for template: WorkoutTemplate) -> Failure? {
        template.sessions.contains { $0.status == .inProgress } ? .sessionInProgress : nil
    }

    /// Past sessions that will outlive this template.
    ///
    /// They are kept — the workout history is the record, and `.nullify` on the
    /// relationship exists precisely so a tidy-up of the template list cannot
    /// erase months of logged times. But they do lose the template's name and
    /// its round count, so the confirmation says how many are affected rather
    /// than letting the user find out afterwards.
    static func affectedSessionCount(for template: WorkoutTemplate) -> Int {
        template.sessions.filter { $0.status != .inProgress }.count
    }

    /// All or nothing.
    ///
    /// `context.delete` removes the template from the context immediately, so a
    /// throwing `save` would otherwise leave the caller holding a deleted model
    /// *and* an error — and the Start tab's recovery, which puts its selection
    /// back on the template, would then be pointing `@State` at a deleted object
    /// that the next body evaluation dereferences for its name. Rolling back
    /// makes the failure mean what it says: nothing happened.
    static func delete(_ template: WorkoutTemplate, context: ModelContext) throws {
        if let blocker = blocker(for: template) { throw blocker }
        context.delete(template)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
