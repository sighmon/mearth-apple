import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var cards: [TemperatureCard] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var warning: String?

    private let composer = DashboardComposer()

    func refreshIfNeeded() async {
        guard cards.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        let snapshot = await composer.makeSnapshot(now: .now)
        cards = snapshot.cards
        warning = snapshot.warning
        lastUpdated = snapshot.generatedAt
    }
}
