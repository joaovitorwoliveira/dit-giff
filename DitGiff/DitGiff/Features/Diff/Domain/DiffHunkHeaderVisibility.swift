import Foundation

/// Whether the reader draws the @@ band above a file's hunks.
///
/// The band only informs when a file has two or more hunks — where one piece ends
/// and another begins. A single hunk is the whole file body; repeating it as a
/// divider adds no information.
nonisolated enum DiffHunkHeaderVisibility {
    /// `true` when the @@ header band should appear for every hunk of the file.
    static func showsHeader(hunkCount: Int) -> Bool {
        hunkCount >= 2
    }
}
