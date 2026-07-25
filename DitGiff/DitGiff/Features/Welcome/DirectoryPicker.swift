import AppKit
import Foundation

/// Opens a directory picker. The seam exists so Welcome tests never put up a panel.
@MainActor
protocol DirectoryPicker: AnyObject {
    func pickDirectory() async -> URL?
}

@MainActor
final class SystemDirectoryPicker: DirectoryPicker {
    func pickDirectory() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"
        panel.message = "Choose a Git repository folder"
        let response = panel.runModal()
        guard response == .OK else { return nil }
        return panel.url
    }
}
