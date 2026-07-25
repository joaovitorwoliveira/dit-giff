import Foundation

/// What Welcome hands to the diff screen. Slice 3 will read the real diff from this;
/// until then the diff UI still draws sample data, but the session is already in place.
nonisolated struct DiffSession: Equatable, Sendable {
    let repository: GitRepository
    let base: GitBranch
    let compare: GitBranch
    let goal: String
    let attachedSpecName: String?
}
