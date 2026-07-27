import SwiftUI

/// The marks SF Symbols has no honest match for, drawn from the prototype's SVG paths in
/// `scratchpad/icons.md`. Each shape maps its own viewBox onto whatever rect it is given,
/// and takes its color from the caller's `foregroundStyle`, the way a symbol does.

/// Sizes and stroke weights are properties of the drawings, not of the bar that hosts
/// them, so they live with the drawings.
enum DiffIconMetric {
    static let logoSize: CGFloat = 22
    static let sidebarToggleSize: CGFloat = 16
    static let sidebarToggleStroke: CGFloat = 1.3
    static let backArrowSize: CGFloat = 14
    static let themeSize: CGFloat = 15

    static let chevronSize: CGFloat = 14
    static let chevronStroke: CGFloat = 1.5
    static let folderSize: CGFloat = 18
    /// Folder outline — matches `documentBodyStroke` so folder and file weigh the same in the tree.
    static let folderBodyStroke: CGFloat = 1.5
    static let documentStatusSize: CGFloat = 18
    /// Outer document outline — thicker than the inner status glyph so the file edge reads first.
    static let documentBodyStroke: CGFloat = 1.5
    static let documentStatusStroke: CGFloat = 1.25

    static let explainFileSize: CGFloat = 19
    static let explainFileStroke: CGFloat = 1.3

    static let fileCheckboxSize: CGFloat = 17
    static let checkboxEmptyStroke: CGFloat = 1.3
    static let fileCheckboxCheckStroke: CGFloat = 1.6

    static let explainSelectionSize: CGFloat = 14
    static let explainSelectionStroke: CGFloat = 1.3
    static let sendArrowSize: CGFloat = 15
    static let sendArrowStroke: CGFloat = 1.4
    static let closeSize: CGFloat = 12
    static let closeStroke: CGFloat = 1.5
    static let locationDocSize: CGFloat = 11
    static let locationDocStroke: CGFloat = 1.4
}

/// The app mark: the "d" of three rounded bars. viewBox 1024.
nonisolated struct DiffLogoShape: Shape {
    private struct Bar {
        let frame: CGRect
        let radius: CGFloat
    }

    private static let viewBox: CGFloat = 1024

    private static let bars = [
        Bar(frame: CGRect(x: 112.64, y: 466.94, width: 337.92, height: 90.11), radius: 45.06),
        Bar(frame: CGRect(x: 236.54, y: 343.04, width: 90.11, height: 337.92), radius: 45.06),
        Bar(frame: CGRect(x: 570.06, y: 464.24, width: 344.68, height: 95.52), radius: 47.76),
    ]

    func path(in rect: CGRect) -> Path {
        let box = DiffIconViewBox(side: Self.viewBox, in: rect)
        var path = Path()
        for bar in Self.bars {
            path.addRoundedRect(
                in: box.scaled(bar.frame),
                cornerSize: box.scaled(radius: bar.radius)
            )
        }
        return path
    }
}

/// The change-map toggle: a panel split by a rule. `sidebar.left` has the panel but not
/// the rule, and the rule is the whole point. viewBox 16, stroked.
nonisolated struct DiffSidebarToggleShape: Shape {
    private static let viewBox: CGFloat = 16
    private static let panel = CGRect(x: 1.5, y: 2.5, width: 13, height: 11)
    private static let panelRadius: CGFloat = 1.6
    private static let dividerX: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let box = DiffIconViewBox(side: Self.viewBox, in: rect)
        var path = Path()
        path.addRoundedRect(
            in: box.scaled(Self.panel),
            cornerSize: box.scaled(radius: Self.panelRadius)
        )
        path.move(to: box.scaled(x: Self.dividerX, y: Self.panel.minY))
        path.addLine(to: box.scaled(x: Self.dividerX, y: Self.panel.maxY))
        return path
    }
}

