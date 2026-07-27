import SwiftUI

struct DiffSidebarFileRow: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let file: DiffFile
    let depth: Int
    let model: DiffModel
    let onFileRevealed: () -> Void

    private var isFocused: Bool { model.isFocusedInSidebar(file) }
    private var isDimmed: Bool { model.isDimmedInSidebar(file) }

    var body: some View {
        Button {
            model.revealFileInReader(file)
            onFileRevealed()
        } label: {
            DSHStack(spacing: .s8) {
                DiffDocumentStatusIcon(status: file.status)
                    .foregroundStyle(statusColor.color)
                Text(file.name)
                    .font(DSTextStyle.body.font(fixedSize: DiffSidebarMetric.nameSize))
                    .foregroundStyle(palette.textPrimary.color)
                    .strikethrough(isDimmed, color: palette.textPrimary.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                counters
                // Reserved trailing slot — matches the folder viewed column so marks
                // share one right edge; opacity alone toggles, never the width.
                Color.clear
                    .frame(
                        width: DiffSidebarMetric.viewedControlColumnWidth,
                        height: DiffSidebarMetric.folderControlHitSize
                    )
                    .accessibilityHidden(true)
            }
            // Opacity on the glyphs only — the surface2 fill below stays solid so the
            // row still reads as marked, not washed out.
            .opacity(isDimmed ? DSOpacity.read : 1)
            .padding(.leading, DiffSidebarMetric.rowLeadingInset(depth: depth))
            .dsPadding(.trailing, .s8)
            .frame(height: DiffSidebarMetric.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsSurface(rowSurface, radius: .sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .overlay(alignment: .trailing) {
            // Sibling of the row button (same pattern as the folder viewed control) so
            // toggling viewed does not also reveal the file.
            Button {
                model.toggleViewed(file)
            } label: {
                DiffCheckboxIcon(
                    isOn: true,
                    size: .file,
                    checkColor: palette.surface1
                )
                .foregroundStyle(palette.textPrimary.color)
                .frame(
                    width: DiffSidebarMetric.viewedControlColumnWidth,
                    height: DiffSidebarMetric.folderControlHitSize
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isDimmed ? 1 : 0)
            .allowsHitTesting(isDimmed)
            .dsPadding(.trailing, .s8)
            .accessibilityLabel("Mark as not viewed")
            .accessibilityAddTraits(isDimmed ? .isSelected : [])
            .accessibilityHidden(!isDimmed)
        }
        .id(file.path)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.name), \(file.status.title)")
        .accessibilityHint(
            model.sectionFiles.contains(where: { $0.path == file.path })
                ? "Scroll to this file in the reader"
                : "Not shown in the reader"
        )
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityValue(isDimmed ? "Viewed" : "Not viewed")
    }

    private var rowSurface: DSColorValue {
        // Strongest → weakest: focused (keyboard) > hover > dimmed (viewed) > default.
        if isFocused { return palette.surfaceSelected }
        if isHovering { return palette.surfaceHover }
        if isDimmed { return palette.surface2 }
        return palette.surface1
    }

    private var statusColor: DSColorValue {
        switch file.status {
        case .added: palette.diffAdd
        case .deleted: palette.diffDel
        case .modified, .renamed: palette.textSecondary
        }
    }

    private var counters: some View {
        DSHStack(spacing: .s4) {
            Text(file.additionsLabel)
                .foregroundStyle(palette.diffAdd.color)
                .frame(minWidth: DiffSidebarMetric.counterMinWidth, alignment: .trailing)
            Text(file.deletionsLabel)
                .foregroundStyle(palette.diffDel.color)
                .frame(minWidth: DiffSidebarMetric.counterMinWidth, alignment: .trailing)
        }
        .font(DSTextStyle.code.font(fixedSize: DiffSidebarMetric.counterSize))
        .lineLimit(1)
    }
}
