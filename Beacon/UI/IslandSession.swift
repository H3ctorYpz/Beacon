import Combine
import CoreGraphics
import Foundation

@MainActor
final class IslandSession: ObservableObject {
    /// 0 = collapsed pill, 1 = expanded island. Drive only via spring animations.
    @Published var progress: CGFloat = 0
    /// Pill chrome on-screen. Independent from `progress` so hide/show never fights expand/collapse.
    @Published var isChromeVisible: Bool = true
}
