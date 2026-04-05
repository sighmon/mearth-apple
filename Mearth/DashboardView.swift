import Combine
import MapKit
import SwiftUI

struct DashboardView: View {
    @StateObject private var store = DashboardStore()
    @State private var selectedLocation: CardLocation?
    private let refreshTimer = Timer.publish(every: 900, on: .main, in: .common).autoconnect()

    @MainActor
    init(store: DashboardStore? = nil) {
        _store = StateObject(wrappedValue: store ?? DashboardStore())
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        VStack(alignment: .leading, spacing: 24) {
                            header
                            cardGrid
                        }
                        .frame(maxWidth: contentMaxWidth)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, 28)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
            }
        }
        .task {
            await store.refreshIfNeeded()
        }
        .onReceive(refreshTimer) { _ in
            Task {
                await store.refresh()
            }
        }
        .sheet(item: $selectedLocation) { location in
            LocationDetailSheet(location: location)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mearth")
                        .font(.system(size: titleSize, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Where on Earth is the temperature similar to Mars, the Moon, and home.")
                        .font(.system(.title3, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    Task {
                        await store.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: refreshIconSize, weight: .semibold))
                        .frame(width: refreshButtonSize, height: refreshButtonSize)
                }
                .buttonStyle(.plain)
                .background(
                    Circle()
                        .fill(.gray)
                )
                #if os(macOS)
                .focusable(false)
                #endif
            }

            statusStrip
        }
        .padding(cardInset)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.18),
                            Color(white: 0.08),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
    }

    private var statusStrip: some View {
        HStack(spacing: 12) {
            Label(store.isLoading ? "Refreshing feeds" : "Data downloaded", systemImage: store.isLoading ? "dot.radiowaves.left.and.right" : "checkmark.seal.fill")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            if let lastUpdated = store.lastUpdated {
                Text("\(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer(minLength: 12)
        }
    }

    private var cardGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let warning = store.warning {
                Text(warning)
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(.yellow)
            }

            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(store.cards) { card in
                    Button {
                        selectedLocation = card.location
                    } label: {
                        TemperatureCardView(card: card)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .disabled(card.location == nil)
                }
            }
            if store.cards.isEmpty {
                ProgressView("Collecting temperatures…")
                    .font(.system(.headline, weight: .medium))
                    .tint(.white)
                    .padding(cardInset)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(white: 0.16),
                .black,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var columns: [GridItem] {
        #if os(tvOS)
        [
            GridItem(.flexible(), spacing: 18, alignment: .top),
            GridItem(.flexible(), spacing: 18, alignment: .top),
        ]
        #else
        [GridItem(.adaptive(minimum: adaptiveMinimum, maximum: adaptiveMaximum), spacing: 18)]
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        54
        #elseif os(macOS)
        34
        #else
        30
        #endif
    }

    private var titleSize: CGFloat {
        #if os(tvOS)
        64
        #elseif os(macOS)
        52
        #else
        44
        #endif
    }

    private var adaptiveMinimum: CGFloat {
        #if os(tvOS)
        280
        #elseif os(macOS)
        210
        #else
        300
        #endif
    }

    private var adaptiveMaximum: CGFloat {
        #if os(tvOS)
        320
        #elseif os(macOS)
        320
        #else
        391
        #endif
    }

    private var contentMaxWidth: CGFloat? {
        #if os(tvOS)
        nil
        #elseif os(macOS)
        650
        #else
        800
        #endif
    }

    private var cardInset: CGFloat {
        #if os(tvOS)
        28
        #else
        22
        #endif
    }

    private var refreshButtonPadding: CGFloat {
        #if os(tvOS)
        18
        #else
        14
        #endif
    }

    private var refreshIconSize: CGFloat {
        #if os(tvOS)
        28
        #else
        22
        #endif
    }

    private var refreshButtonSize: CGFloat {
        refreshIconSize + (refreshButtonPadding * 2)
    }
}

private struct TemperatureCardView: View {
    let card: TemperatureCard

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.title.uppercased())
                        .font(.system(.caption, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.72))

                    Text(card.subtitle)
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Image(systemName: style.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Text(card.value)
                .font(.system(size: 48, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text(card.detail)
                    .font(.system(.headline, weight: .medium))
                    .foregroundStyle(.white.opacity(0.84))

                Text(card.footnote)
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: style.colors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
    }

    private var style: CardStyle {
        switch card.kind {
        case .mars:
            return CardStyle(colors: [.orange, .red], symbol: "antenna.radiowaves.left.and.right")
        case .earth:
            return CardStyle(colors: [.teal, .green], symbol: "building.2.crop.circle")
        case .moon:
            return CardStyle(colors: [.gray, .black], symbol: "moon.stars.fill")
        case .local:
            return CardStyle(colors: [.blue, .indigo], symbol: "location.north.circle.fill")
        }
    }

    private var cardPadding: CGFloat {
        #if os(tvOS)
        28
        #else
        22
        #endif
    }

}

private struct CardStyle {
    let colors: [Color]
    let symbol: String
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView(store: DashboardStore.preview)
            .frame(width: 1440, height: 980)
    }
}
