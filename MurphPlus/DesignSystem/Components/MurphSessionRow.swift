// MurphPlus/DesignSystem/Components/MurphSessionRow.swift
// History list row. Left bar is lime for completed, dust for abandoned
// (components/data/SessionRow.jsx). Abandoned rows show a dust "Abandoned"
// badge and how far the attempt got — never a fabricated duration.
import SwiftUI

struct MurphSessionRow: View {
    let templateName: String
    let dateLabel: String
    var time: String? = nil
    var vestLabel: String? = nil
    var isCompleted: Bool
    var progressLabel: String? = nil
    var isPR: Bool = false
    var showBottomDivider: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isCompleted ? MurphColor.lime500 : MurphColor.dust500)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: MurphSpacing.space1) {
                    Text(templateName)
                        .murphType(.body)
                        .foregroundStyle(MurphColor.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: MurphSpacing.space2) {
                        Text(dateLabel)
                            .murphType(.bodySm)
                            .foregroundStyle(MurphColor.textMuted)
                        if let vestLabel {
                            Text(vestLabel)
                                .murphType(.bodySm)
                                .foregroundStyle(MurphColor.textMuted)
                        }
                    }
                }
                .padding(.leading, MurphSpacing.space3)

                Spacer(minLength: MurphSpacing.space2)

                VStack(alignment: .trailing, spacing: MurphSpacing.space1) {
                    if isCompleted, let time {
                        Text(time)
                            .murphType(.metric(17))
                            .foregroundStyle(MurphColor.textPrimary)
                    } else {
                        MurphBadge(tone: .abandoned, title: "Abandoned")
                        if let progressLabel {
                            Text(progressLabel)
                                .murphType(.bodySm)
                                .foregroundStyle(MurphColor.textMuted)
                        }
                    }
                    if isPR {
                        MurphBadge(tone: .pr, title: "PR")
                    }
                }
            }
            .padding(.vertical, MurphSpacing.space3)
            .padding(.trailing, MurphSpacing.space4)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                if showBottomDivider {
                    Rectangle().fill(MurphColor.lineHairline).frame(height: MurphShape.borderHair)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
