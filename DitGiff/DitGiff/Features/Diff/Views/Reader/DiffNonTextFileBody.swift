import SwiftUI

/// Short reader entry for binary, submodule, and no-content files — descriptive,
/// never a verdict. Content only: outer card chrome is applied by DiffFileBody,
/// same path as text hunks.
struct DiffNonTextFileBody: View {
    @Environment(\.dsPalette) private var palette

    let file: DiffFile

    var body: some View {
        DSVStack(alignment: .leading, spacing: .s8) {
            Text(file.body.readerSummary)
                .dsText(.body)
                .foregroundStyle(palette.textSecondary.color)
            if let detail = file.body.readerDetail {
                Text(detail)
                    .dsText(.code)
                    .foregroundStyle(palette.textTertiary.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPadding(.all, .s16)
    }
}
