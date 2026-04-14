import Foundation
import SwiftUI
import SharedModels

// MARK: - Split Direction

public enum SplitDirection: String, Sendable, Codable {
    case horizontal
    case vertical
}

// MARK: - Panel Node

public indirect enum PanelNode: Identifiable, Sendable {
    case leaf(PanelLeaf)
    case split(PanelSplit)

    public var id: PanelID {
        switch self {
        case .leaf(let leaf): leaf.id
        case .split(let split): split.id
        }
    }
}

public struct PanelLeaf: Identifiable, Sendable {
    public let id: PanelID
    public var sessionID: SessionID

    public init(id: PanelID = UUID().uuidString, sessionID: SessionID) {
        self.id = id
        self.sessionID = sessionID
    }
}

public struct PanelSplit: Identifiable, Sendable {
    public let id: PanelID
    public var direction: SplitDirection
    public var ratio: CGFloat
    public var first: PanelNode
    public var second: PanelNode

    public init(
        id: PanelID = UUID().uuidString,
        direction: SplitDirection,
        ratio: CGFloat = 0.5,
        first: PanelNode,
        second: PanelNode
    ) {
        self.id = id
        self.direction = direction
        self.ratio = ratio
        self.first = first
        self.second = second
    }
}

// MARK: - Workspace State

@Observable
public final class WorkspaceState {
    public var root: PanelNode
    public var focusedPanelID: PanelID
    public var splitRatios: [PanelID: CGFloat] = [:]

    public init() {
        let sessionID = UUID().uuidString
        let leaf = PanelLeaf(sessionID: sessionID)
        self.root = .leaf(leaf)
        self.focusedPanelID = leaf.id
    }

    // MARK: - Panel Count

    public var panelCount: Int {
        countLeaves(in: root)
    }

    public var allSessionIDs: [SessionID] {
        allLeaves(in: root).map(\.sessionID)
    }

    // MARK: - Panel Operations

    public func splitPanel(_ panelID: PanelID, direction: SplitDirection) -> SessionID {
        let newSessionID = UUID().uuidString
        let newLeaf = PanelLeaf(sessionID: newSessionID)

        root = replacingNode(in: root, targetID: panelID) { node in
            let split = PanelSplit(
                direction: direction,
                first: node,
                second: .leaf(newLeaf)
            )
            splitRatios[split.id] = 0.5
            return .split(split)
        }

        focusedPanelID = newLeaf.id
        return newSessionID
    }

    public func closePanel(_ panelID: PanelID) {
        guard panelCount > 1 else { return }

        // Find sibling to receive focus
        let siblingID = findSibling(of: panelID, in: root)

        root = removingNode(in: root, targetID: panelID) ?? root

        if let siblingID {
            focusedPanelID = siblingID
        } else {
            // Fall back to first leaf
            focusedPanelID = allLeaves(in: root).first?.id ?? focusedPanelID
        }
    }

    public func updateSplitRatio(_ splitID: PanelID, ratio: CGFloat) {
        let clamped = max(0.1, min(0.9, ratio))
        splitRatios[splitID] = clamped
    }

    public func focusPanel(_ panelID: PanelID) {
        focusedPanelID = panelID
    }

    public func focusNext() {
        let leaves = allLeaves(in: root)
        guard let currentIndex = leaves.firstIndex(where: { $0.id == focusedPanelID }) else { return }
        let nextIndex = (currentIndex + 1) % leaves.count
        focusedPanelID = leaves[nextIndex].id
    }

    public func focusPrevious() {
        let leaves = allLeaves(in: root)
        guard let currentIndex = leaves.firstIndex(where: { $0.id == focusedPanelID }) else { return }
        let prevIndex = (currentIndex - 1 + leaves.count) % leaves.count
        focusedPanelID = leaves[prevIndex].id
    }

    /// Move focus in a spatial direction
    public func focusInDirection(_ direction: SplitDirection, forward: Bool = true) {
        guard let target = findAdjacentPanel(
            from: focusedPanelID,
            in: root,
            direction: direction,
            forward: forward
        ) else { return }
        focusedPanelID = target
    }

    // MARK: - Tree Helpers

    public func allLeaves(in node: PanelNode) -> [PanelLeaf] {
        switch node {
        case .leaf(let leaf):
            return [leaf]
        case .split(let split):
            return allLeaves(in: split.first) + allLeaves(in: split.second)
        }
    }

    private func countLeaves(in node: PanelNode) -> Int {
        switch node {
        case .leaf: return 1
        case .split(let split):
            return countLeaves(in: split.first) + countLeaves(in: split.second)
        }
    }