/// The change-map chevron: points right when closed, rotates 90° when open. viewBox 12.
nonisolated struct DiffChevronShape: Shape {
    private static let viewBox: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let box = DiffIconViewBox(side: Self.viewBox, in: rect)
        var path = Path()
        path.move(to: box.scaled(x: 4.5, y: 2.5))
        path.addLine(to: box.scaled(x: 8, y: 6))
        path.addLine(to: box.scaled(x: 4.5, y: 9.5))
        return path
    }
}

/// The folder outline on a directory row. Closed path so stroke and former fill agree.
/// viewBox 16.
nonisolated struct DiffFolderShape: Shape {
    private static let viewBox: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let box = DiffIconViewBox(side: Self.viewBox, in: rect)
        var path = Path()
        path.move(to: box.scaled(x: 1.5, y: 4.5))
        path.addLine(to: box.scaled(x: 5.7, y: 4.5))
        path.addLine(to: box.scaled(x: 7.3, y: 6.5))
        path.addLine(to: box.scaled(x: 14.5, y: 6.5))
        path.addLine(to: box.scaled(x: 14.5, y: 12.5))
        box.addCornerArc(to: &path, from: (14.5, 12.5), to: (13.5, 13.5), center: (13.5, 12.5))
        path.addLine(to: box.scaled(x: 2.5, y: 13.5))
        box.addCornerArc(to: &path, from: (2.5, 13.5), to: (1.5, 12.5), center: (2.5, 12.5))
        path.addLine(to: box.scaled(x: 1.5, y: 4.5))
        path.closeSubpath()
        return path
    }
}

/// The document silhouette shared by every file-status glyph. viewBox 16.
nonisolated struct DiffDocumentBodyShape: Shape {
    private static let viewBox: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let box = DiffIconViewBox(side: Self.viewBox, in: rect)
        var path = Path()
        path.move(to: box.scaled(x: 4.3, y: 2.3))
        path.addLine(to: box.scaled(x: 8.7, y: 2.3))
        path.addLine(to: box.scaled(x: 11.6, y: 5.2))
        path.addLine(to: box.scaled(x: 11.6, y: 12.7))
        box.addCornerArc(to: &path, from: (11.6, 12.7), to: (10.6, 13.7), center: (10.6, 12.7))
        path.addLine(to: box.scaled(x: 4.3, y: 13.7))
        box.addCornerArc(to: &path, from: (4.3, 13.7), to: (3.3, 12.7), center: (4.3, 12.7))
        path.addLine(to: box.scaled(x: 3.3, y: 3.3))
        box.addCornerArc(to: &path, from: (3.3, 3.3), to: (4.3, 2.3), center: (4.3, 3.3))
        path.closeSubpath()
        return path
    }
}

/// The status mark drawn inside the document: one Shape, four symbols. viewBox 16.
nonisolated struct DiffDocumentStatusSymbolShape: Shape {
    let status: DiffFileStatus

    private static let viewBox: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let box = DiffIconViewBox(side: Self.viewBox, in: rect)
        var path = Path()
        switch status {
        case .added:
            path.move(to: box.scaled(x: 7.35, y: 5.8))
            path.addLine(to: box.scaled(x: 7.35, y: 10.2))
            path.move(to: box.scaled(x: 5.15, y: 8))
            path.addLine(to: box.scaled(x: 9.55, y: 8))
        case .deleted:
            path.move(to: box.scaled(x: 5.15, y: 8))
            path.addLine(to: box.scaled(x: 9.55, y: 8))
        case .modified:
            path.move(to: box.scaled(x: 5.15, y: 6.9))
            path.addLine(to: box.scaled(x: 9.55, y: 6.9))
            path.move(to: box.scaled(x: 5.15, y: 9.1))
            path.addLine(to: box.scaled(x: 9.55, y: 9.1))
        case .renamed:
            path.move(to: box.scaled(x: 5, y: 8))
            path.addLine(to: box.scaled(x: 8.4, y: 8))
            path.move(to: box.scaled(x: 7.1, y: 6.3))
            path.addLine(to: box.scaled(x: 8.9, y: 8))
            path.addLine(to: box.scaled(x: 7.1, y: 9.7))
        }
        return path
    }
}

