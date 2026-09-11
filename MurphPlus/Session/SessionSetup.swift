// MurphPlus/Session/SessionSetup.swift
import Foundation

/// What the user chose on the setup screen, handed to `RootTabView` as one
/// value.
///
/// A struct rather than a fourth closure parameter because `indoor` and
/// `vestOn` are both `Bool`: as positional arguments they would sit adjacent
/// and unlabelled at the call site, where transposing them silently produces a
/// vested indoor session that never powers the receiver.
struct SessionSetup {
    let template: WorkoutTemplate
    let vestOn: Bool
    let vestWeightLbs: Int?
    let indoor: Bool
}
