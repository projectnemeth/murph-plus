// MurphPlus/DesignSystem/Components/MurphDialog.swift
// Bottom sheet, hazard top border, blurred scrim (components/feedback/Dialog.jsx).
// Leave `onDismiss` off when the choice is mandatory — the resume prompt has
// no dismiss. Rendered as an in-place overlay (not a system sheet) so it can
// be anchored within a single screen, matching the source design system.
import SwiftUI

struct MurphDialog<Actions: View>: View {
    let title: String
    let body_: String
    var onDismiss: (() -> Void)? = nil
    @ViewBuilder var actions: Actions

    init(title: String, body: String, onDismiss: (() -> Void)? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.body_ = body
        self.onDismiss = onDismiss
        self.actions = actions()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { onDismiss?() }

            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: MurphSpacing.space4) {
                    Rectangle()
                        .fill(MurphColor.hazard500)
                        .frame(height: MurphShape.borderStrong)
                        .padding(.horizontal, -MurphSpacing.space5)

                    Text(title)
                        .murphType(.title())
                        .foregroundStyle(MurphColor.textPrimary)
                    Text(body_)
                        .murphType(.body)
                        .foregroundStyle(MurphColor.textSecondary)

                    VStack(spacing: MurphSpacing.space3) {
                        actions
                    }
                    .padding(.top, MurphSpacing.space2)
                }
                .padding(MurphSpacing.space5)
                .padding(.bottom, MurphSpacing.space6)
                .background(MurphColor.surfaceCard)
                .clipShape(.rect(topLeadingRadius: MurphShape.radiusLg, topTrailingRadius: MurphShape.radiusLg))
            }
            .transition(.move(edge: .bottom))
        }
        .animation(MurphMotion.easeSnap, value: title)
    }
}
