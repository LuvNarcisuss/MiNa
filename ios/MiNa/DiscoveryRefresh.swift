import Foundation

struct DiscoveryOrder {
    private var positions: [String: Int] = [:]

    func arranged<Item: Identifiable>(_ items: [Item]) -> [Item] where Item.ID == String {
        guard !positions.isEmpty else { return items }
        return items.sorted { positions[$0.id, default: .max] < positions[$1.id, default: .max] }
    }

    mutating func shuffle<Item: Identifiable>(_ items: [Item], replacing first: String?) where Item.ID == String {
        var ids = items.map(\.id).shuffled()
        if ids.count > 1, ids.first == first {
            ids.swapAt(0, Int.random(in: 1..<ids.count))
        }
        positions = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
    }
}

// A foreground pull takes precedence over polling for the same list.
struct DiscoveryLoad {
    private(set) var current: UUID?
    private var pullScope: String?

    mutating func begin(scope: String, pull: Bool) -> UUID? {
        guard pull || pullScope != scope else { return nil }
        let id = UUID()
        current = id
        pullScope = pull ? scope : nil
        return id
    }

    mutating func finish(_ id: UUID) {
        if current == id {
            current = nil
            pullScope = nil
        }
    }
}