/// Explain-this-file: a document with a person mark. viewBox 20, stroked.
nonisolated struct DiffExplainFileShape: Shape {
    private static let viewBox: CGFloat = 20
    private static let page = CGRect(x: 1.5, y: 2, width: 11, height: 14)
    private static let pageRadius: CGFloat = 1.5
    private static let headCenter = CGPoint(x: 16, y: 6)
    private static let headRadius: CGFloat = 2.3

    func path(in rect: CGRect) -> Path {
        let box = DiffIconViewBox(side: Self.viewBox, in: rect)
        var path = Path()
        path.addRoundedRect(
            in: box.scaled(Self.page),
            cornerSize: box.scaled(radius: Self.pageRadius)
        )
        path.move(to: box.scaled(x: 4, y: 5.5))
        path.addLine(to: box.scaled(x: 10, y: 5.5))
        path.move(to: box.scaled(x: 4, y: 8))
        path.addLine(to: box.scaled(x: 10, y: 8))
        path.move(to: box.scaled(x: 4, y: 10.5))
        path.addLine(to: box.scaled(x: 8, y: 10.5))
        let headOrigin = box.scaled(
            x: Self.headCenter.x - Self.headRadius,
            y: Self.headCenter.y - Self.headRadius
        )
        let headSide = box.scaled(radius: Self.headRadius).width * 2
        path.addEllipse(in: CGRect(x: headOrigin.x, y: headOrigin.y, width: headSide, height: headSide))
        // Shoulders: M12.5 16.5c0-2.4 1.8-4.3 4-4.3s4 1.9 4 4.3
        path.move(to: box.scaled(x: 12.5, y: 16.5))
        path.addCurve(
            to: box.scaled(x: 16.5, y: 12.2),
            control1: box.scaled(x: 12.5, y: 14.1),
            control2: box.scaled(x: 14.3, y: 12.2)
        )
        path.addCurve(
            to: box.scaled(x: 20.5, y: 16.5),
            control1: box.scaled(x: 18.7, y: 12.2),
            control2: box.scaled(x: 20.5, y: 14.1)
        )
        return path
    }
}

/// Empty checkbox outline. viewBox 16.
nonisolated struct DiffCheckboxEmptyShape: Shape {
    private static let viewBox: CGFloat = 16
    private static let frame = CGRect(x: 2.5, y: 2.5, width: 11, height: 11)
    private static let radius: CGFloat = 2.6

    func path(in rect: CGRect) -> Path {
        let box = DiffIconViewBox(side: Self.viewBox, in: rect)
        var path = Path()
        path.addRoundedRect(
            in: box.scaled(Self.frame),
            cornerSize: box.scaled(radius: Self.radius)
        )
        return path
    }
}

/// Filled checkbox body. viewBox 16.
nonisolated struct DiffCheckboxFilledShape: Shape {
    private static let viewBox: CGFloat = 16
    private static let frame = CGRect(x: 2, y: 2, width: 12, height: 12)
    private static let radius: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let box = DiffIconViewBox(side: Self.viewBox, in: rect)
        var path = Path()
        path.addRoundedRect(
            in: box.scaled(Self.frame),
            cornerSize: box.scaled(radius: Self.radius)
        )
        return path
    }
}

/// The check mark inside a filled checkbox. viewBox 16.
nonisolated struct DiffCheckboxCheckShape: Shape {
    private static let viewBox: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let box = DiffIconViewBox(side: Self.viewBox, in: rect)
        var path = Path()
        path.move(to: box.scaled(x: 4.8, y: 8.2))
        path.addLine(to: box.scaled(x: 6.8, y: 10.2))
        path.addLine(to: box.scaled(x: 11.2, y: 5.8))
        return path
    }
}

