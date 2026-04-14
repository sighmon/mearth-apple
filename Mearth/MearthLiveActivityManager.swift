#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

@MainActor
enum MearthLiveActivityManager {
    private static let attributes = MearthLiveActivityAttributes(name: "Mearth")

    static func update(snapshot: SharedDashboardSnapshot) async {
        guard #available(iOS 16.2, *) else {
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        let content = ActivityContent(
            state: MearthLiveActivityAttributes.ContentState(snapshot: snapshot),
            staleDate: snapshot.generatedAt.addingTimeInterval(60 * 30)
        )

        if let activity = Activity<MearthLiveActivityAttributes>.activities.first {
            await activity.update(content)
            return
        }

        do {
            _ = try Activity<MearthLiveActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            // Ignore Live Activity failures; widgets continue to work from the shared snapshot.
        }
    }
}
#endif