    private func replacingNode(
        in node: PanelNode,
        targetID: PanelID,
        replacement: (PanelNode) -> PanelNode
    ) -> PanelNode {
        if node.id == targetID {
            return replacement(node)
        }

        switch node {
        case .leaf:
            return node
        case .split(var split):
            split.first = replacingNode(in: split.first, targetID: targetID, replacement: replacement)
            split.second = replacingNode(in: split.second, targetID: targetID, replacement: replacement)
            return .split(split)
        }
    }

    private func removingNode(in node: PanelNode, targetID: PanelID) -> PanelNode? {
        switch node {
        case .leaf(let leaf):
            return leaf.id == targetID ? nil : node
        case .split(let split):
            if split.first.id == targetID {
                splitRatios.removeValue(forKey: split.id)
                return split.second
            }
            if split.second.id == targetID {
                splitRatios.removeValue(forKey: split.id)
                return split.first
            }
            if let newFirst = removingNode(in: split.first, targetID: targetID) {
                var newSplit = split
                newSplit.first = newFirst
                return .split(newSplit)
            }
            if let newSecond = removingNode(in: split.second, targetID: targetID) {
                var newSplit = split
                newSplit.second = newSecond
                return .split(newSplit)
            }
            return node
        }
    }

    private func findSibling(of panelID: PanelID, in node: PanelNode) -> PanelID? {
        switch node {
        case .leaf:
            return nil
        case .split(let split):
            if split.first.id == panelID {
                return allLeaves(in: split.second).first?.id
            }
            if split.second.id == panelID {
                return allLeaves(in: split.first).first?.id
            }
            if let found = findSibling(of: panelID, in: split.first) {
                return found
            }
            return findSibling(of: panelID, in: split.second)
        }
    }

    private func findAdjacentPanel(
        from panelID: PanelID,
        in node: PanelNode,
        direction: SplitDirection,
        forward: Bool
    ) -> PanelID? {
        // Walk the tree to find the panel, tracking the path
        let path = findPath(to: panelID, in: node)
        guard !path.isEmpty else { return nil }

        // Walk up the path to find a split in the desired direction
        for i in stride(from: path.count - 1, through: 0, by: -1) {
            let pathEntry = path[i]
            guard case .split(let split) = pathEntry.node,
                  split.direction == direction else { continue }

            // Determine if we can move in the desired direction
            let isInFirst = pathEntry.childIndex == 0
            let canMove = forward ? isInFirst : !isInFirst
            guard canMove else { continue }

            // Navigate into the other subtree
            let target = forward ? split.second : split.first
            // Get the nearest leaf in the entry direction
            let leaves = allLeaves(in: target)
            return (forward ? leaves.first : leaves.last)?.id
        }

        return nil
    }

    private struct PathEntry {
        let node: PanelNode
        let childIndex: Int // 0 = first, 1 = second
    }

    private func findPath(to targetID: PanelID, in node: PanelNode) -> [PathEntry] {
        if node.id == targetID {
            return []
        }

        switch node {
        case .leaf:
            return []
        case .split(let split):
            if let _ = findLeaf(targetID, in: split.first) {
                return [PathEntry(node: node, childIndex: 0)] +
                       findPath(to: targetID, in: split.first)
            }
            if let _ = findLeaf(targetID, in: split.second) {
                return [PathEntry(node: node, childIndex: 1)] +
                       findPath(to: targetID, in: split.second)
            }
            return []
        }
    }

    private func findLeaf(_ id: PanelID, in node: PanelNode) -> PanelLeaf? {
        switch node {
        case .leaf(let leaf):
            return leaf.id == id ? leaf : nil
        case .split(let split):
            return findLeaf(id, in: split.first) ?? findLeaf(id, in: split.second)
        }
    }
}

// MARK: - Window State (Tabs)

@Observable
public final class WindowState {
    public var tabs: [TabState]
    public var activeTabIndex: Int

    public init() {
        let tab = TabState()
        self.tabs = [tab]
        self.activeTabIndex = 0
    }

    public var activeTab: TabState {
        get { tabs[activeTabIndex] }
        set { tabs[activeTabIndex] = newValue }
    }

    public func addTab() -> TabState {
        let tab = TabState()
        tabs.append(tab)
        activeTabIndex = tabs.count - 1
        return tab
    }

    public func closeTab(at index: Int) {
        guard tabs.count > 1 else { return }
        tabs.remove(at: index)
        if activeTabIndex >= tabs.count {
            activeTabIndex = tabs.count - 1
        }
    }

    public func selectTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        activeTabIndex = index
    }
}

// MARK: - Tab State

public struct TabState: Identifiable, Sendable {
    public let id: String
    public var title: String
    public let workspaceID: String

    public init(
        id: String = UUID().uuidString,
        title: String = "Terminal",
        workspaceID: String = UUID().uuidString
    ) {
        self.id = id
        self.title = title
        self.workspaceID = workspaceID
    }
}