/// Hunk "explain" lines. viewBox 16.
nonisolated struct DiffHunkExplainShape: Shape {
    private static let viewBox: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let box = DiffIconViewBox(side: Self.viewBox, in: rect)
        var path = Path()
        path.move(to: box.scaled(x: 2.5, y: 4))
        path.addLine(to: box.scaled(x: 13.5, y: 4))
        path.move(to: box.scaled(x: 2.5, y: 8))
        path.addLine(to: box.scaled(x: 13.5, y: 8))
        path.move(to: box.scaled(x: 2.5, y: 12))
        path.addLine(to: box.scaled(x: 8.5, y: 12))
        return path
    }
}

/// Send arrow for the selection popover. viewBox 16.
nonisolated struct DiffSendArrowShape: Shape {
    private static let viewBox: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let box = DiffIconViewBox(side: Self.viewBox, in: rect)
        var path = Path()
        path.move(to: box.scaled(x: 2, y: 8))
        path.addLine(to: box.scaled(x: 13.5, y: 8))
        path.move(to: box.scaled(x: 8.5, y: 3))
        path.addLine(to: box.scaled(x: 13.5, y: 8))
        path.addLine(to: box.scaled(x: 8.5, y: 13))
        return path
    }
}

/// Close mark for the chat panel. viewBox 12.
nonisolated struct DiffCloseShape: Shape {
    private static let viewBox: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let box = DiffIconViewBox(side: Self.viewBox, in: rect)
        var path = Path()
        path.move(to: box.scaled(x: 2.5, y: 2.5))
        path.addLine(to: box.scaled(x: 9.5, y: 9.5))
        path.move(to: box.scaled(x: 9.5, y: 2.5))
        path.addLine(to: box.scaled(x: 2.5, y: 9.5))
        return path
    }
}

/// Maps an SVG viewBox onto a rect: uniform scale, centered, so an icon drawn at any
/// size keeps its proportions.
nonisolated private struct DiffIconViewBox {
    private let scale: CGFloat
    private let origin: CGPoint

    init(side: CGFloat, in rect: CGRect) {
        scale = min(rect.width, rect.height) / side
        origin = CGPoint(
            x: rect.midX - side * scale / 2,
            y: rect.midY - side * scale / 2
        )
    }

    func scaled(_ frame: CGRect) -> CGRect {
        CGRect(
            x: origin.x + frame.minX * scale,
            y: origin.y + frame.minY * scale,
            width: frame.width * scale,
            height: frame.height * scale
        )
    }

    func scaled(radius: CGFloat) -> CGSize {
        CGSize(width: radius * scale, height: radius * scale)
    }

    func scaled(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    /// A unit-radius SVG corner arc (`a1 1 0 0 1 …`), drawn as a cubic so the path
    /// stays in viewBox space and never fights SwiftUI's arc winding.
    func addCornerArc(
        to path: inout Path,
        from: (CGFloat, CGFloat),
        to: (CGFloat, CGFloat),
        center: (CGFloat, CGFloat)
    ) {
        // κ ≈ 0.552 for a quarter-circle cubic approximation.
        let kappa: CGFloat = 0.5522847498
        let sx = from.0 - center.0
        let sy = from.1 - center.1
        let ex = to.0 - center.0
        let ey = to.1 - center.1
        // Unit tangents in the direction of travel, perpendicular to each radius.
        var t0x = -sy
        var t0y = sx
        if t0x * ex + t0y * ey < 0 {
            t0x = -t0x
            t0y = -t0y
        }
        var t1x = -ey
        var t1y = ex
        if t1x * sx + t1y * sy < 0 {
            t1x = -t1x
            t1y = -t1y
        }
        let control1 = scaled(x: from.0 + kappa * t0x, y: from.1 + kappa * t0y)
        let control2 = scaled(x: to.0 - kappa * t1x, y: to.1 - kappa * t1y)
        path.addCurve(to: scaled(x: to.0, y: to.1), control1: control1, control2: control2)
    }
}
