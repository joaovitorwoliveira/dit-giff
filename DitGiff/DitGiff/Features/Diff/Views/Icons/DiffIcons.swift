import SwiftUI

struct DiffLogoIcon: View {
    var body: some View {
        DiffLogoShape()
            .fill()
            .frame(width: DiffIconMetric.logoSize, height: DiffIconMetric.logoSize)
            .accessibilityLabel("Dit Giff")
    }
}

struct DiffSidebarToggleIcon: View {
    var body: some View {
        DiffSidebarToggleShape()
            .stroke(lineWidth: DiffIconMetric.sidebarToggleStroke)
            .frame(
                width: DiffIconMetric.sidebarToggleSize,
                height: DiffIconMetric.sidebarToggleSize
            )
    }
}

struct DiffChevronIcon: View {
    var body: some View {
        DiffChevronShape()
            .stroke(
                style: StrokeStyle(
                    lineWidth: DiffIconMetric.chevronStroke,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: DiffIconMetric.chevronSize, height: DiffIconMetric.chevronSize)
    }
}

struct DiffFolderIcon: View {
    var body: some View {
        DiffFolderShape()
            .fill()
            .opacity(DiffIconMetric.folderOpacity)
            .frame(width: DiffIconMetric.folderSize, height: DiffIconMetric.folderSize)
    }
}

/// Document mark with the status symbol inside. One view, four statuses — the color
/// comes from the caller's `foregroundStyle`.
struct DiffDocumentStatusIcon: View {
    let status: DiffFileStatus

    var body: some View {
        ZStack {
            DiffDocumentBodyShape()
                .fill()
                .opacity(DiffIconMetric.documentBodyOpacity)
            DiffDocumentStatusSymbolShape(status: status)
                .stroke(
                    style: StrokeStyle(
                        lineWidth: DiffIconMetric.documentStatusStroke,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
        }
        .frame(
            width: DiffIconMetric.documentStatusSize,
            height: DiffIconMetric.documentStatusSize
        )
        .accessibilityLabel(status.title)
    }
}

struct DiffExplainFileIcon: View {
    var body: some View {
        DiffExplainFileShape()
            .stroke(
                style: StrokeStyle(
                    lineWidth: DiffIconMetric.explainFileStroke,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(
                width: DiffIconMetric.explainFileSize,
                height: DiffIconMetric.explainFileSize
            )
    }
}

/// Empty or filled checkbox. The check mark takes `checkColor` so it can sit on
/// `surface1` while the box itself follows `foregroundStyle`.
struct DiffCheckboxIcon: View {
    enum Size {
        case file
        case hunk

        var points: CGFloat {
            switch self {
            case .file: DiffIconMetric.fileCheckboxSize
            case .hunk: DiffIconMetric.hunkCheckboxSize
            }
        }

        var checkStroke: CGFloat {
            switch self {
            case .file: DiffIconMetric.fileCheckboxCheckStroke
            case .hunk: DiffIconMetric.hunkCheckboxCheckStroke
            }
        }
    }

    let isOn: Bool
    let size: Size
    let checkColor: DSColorValue

    var body: some View {
        ZStack {
            if isOn {
                DiffCheckboxFilledShape()
                    .fill()
                DiffCheckboxCheckShape()
                    .stroke(
                        style: StrokeStyle(
                            lineWidth: size.checkStroke,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .foregroundStyle(checkColor.color)
            } else {
                DiffCheckboxEmptyShape()
                    .stroke(lineWidth: DiffIconMetric.checkboxEmptyStroke)
            }
        }
        .frame(width: size.points, height: size.points)
    }
}

struct DiffHunkExplainIcon: View {
    var body: some View {
        DiffHunkExplainShape()
            .stroke(
                style: StrokeStyle(
                    lineWidth: DiffIconMetric.hunkExplainStroke,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(
                width: DiffIconMetric.hunkActionSize,
                height: DiffIconMetric.hunkActionSize
            )
    }
}

struct DiffHunkChatIcon: View {
    var body: some View {
        DiffHunkChatShape()
            .stroke(
                style: StrokeStyle(
                    lineWidth: DiffIconMetric.hunkChatStroke,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(
                width: DiffIconMetric.hunkActionSize,
                height: DiffIconMetric.hunkActionSize
            )
    }
}

/// Same lines as the hunk explain mark, at the popover's 14pt / 1.3 stroke.
struct DiffExplainSelectionIcon: View {
    var body: some View {
        DiffHunkExplainShape()
            .stroke(
                style: StrokeStyle(
                    lineWidth: DiffIconMetric.explainSelectionStroke,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(
                width: DiffIconMetric.explainSelectionSize,
                height: DiffIconMetric.explainSelectionSize
            )
    }
}

struct DiffSendArrowIcon: View {
    var body: some View {
        DiffSendArrowShape()
            .stroke(
                style: StrokeStyle(
                    lineWidth: DiffIconMetric.sendArrowStroke,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(
                width: DiffIconMetric.sendArrowSize,
                height: DiffIconMetric.sendArrowSize
            )
    }
}

struct DiffCloseIcon: View {
    var body: some View {
        DiffCloseShape()
            .stroke(
                style: StrokeStyle(
                    lineWidth: DiffIconMetric.closeStroke,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: DiffIconMetric.closeSize, height: DiffIconMetric.closeSize)
    }
}

/// Document outline for a location chip — stroke only, no status glyph.
struct DiffLocationDocIcon: View {
    var body: some View {
        DiffDocumentBodyShape()
            .stroke(
                style: StrokeStyle(
                    lineWidth: DiffIconMetric.locationDocStroke,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(
                width: DiffIconMetric.locationDocSize,
                height: DiffIconMetric.locationDocSize
            )
    }
}

#Preview("Drawn icons") {
    DSHStack(spacing: .s16) {
        DiffLogoIcon()
        DiffSidebarToggleIcon()
        DiffChevronIcon()
        DiffFolderIcon()
        DiffDocumentStatusIcon(status: .modified)
        DiffExplainFileIcon()
        DiffCheckboxIcon(isOn: false, size: .file, checkColor: DSPalette.dark.surface1)
        DiffCheckboxIcon(isOn: true, size: .file, checkColor: DSPalette.dark.surface1)
        DiffHunkExplainIcon()
        DiffHunkChatIcon()
        DiffExplainSelectionIcon()
        DiffSendArrowIcon()
        DiffCloseIcon()
        DiffLocationDocIcon()
    }
    .foregroundStyle(DSPalette.dark.textPrimary.color)
    .dsPadding(.all, .s24)
    .dsSurface(DSPalette.dark.surface1)
    .preferredColorScheme(.dark)
}
