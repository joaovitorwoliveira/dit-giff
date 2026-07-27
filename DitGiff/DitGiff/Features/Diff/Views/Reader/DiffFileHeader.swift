import SwiftUI

// MARK: - Sticky file header

struct DiffFileStickyHeader: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let file: DiffFile
    let model: DiffModel

    private var isOpen: Bool { !model.isCollapsed(file) }
    private var isViewed: Bool { model.isViewed(file) }

    var body: some View {
        DSHStack(spacing: .s8) {
            collapseButton
            pathLabel
            counters
            // Sparkles and Viewed carry unequal internal padding (6 vs 8 horizontal).
            // A single stack spacing makes the optical gap between counters→sparkles
            // smaller than sparkles→Viewed; zero inner spacing equalizes both at 14pt.
            DSHStack(spacing: nil) {
                DiffExplainFileButton(
                    isEnabled: model.canExplainFile(file)
                ) {
                    model.explainFile(file)
                }
                DiffViewedButton(isViewed: isViewed) { model.toggleViewed(file) }
            }
        }
        .dsPadding(.leading, .s8)
        .dsPadding(.trailing, .s12)
        .frame(height: DiffViewerMetric.headerHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Pinned headers leave the section flow, so the file card cannot be one
        // outer shape. Top-only corners while open; all four when collapsed alone.
        .background {
            DiffFileCardChrome.shape(topRounded: true, bottomRounded: !isOpen)
                .fill(palette.surface1.color)
        }
        .overlay {
            DiffFileCardChrome.shape(topRounded: true, bottomRounded: !isOpen)
                .strokeBorder(
                    palette.borderSubtle.color,
                    lineWidth: DiffViewerMetric.hairline
                )
        }
    }

    private var collapseButton: some View {
        Button {
            model.toggleCollapsed(file)
        } label: {
            DiffChevronIcon()
                .foregroundStyle(palette.textTertiary.color)
                .frame(
                    width: DiffViewerMetric.chevronHitSize,
                    height: DiffViewerMetric.chevronHitSize
                )
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .animation(
                    DSMotion.collapse.animation(reduceMotion: reduceMotion),
                    value: isOpen
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOpen ? "Collapse \(file.name)" : "Expand \(file.name)")
    }

    private var pathLabel: some View {
        // Directory yields first and truncates at the *head* so the file name — the
        // identity of the row — stays whole. Never truncate the name with ellipsis.
        DSHStack(alignment: .firstTextBaseline, spacing: nil) {
            Text(file.directory)
                .font(DSTextStyle.body.font(fixedSize: DiffViewerMetric.directorySize))
                .foregroundStyle(palette.textTertiary.color)
                .lineLimit(1)
                .truncationMode(.head)
                .layoutPriority(-1)
            Text(file.name)
                .font(DSTextStyle.panelTitle.font(fixedSize: DiffViewerMetric.fileNameSize))
                .foregroundStyle(palette.textPrimary.color)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var counters: some View {
        DSHStack(spacing: .s4) {
            Text(file.additionsLabel)
                .foregroundStyle(palette.diffAdd.color)
            Text(file.deletionsLabel)
                .foregroundStyle(palette.diffDel.color)
        }
        .font(DSTextStyle.code.font(fixedSize: DiffViewerMetric.statsSize))
        .lineLimit(1)
    }
}

private struct DiffExplainFileButton: View {
    @Environment(\.dsPalette) private var palette

    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.system(size: DiffViewerMetric.explainSparklesSize))
                .foregroundStyle(palette.textTertiary.color)
                .frame(
                    width: DiffIconMetric.explainFileSize,
                    height: DiffIconMetric.explainFileSize
                )
                .padding(DiffViewerMetric.iconButtonPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : DiffViewerMetric.disabledOpacity)
        .accessibilityLabel("Explain this file")
    }
}

private struct DiffViewedButton: View {
    @Environment(\.dsPalette) private var palette

    let isViewed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Gap 6 is off the closed scale, so this stack takes the metric directly.
            HStack(spacing: DiffViewerMetric.viewedCheckboxGap) {
                DiffCheckboxIcon(
                    isOn: isViewed,
                    size: .file,
                    checkColor: palette.surface1
                )
                Text("Viewed")
                    .font(DSTextStyle.label.font(fixedSize: DiffViewerMetric.viewedLabelSize))
                    .lineLimit(1)
            }
            .foregroundStyle(
                isViewed ? palette.textPrimary.color : palette.textTertiary.color
            )
            .padding(.vertical, DiffViewerMetric.viewedVerticalPadding)
            .dsPadding(.horizontal, .s8)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.sm.points, style: .continuous)
                    .fill(isViewed ? palette.surface3.color : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityLabel(isViewed ? "Mark as not viewed" : "Mark as viewed")
        .accessibilityAddTraits(isViewed ? .isSelected : [])
    }
}
