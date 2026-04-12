import MapKit
import SwiftUI

struct LocationDetailSheet: View {
    let card: TemperatureCard

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var temperatureUnitStore: TemperatureUnitStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    switch location.body {
                    case .earth:
                        EarthLocationMap(location: location)
                    case .mars, .moon:
                        PlanetaryLocationView(location: location)
                    }

                    metricsSection
                    temperaturePreferencesSection
                    coordinatesSection
                    comparisonSection
                    contextSection
                    sourcesSection

                    Spacer(minLength: 0)
                }
                .padding(24)
            }
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

    private var location: CardLocation {
        card.location ?? CardLocation(
            title: card.title,
            subtitle: card.subtitle,
            body: .earth,
            latitude: 0,
            longitude: 0,
            note: ""
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(location.subtitle)
                .font(.title3.weight(.semibold))

            Text(location.body.rawValue.capitalized)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(displayValue)
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !card.supportingMetrics.isEmpty {
                Text("Current Exposure")
                    .font(.headline)
                    .foregroundStyle(.primary)

                ForEach(card.supportingMetrics) { metric in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(metric.label)
                            .font(.system(.caption, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)

                        Text(metric.value)
                            .font(.system(.body, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private var coordinatesSection: some View {
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
    }

    @ViewBuilder
    private var temperaturePreferencesSection: some View {
        if card.kind == .local {
            VStack(alignment: .leading, spacing: 14) {
                Text("Temperature Units")
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Text("°C")
                            .font(.system(.body, weight: manualUnitIsFahrenheit ? .regular : .semibold))
                            .foregroundStyle(isAutomaticTemperatureUnit ? .secondary : .primary)

                        Toggle("", isOn: manualUnitBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)

                        Text("°F")
                            .font(.system(.body, weight: manualUnitIsFahrenheit ? .semibold : .regular))
                            .foregroundStyle(isAutomaticTemperatureUnit ? .secondary : .primary)
                    }

                    Spacer(minLength: 16)

                    Button {
                        if isAutomaticTemperatureUnit {
                            temperatureUnitStore.setPreference(currentManualPreference)
                        } else {
                            temperatureUnitStore.setPreference(.automatic)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isAutomaticTemperatureUnit ? "checkmark.square.fill" : "square")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Auto")
                                .font(.system(.body, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                }

                Text("\(autoUnitDescription). Auto uses your detected local region first, then falls back to the device locale.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context")
                .font(.headline)
                .foregroundStyle(.primary)

            if let sourceNote = card.sourceNote, !sourceNote.isEmpty {
                Text(sourceNote)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(contextLines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var comparisonSection: some View {
        if card.kind == .earth, !card.earthComparisonCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sampled Earth Cities")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("This is the full Open-Meteo city sample used for the Earth match, sorted by temperature difference from Mars.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(card.earthComparisonCandidates) { candidate in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(candidate.city), \(candidate.country)")
                                .font(.subheadline.weight(candidate.isSelectedMatch ? .semibold : .regular))
                                .foregroundStyle(.primary)

                            Text("\(formattedTemperature(candidate.temperature, fractionDigits: 1)) · \(formattedTemperatureDelta(candidate.temperatureDeltaFromReference, fractionDigits: 1)) from Mars")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formattedTemperature(candidate.temperature, fractionDigits: 1))
                                .font(.system(.body, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)

                            Text("UV \(Self.uvIndexString(candidate.uvIndex))")
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sources")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(sourceLinks) { source in
                VStack(alignment: .leading, spacing: 4) {
                    Link(source.title, destination: source.url)
                        .font(.subheadline.weight(.semibold))

                    Text(source.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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

    private var contextLines: [String] {
        switch card.kind {
        case .mars:
            return [
                "Temperature is estimated from Curiosity REMS daily range and current local mean solar time at Gale Crater.",
                "UV is shown as a local-time UV Index-equivalent derived from the REMS UV category in the official CAB feed.",
                "Radiation is shown separately in µSv/h as a Mars surface ionizing-radiation baseline anchored to Curiosity RAD context from NASA/JPL."
            ]
        case .moon:
            return [
                "Temperature is modeled from local solar angle at Tranquility Base rather than a live lunar sensor feed.",
                "UV is a local-time UV Index-equivalent estimate for direct sunlight with no meaningful atmosphere.",
                "Radiation is shown separately in µSv/h as an Apollo-era lunar surface baseline for ionizing radiation, not a live local reading."
            ]
        case .earth:
            return [
                "Temperature and UV come from the live Earth weather lookup used for this comparison city.",
                "Radiation is shown separately in µSv/h as a simple Earth surface background reference so off-world values have a baseline.",
                "UV Index is directly comparable across Earth, Mars estimate, and Moon estimate; ionizing radiation is not on the same scale and is shown in dose-rate units."
            ]
        case .local:
            return [
                "Temperature and UV come from your live local weather lookup when available, with fallback weather sources if needed.",
                "Radiation is shown separately in µSv/h as a simple Earth surface background reference.",
                "UV Index is directly comparable across Earth, Mars estimate, and Moon estimate; ionizing radiation is shown in dose-rate units."
            ]
        }
    }

    private var sourceLinks: [SourceLink] {
        switch card.kind {
        case .mars:
            return [
                SourceLink(
                    title: "CAB Curiosity REMS Feed",
                    url: URL(string: "http://cab.inta-csic.es/rems/wp-content/plugins/marsweather-widget/api.php")!,
                    note: "Official outreach feed for Curiosity weather, including the REMS UV category used here."
                ),
                SourceLink(
                    title: "NASA/JPL Curiosity RAD Context",
                    url: URL(string: "https://www.jpl.nasa.gov/images/pia16020-curiositys-first-radiation-measurements-on-mars/")!,
                    note: "Background reference for Mars surface ionizing radiation measured by Curiosity's Radiation Assessment Detector."
                )
            ]
        case .moon:
            return [
                SourceLink(
                    title: "NASA Apollo Lunar Radiation Review",
                    url: URL(string: "https://www.nasa.gov/wp-content/uploads/static/history/alsj/WOTM/WOTM-Radiation.html")!,
                    note: "Apollo-era lunar orbit and surface dose-rate context used as the baseline for lunar ionizing radiation."
                ),
                SourceLink(
                    title: "NASA Earth UV Index Context",
                    url: URL(string: "https://neo.gsfc.nasa.gov/view.php?datasetId=AURA_UVI_CLIM_M")!,
                    note: "Reference for the UV Index scale that the lunar UV-equivalent estimate is mapped against."
                )
            ]
        case .earth:
            return [
                SourceLink(
                    title: "Open-Meteo Forecast API",
                    url: URL(string: "https://open-meteo.com/en/docs")!,
                    note: "Source of the current temperature and UV Index used for the sampled Earth city comparison set."
                ),
                SourceLink(
                    title: "US EPA Radiation Sources and Doses",
                    url: URL(string: "https://19january2017snapshot.epa.gov/radiation/radiation-sources-and-doses")!,
                    note: "Background reference for typical Earth surface ionizing-radiation exposure levels."
                )
            ]
        case .local:
            return [
                SourceLink(
                    title: " Weather",
                    url: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
                    note: "Primary source for the local card's current weather and UV Index when  Weather is available."
                ),
                SourceLink(
                    title: "Open-Meteo Forecast API",
                    url: URL(string: "https://open-meteo.com/en/docs")!,
                    note: "Fallback source for current local temperature and UV Index when  Weather data is unavailable."
                ),
                SourceLink(
                    title: "US EPA Radiation Sources and Doses",
                    url: URL(string: "https://19january2017snapshot.epa.gov/radiation/radiation-sources-and-doses")!,
                    note: "Background reference for typical Earth surface ionizing-radiation exposure levels."
                )
            ]
        }
    }

    private var displayValue: String {
        if let temperatureCelsius = card.temperatureCelsius {
            return temperatureUnitStore.formattedTemperature(celsius: temperatureCelsius)
        }
        return card.value
    }

    private func formattedTemperature(_ value: Double, fractionDigits: Int) -> String {
        temperatureUnitStore.formattedTemperature(celsius: value, fractionDigits: fractionDigits)
    }

    private func formattedTemperatureDelta(_ value: Double, fractionDigits: Int) -> String {
        temperatureUnitStore.formattedTemperatureDelta(celsius: value, fractionDigits: fractionDigits)
    }

    private static func uvIndexString(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return String(format: "%.1f", value)
    }

    private var isAutomaticTemperatureUnit: Bool {
        temperatureUnitStore.preference == .automatic
    }

    private var manualUnitIsFahrenheit: Bool {
        switch temperatureUnitStore.preference {
        case .fahrenheit:
            return true
        case .celsius:
            return false
        case .automatic:
            return temperatureUnitStore.resolvedUnit == .fahrenheit
        }
    }

    private var currentManualPreference: TemperatureUnitPreference {
        manualUnitIsFahrenheit ? .fahrenheit : .celsius
    }

    private var autoUnitDescription: String {
        "Currently \(temperatureUnitStore.resolvedUnit.symbol)"
    }

    private var manualUnitBinding: Binding<Bool> {
        Binding(
            get: { manualUnitIsFahrenheit },
            set: { isFahrenheit in
                temperatureUnitStore.setPreference(isFahrenheit ? .fahrenheit : .celsius)
            }
        )
    }
}

private struct SourceLink: Identifiable {
    let title: String
    let url: URL
    let note: String

    var id: String { title }
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
