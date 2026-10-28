/// Arrow-key and Tab movement through sections of items laid out in grids, as in the Add to
/// Ring picker and the Add App Ring sheet. Left/Right and Tab walk the items in reading order
/// across sections; Up/Down move a row, keeping the column where the next section allows.
struct GridNavigation {
    struct Section {
        var ids: [String]
        var columns: Int
    }

    enum Move {
        case left, right, up, down
    }

    var sections: [Section]

    var first: String? { sections.lazy.compactMap(\.ids.first).first }

    /// The item to highlight after `move` from `current` (the first item when there is none).
    func target(from current: String?, _ move: Move) -> String? {
        let order = sections.flatMap(\.ids)
        guard let current, let position = locate(current) else { return first }
        switch move {
        case .right, .left:
            guard let i = order.firstIndex(of: current) else { return first }
            let next = move == .right ? i + 1 : i - 1
            return order.indices.contains(next) ? order[next] : current
        case .down:
            return below(position) ?? current
        case .up:
            return above(position) ?? current
        }
    }

    private struct Position {
        var section: Int
        var index: Int
    }

    private func locate(_ id: String) -> Position? {
        for (s, section) in sections.enumerated() {
            if let i = section.ids.firstIndex(of: id) { return Position(section: s, index: i) }
        }
        return nil
    }

    private func below(_ p: Position) -> String? {
        let section = sections[p.section]
        let columns = max(section.columns, 1)
        let row = p.index / columns, lastRow = (section.ids.count - 1) / columns
        if p.index + columns < section.ids.count { return section.ids[p.index + columns] }
        if row < lastRow { return section.ids.last }
        guard let next = sections[(p.section + 1)...].firstIndex(where: { !$0.ids.isEmpty }) else { return nil }
        let column = p.index % columns
        return sections[next].ids[min(column, min(sections[next].columns, sections[next].ids.count) - 1)]
    }

    private func above(_ p: Position) -> String? {
        let section = sections[p.section]
        let columns = max(section.columns, 1)
        if p.index - columns >= 0 { return section.ids[p.index - columns] }
        guard let previous = sections[..<p.section].lastIndex(where: { !$0.ids.isEmpty }) else { return nil }
        let target = sections[previous]
        let targetColumns = max(target.columns, 1)
        let lastRowStart = (target.ids.count - 1) / targetColumns * targetColumns
        let column = min(p.index % columns, targetColumns - 1)
        return target.ids[min(lastRowStart + column, target.ids.count - 1)]
    }
}
