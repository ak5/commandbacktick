import Foundation

struct CycleState {
    let ids: [String]
    private(set) var index = 0
    init(ids: [String], focused: String?, local: Set<String>, stagePeers: Set<String> = []) {
        let first = ids.first(where: { $0 == focused }) ?? ids.first
        self.ids = first.map { first in
            [first] + ids.filter { $0 != first && stagePeers.contains($0) }
                + ids.filter { $0 != first && !stagePeers.contains($0) && local.contains($0) }
                + ids.filter { $0 != first && !stagePeers.contains($0) && !local.contains($0) }
        } ?? []
    }
    mutating func step(_ direction: Int) {
        guard !ids.isEmpty else { return }
        index = (index + direction % ids.count + ids.count) % ids.count
    }
    var selected: String? { ids.isEmpty ? nil : ids[index] }
}

/// A missing physical key reading must never be treated as a confirmed release.
struct ReleaseState {
    private(set) var sawHeld = false
    mutating func update(held: Bool) -> Bool {
        if held { sawHeld = true }
        return sawHeld && !held
    }
}

/// Resolve a changed menu only when the selected title is unique. Duplicate titles
/// are usable only while the complete menu order remains unchanged.
func resolvedMenuIndex(original: [String], current: [String], selected: Int) -> Int? {
    guard original.indices.contains(selected) else { return nil }
    let matches = current.indices.filter { current[$0] == original[selected] }
    if matches.count == 1 { return matches[0] }
    return original == current && current.indices.contains(selected) ? selected : nil
}
