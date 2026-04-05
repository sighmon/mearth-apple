import MapKit
import SwiftUI

struct LocationDetailSheet: View {
    let location: CardLocation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                header

                switch location.body {
                case .earth:
                    EarthLocationMap(location: location)
                case .mars, .moon:
                    PlanetaryLocationView(location: location)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Coordinates")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(formattedLatitude), \(formattedLongitude)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text(location.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle(location.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: closePlacement) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(location.subtitle)
                .font(.title3.weight(.semibold))

            Text(location.body.rawValue.capitalized)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var formattedLatitude: String {
        Self.formatCoordinate(location.latitude, positive: "N", negative: "S")
    }

    private var formattedLongitude: String {
        Self.formatCoordinate(location.longitude, positive: "E", negative: "W")
    }

    private static func formatCoordinate(_ value: Double, positive: String, negative: String) -> String {
        let direction = value >= 0 ? positive : negative
        return String(format: "%.4f° %@", abs(value), direction)
    }

    private var closePlacement: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .topBarTrailing
        #endif
    }
}

private struct EarthLocationMap: View {
    let location: CardLocation

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)
        )
    }

    var body: some View {
        Map(initialPosition: .region(region)) {
            Marker(location.title, coordinate: coordinate)
        }
        .mapStyle(.standard(elevation: .realistic))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(minHeight: 320)
    }
}

private struct PlanetaryLocationView: View {
    let location: CardLocation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                PlanetaryTileMosaic(location: location)

                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)

                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) / 2

                    for step in stride(from: 0.2, through: 0.8, by: 0.2) {
                        let latitudeRadius = radius * CGFloat(step)
                        context.stroke(
                            Path(ellipseIn: CGRect(
                                x: center.x - radius,
                                y: center.y - latitudeRadius,
                                width: radius * 2,
                                height: latitudeRadius * 2
                            )),
                            with: .color(.white.opacity(0.08)),
                            lineWidth: 1
                        )
                    }

                    for longitude in stride(from: -60.0, through: 60.0, by: 30.0) {
                        let arcOffset = radius * CGFloat(longitude / 90)
                        var path = Path()
                        path.move(to: CGPoint(x: center.x + arcOffset, y: center.y - radius))
                        path.addQuadCurve(
                            to: CGPoint(x: center.x + arcOffset, y: center.y + radius),
                            control: CGPoint(x: center.x - arcOffset * 0.35, y: center.y)
                        )
                        context.stroke(path, with: .color(.white.opacity(0.08)), lineWidth: 1)
                    }
                }

                marker
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, 12)
        }
    }

    private var marker: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2 * 0.82
            let x = proxy.size.width / 2 + CGFloat(location.longitude / 180) * radius
            let y = proxy.size.height / 2 - CGFloat(location.latitude / 90) * radius

            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)

                Circle()
                    .stroke(.black.opacity(0.4), lineWidth: 4)
                    .frame(width: 18, height: 18)
            }
            .position(x: x, y: y)
        }
    }
}

private struct PlanetaryTileMosaic: View {
    let location: CardLocation

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                HStack(spacing: 0) {
                    ForEach(tileURLs, id: \.absoluteString) { url in
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .interpolation(.high)
                            default:
                                Rectangle()
                                    .fill(fallbackGradient)
                            }
                        }
                        .frame(width: size, height: size)
                        .clipped()
                    }
                }
                .frame(width: size * 2, height: size, alignment: .leading)
                .offset(x: -size / 2)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.14),
                                .clear,
                                .black.opacity(0.20),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.softLight)
            }
            .overlay {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.22),
                                .clear,
                            ],
                            center: UnitPoint(x: 0.34, y: 0.28),
                            startRadius: 4,
                            endRadius: size * 0.32
                        )
                    )
                    .blendMode(.screen)
            }
            .overlay {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .clear,
                                .clear,
                                .black.opacity(0.30),
                                .black.opacity(0.52),
                            ],
                            center: .center,
                            startRadius: size * 0.22,
                            endRadius: size * 0.56
                        )
                    )
                    .blendMode(.multiply)
            }
            .overlay {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.18)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var tileURLs: [URL] {
        switch location.body {
        case .mars:
            return [
                URL(string: "https://trek.nasa.gov/tiles/Mars/EQ/msss_atlas_simp_clon/1.0.0/default/default028mm/0/0/0.png")!,
                URL(string: "https://trek.nasa.gov/tiles/Mars/EQ/msss_atlas_simp_clon/1.0.0/default/default028mm/0/0/1.png")!,
            ]
        case .moon:
            return [
                URL(string: "https://trek.nasa.gov/tiles/Moon/EQ/LRO_WAC_Mosaic_Global_303ppd_v02/1.0.0/default/default028mm/0/0/0.jpg")!,
                URL(string: "https://trek.nasa.gov/tiles/Moon/EQ/LRO_WAC_Mosaic_Global_303ppd_v02/1.0.0/default/default028mm/0/0/1.jpg")!,
            ]
        case .earth:
            return []
        }
    }

    private var fallbackGradient: LinearGradient {
        switch location.body {
        case .mars:
            return LinearGradient(colors: [.orange, .red, .brown], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .moon:
            return LinearGradient(colors: [.gray, Color(white: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .earth:
            return LinearGradient(colors: [.blue, .green], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
