import Combine
import SwiftUI

struct DashboardView: View {
    @StateObject private var store = DashboardStore()
    private let refreshTimer = Timer.publish(every: 900, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    statusStrip
                    cardGrid
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 28)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("THERMAL TRIANGULATION")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.62))

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mearth")
                        .font(.system(size: titleSize, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Curiosity on Mars, the nearest Earth analog, a modeled Apollo site on the Moon, and your local temperature in one dashboard.")
                        .font(.system(.title3, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    Task {
                        await store.refresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.93, green: 0.48, blue: 0.25))
            }
        }
        .padding(cardInset)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.23, green: 0.09, blue: 0.08),
                            Color(red: 0.09, green: 0.13, blue: 0.22),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 180, height: 180)
                        .blur(radius: 10)
                        .offset(x: 34, y: -34)
                }
        )
    }

    private var statusStrip: some View {
        HStack(spacing: 12) {
            Label(store.isLoading ? "Refreshing feeds" : "Snapshot ready", systemImage: store.isLoading ? "dot.radiowaves.left.and.right" : "checkmark.seal.fill")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            if let lastUpdated = store.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.09))
        )
    }

    private var cardGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let warning = store.warning {
                Text(warning)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.62))
            }

            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(store.cards) { card in
                    TemperatureCardView(card: card)
                }
            }

            if store.cards.isEmpty {
                ProgressView("Collecting temperatures…")
                    .font(.system(.headline, design: .rounded, weight: .medium))
                    .tint(.white)
                    .padding(cardInset)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
        }
    }

    private var background: some View {
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.08)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.16, blue: 0.28),
                    Color(red: 0.16, green: 0.07, blue: 0.06),
                    Color(red: 0.03, green: 0.04, blue: 0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.96, green: 0.45, blue: 0.24).opacity(0.20))
                .frame(width: 360, height: 360)
                .blur(radius: 48)
                .offset(x: 180, y: -220)

            Circle()
                .fill(Color(red: 0.23, green: 0.61, blue: 0.95).opacity(0.18))
                .frame(width: 300, height: 300)
                .blur(radius: 56)
                .offset(x: -170, y: 260)
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: adaptiveMinimum, maximum: 420), spacing: 18)]
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        54
        #elseif os(macOS)
        34
        #else
        20
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
        360
        #elseif os(macOS)
        290
        #else
        260
        #endif
    }

    private var cardInset: CGFloat {
        #if os(tvOS)
        28
        #else
        22
        #endif
    }
}

private struct TemperatureCardView: View {
    let card: TemperatureCard

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.title.uppercased())
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.72))

                    Text(card.subtitle)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Image(systemName: style.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Text(card.value)
                .font(.system(size: 48, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text(card.detail)
                    .font(.system(.headline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.84))

                Text(card.footnote)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: style.colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 120, height: 120)
                        .blur(radius: 8)
                        .offset(x: 22, y: -18)
                }
        )
    }

    private var style: CardStyle {
        switch card.kind {
        case .mars:
            return CardStyle(colors: [Color(red: 0.54, green: 0.20, blue: 0.12), Color(red: 0.24, green: 0.09, blue: 0.08)], symbol: "antenna.radiowaves.left.and.right")
        case .earth:
            return CardStyle(colors: [Color(red: 0.12, green: 0.28, blue: 0.22), Color(red: 0.07, green: 0.13, blue: 0.14)], symbol: "building.2.crop.circle")
        case .moon:
            return CardStyle(colors: [Color(red: 0.28, green: 0.28, blue: 0.35), Color(red: 0.10, green: 0.11, blue: 0.17)], symbol: "moon.stars.fill")
        case .local:
            return CardStyle(colors: [Color(red: 0.10, green: 0.31, blue: 0.48), Color(red: 0.08, green: 0.13, blue: 0.20)], symbol: "location.north.circle.fill")
        }
    }

    private var cardPadding: CGFloat {
        #if os(tvOS)
        28
        #else
        22
        #endif
    }

    private var minHeight: CGFloat {
        #if os(tvOS)
        300
        #else
        256
        #endif
    }
}

private struct CardStyle {
    let colors: [Color]
    let symbol: String
}
