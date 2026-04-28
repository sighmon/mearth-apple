import MapKit
import SceneKit
import SwiftUI
import ImageIO
import CryptoKit

struct LocationDetailSheet: View {
    let card: TemperatureCard

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var temperatureUnitStore: TemperatureUnitStore
    @State private var selectedPlanetarySiteID: String?
    @State private var sunlightEnabled = true

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header

                        switch detailLocation.body {
                        case .earth:
                            EarthLocationMap(
                                location: detailLocation,
                                selectedTemperatureCelsius: card.temperatureCelsius,
                                comparisonCandidates: card.earthComparisonCandidates
                            )
                        case .mars, .moon:
                            PlanetaryLocationView(
                                location: baseLocation,
                                sites: planetarySites,
                                sunlightEnabled: sunlightEnabled,
                                maxHeight: max(proxy.size.height * 0.5, 320)
                            ) { siteID in
                                selectedPlanetarySiteID = siteID
                            }
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
            }
            .navigationTitle(detailLocation.title)
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
        #if os(macOS)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 720, idealHeight: 820)
        #endif
    }

    private var baseLocation: CardLocation {
        card.location ?? CardLocation(
            title: card.title,
            subtitle: card.subtitle,
            body: .earth,
            latitude: 0,
            longitude: 0,
            note: ""
        )
    }

    private var selectedPlanetarySite: PlanetarySite? {
        guard let selectedPlanetarySiteID else {
            return nil
        }
        return planetarySites.first(where: { $0.id == selectedPlanetarySiteID })
    }

    private var displayedPlanetarySite: PlanetarySite? {
        selectedPlanetarySite ?? planetarySites.first(where: { $0.matches(location: detailLocation) })
    }

    private var detailLocation: CardLocation {
        selectedPlanetarySite?.location ?? baseLocation
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerSubtitle)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.78)

            Text(detailLocation.body.rawValue.capitalized)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(displayValue)
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private var headerSubtitle: String {
        guard let displayedPlanetarySite, detailLocation.body != .earth else {
            return detailLocation.subtitle
        }
        return "\(detailLocation.subtitle) · \(displayedPlanetarySite.metadataLine)"
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !displayedSupportingMetrics.isEmpty {
                HStack(alignment: .center, spacing: 12) {
                    Text("Current Exposure")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 12)

                    if detailLocation.body == .mars || detailLocation.body == .moon {
                        HStack(spacing: 8) {
                            Text("Sunlight")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)

                            Toggle("", isOn: $sunlightEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                }

                ForEach(displayedSupportingMetrics) { metric in
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

            Text(detailLocation.note)
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

            if let sourceNote = detailSourceNote, !sourceNote.isEmpty {
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
        Self.formatCoordinate(detailLocation.latitude, positive: "N", negative: "S")
    }

    private var formattedLongitude: String {
        Self.formatCoordinate(detailLocation.longitude, positive: "E", negative: "W")
    }

    private var planetarySites: [PlanetarySite] {
        PlanetarySiteCatalog.sites(for: baseLocation.body, selectedLocation: baseLocation)
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
            ].compactMap { $0 }
        case .moon:
            return [
                "Temperature is modeled from local solar angle at Tranquility Base rather than a live lunar sensor feed.",
                "UV is a local-time UV Index-equivalent estimate for direct sunlight with no meaningful atmosphere.",
                "Radiation is shown separately in µSv/h as an Apollo-era lunar surface baseline for ionizing radiation, not a live local reading."
            ].compactMap { $0 }
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

    private var detailSourceNote: String? {
        if let displayedPlanetarySite, detailLocation.body != .earth {
            if selectedPlanetarySite != nil, let localHour = estimatedPlanetaryConditions?.localHour {
                return "\(displayedPlanetarySite.mission) · \(displayedPlanetarySite.metadataLine) · local time \(Self.hourMinuteString(localHour))"
            }
            return "\(displayedPlanetarySite.mission) · \(displayedPlanetarySite.metadataLine)"
        }
        return card.sourceNote
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
                ),
                SourceLink(
                    title: "NASA GISS Mars24 Sunclock",
                    url: URL(string: "https://www.giss.nasa.gov/tools/mars24/index.html")!,
                    note: "Reference for Mars solar time and the day-night geometry used to place the Mars sunlight terminator."
                ),
                SourceLink(
                    title: "NASA GISS Mars24 Technical Notes",
                    url: URL(string: "https://www.giss.nasa.gov/tools/mars24/help/notes.html")!,
                    note: "Technical notes on coordinated Mars time and local mean solar time, which the globe sunlight model is based on."
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
                ),
                SourceLink(
                    title: "NASA Moon Phase and Libration",
                    url: URL(string: "https://science.nasa.gov/resource/moon-phase-and-libration-2026/")!,
                    note: "Reference for the Moon's subsolar point, phase, and illuminated hemisphere used to place the lunar sunlight terminator."
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
        if let temperatureCelsius = displayedTemperatureCelsius {
            return temperatureUnitStore.formattedTemperature(celsius: temperatureCelsius)
        }
        return card.value
    }

    private var displayedTemperatureCelsius: Double? {
        estimatedPlanetaryConditions?.temperatureCelsius ?? card.temperatureCelsius
    }

    private var displayedSupportingMetrics: [CardSupportingMetric] {
        guard let conditions = estimatedPlanetaryConditions else {
            return card.supportingMetrics
        }

        return [
            CardSupportingMetric(label: "UV INDEX", value: Self.uvIndexString(conditions.uvIndex)),
            CardSupportingMetric(label: "RADIATION", value: Self.radiationString(conditions.radiationDoseRate)),
        ]
    }

    private var estimatedPlanetaryConditions: EstimatedPlanetaryConditions? {
        guard selectedPlanetarySite != nil else {
            return nil
        }

        switch detailLocation.body {
        case .mars:
            guard let referenceTemperature = card.temperatureCelsius else {
                return nil
            }
            return PlanetaryTemperatureEstimator.estimateMars(
                at: card.lastUpdated,
                location: detailLocation,
                referenceLocation: baseLocation,
                referenceTemperatureCelsius: referenceTemperature
            )
        case .moon:
            return PlanetaryTemperatureEstimator.estimateMoon(
                at: card.lastUpdated,
                location: detailLocation
            )
        case .earth:
            return nil
        }
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

    private static func radiationString(_ value: Double) -> String {
        "\(String(format: "%.2f", value)) µSv/h"
    }

    private static func hourMinuteString(_ hourValue: Double) -> String {
        let normalized = PlanetaryTemperatureEstimator.positiveModulo(hourValue, 24)
        let totalMinutes = Int((normalized * 60).rounded())
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
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

private struct EstimatedPlanetaryConditions {
    let temperatureCelsius: Double
    let uvIndex: Double?
    let radiationDoseRate: Double
    let localHour: Double
}

private enum PlanetaryTemperatureEstimator {
    private static let marsRadiationDoseRate = 27.8
    private static let moonRadiationDoseRate = 32.0
    private static let moonMinimumTemperature = -173.0
    private static let moonMaximumTemperature = 127.0
    private static let moonPeakTemperatureHour = 14.0

    static func estimateMars(
        at date: Date,
        location: CardLocation,
        referenceLocation: CardLocation,
        referenceTemperatureCelsius: Double
    ) -> EstimatedPlanetaryConditions {
        let localHour = solarLocalHour(
            longitude: location.longitude,
            subsolarLongitude: PlanetaryIllumination.marsSubsolarLongitude(at: date)
        )
        let referenceLocalHour = solarLocalHour(
            longitude: referenceLocation.longitude,
            subsolarLongitude: PlanetaryIllumination.marsSubsolarLongitude(at: date)
        )
        let diurnalDelta = marsDiurnalOffset(localHour) - marsDiurnalOffset(referenceLocalHour)
        let latitudeDelta = marsLatitudeOffset(latitude: location.latitude) - marsLatitudeOffset(latitude: referenceLocation.latitude)
        let temperature = min(25, max(-125, referenceTemperatureCelsius + diurnalDelta + latitudeDelta))

        return EstimatedPlanetaryConditions(
            temperatureCelsius: temperature,
            uvIndex: daylightUVIndex(peakIndex: 6.5, localHour: localHour, sunrise: 6, sunset: 18, exponent: 0.92),
            radiationDoseRate: marsRadiationDoseRate,
            localHour: localHour
        )
    }

    static func estimateMoon(at date: Date, location: CardLocation) -> EstimatedPlanetaryConditions {
        let localHour = solarLocalHour(
            longitude: location.longitude,
            subsolarLongitude: PlanetaryIllumination.moonSubsolarLongitude(at: date)
        )
        let temperature = moonSurfaceTemperature(localHour: localHour, latitude: location.latitude)

        return EstimatedPlanetaryConditions(
            temperatureCelsius: temperature,
            uvIndex: daylightUVIndex(peakIndex: 12.0, localHour: localHour, sunrise: 6, sunset: 18, exponent: 0.9),
            radiationDoseRate: moonRadiationDoseRate,
            localHour: localHour
        )
    }

    static func positiveModulo(_ value: Double, _ modulus: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder >= 0 ? remainder : remainder + modulus
    }

    private static func solarLocalHour(longitude: Double, subsolarLongitude: Double) -> Double {
        positiveModulo(12 + signedModulo(longitude - subsolarLongitude, 360) / 15, 24)
    }

    private static func marsDiurnalOffset(_ localHour: Double) -> Double {
        let shiftedHour = positiveModulo(localHour - 14, 24)
        let cyclePosition = shiftedHour / 24
        let thermalWave = cos(cyclePosition * 2 * .pi)
        return 26 * (thermalWave >= 0 ? pow(thermalWave, 0.82) : -pow(abs(thermalWave), 1.25))
    }

    private static func marsLatitudeOffset(latitude: Double) -> Double {
        -0.32 * abs(latitude)
    }

    private static func moonSurfaceTemperature(localHour: Double, latitude: Double) -> Double {
        let latitudeScale = max(0.08, cos(abs(latitude) * .pi / 180))
        let effectiveMaximum = moonMinimumTemperature + (moonMaximumTemperature - moonMinimumTemperature) * latitudeScale
        let midpoint = (effectiveMaximum + moonMinimumTemperature) / 2
        let amplitude = (effectiveMaximum - moonMinimumTemperature) / 2
        let shiftedHour = positiveModulo(localHour - moonPeakTemperatureHour, 24)
        let cyclePosition = shiftedHour / 24
        let thermalWave = cos(cyclePosition * 2 * .pi)
        let smoothedWave = thermalWave >= 0
            ? pow(thermalWave, 0.82)
            : -pow(abs(thermalWave), 0.92)

        return midpoint + amplitude * smoothedWave
    }

    private static func daylightUVIndex(
        peakIndex: Double?,
        localHour: Double,
        sunrise: Double,
        sunset: Double,
        exponent: Double
    ) -> Double? {
        guard let peakIndex else {
            return nil
        }

        let normalizedTime = positiveModulo(localHour, 24)
        guard normalizedTime >= sunrise && normalizedTime <= sunset else {
            return 0
        }

        let daylightLength = max(0.1, sunset - sunrise)
        let progress = (normalizedTime - sunrise) / daylightLength
        return peakIndex * pow(max(0, sin(.pi * progress)), exponent)
    }

    private static func signedModulo(_ value: Double, _ modulus: Double) -> Double {
        let normalized = positiveModulo(value, modulus)
        return normalized > modulus / 2 ? normalized - modulus : normalized
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
    let selectedTemperatureCelsius: Double?
    let comparisonCandidates: [EarthComparisonCandidate]

    @EnvironmentObject private var temperatureUnitStore: TemperatureUnitStore

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }

    private var annotations: [EarthTemperatureMapAnnotation] {
        let candidateAnnotations = comparisonCandidates.compactMap { candidate -> EarthTemperatureMapAnnotation? in
            guard let latitude = candidate.latitude, let longitude = candidate.longitude else {
                return nil
            }

            return EarthTemperatureMapAnnotation(
                title: candidate.city,
                subtitle: candidate.country,
                temperature: candidate.temperature,
                isSelectedMatch: candidate.isSelectedMatch,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            )
        }

        guard !candidateAnnotations.isEmpty else {
            return [
                EarthTemperatureMapAnnotation(
                    title: location.title,
                    subtitle: location.subtitle,
                    temperature: selectedTemperatureCelsius,
                    isSelectedMatch: true,
                    coordinate: coordinate
                )
            ]
        }

        return candidateAnnotations
    }

    private var selectedCoordinate: CLLocationCoordinate2D {
        if let selectedCandidate = comparisonCandidates.first(where: { $0.isSelectedMatch }),
           let latitude = selectedCandidate.latitude,
           let longitude = selectedCandidate.longitude {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        return coordinate
    }

    private var region: MKCoordinateRegion {
        if comparisonCandidates.contains(where: { $0.latitude != nil && $0.longitude != nil }) {
            return MKCoordinateRegion(
                center: selectedCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)
            )
        }

        return MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)
        )
    }

    var body: some View {
        Map(initialPosition: .region(region)) {
            ForEach(annotations) { annotation in
                Annotation(annotation.title, coordinate: annotation.coordinate, anchor: .bottom) {
                    EarthTemperatureMapMarker(
                        temperature: annotation.temperature.map {
                            temperatureUnitStore.formattedTemperature(celsius: $0, fractionDigits: 0)
                        },
                        isSelectedMatch: annotation.isSelectedMatch
                    )
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(minHeight: 320)
    }
}

private struct EarthTemperatureMapAnnotation: Identifiable {
    let title: String
    let subtitle: String
    let temperature: Double?
    let isSelectedMatch: Bool
    let coordinate: CLLocationCoordinate2D

    var id: String {
        "\(title)-\(subtitle)-\(coordinate.latitude)-\(coordinate.longitude)"
    }
}

private struct EarthTemperatureMapMarker: View {
    let temperature: String?
    let isSelectedMatch: Bool

    var body: some View {
        VStack(spacing: 4) {
            if let temperature {
                Text(temperature)
                    .font(.system(.caption, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isSelectedMatch ? .black : .white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSelectedMatch ? Color.yellow : Color.black.opacity(0.74))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(isSelectedMatch ? 0.8 : 0.34), lineWidth: 1)
                    )
            }

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: isSelectedMatch ? 18 : 14, weight: .semibold))
                .foregroundStyle(isSelectedMatch ? .yellow : .red, .white)
        }
        .shadow(color: .black.opacity(0.26), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }
}

private struct PlanetaryLocationView: View {
    let location: CardLocation
    let sites: [PlanetarySite]
    let sunlightEnabled: Bool
    let maxHeight: CGFloat
    let onSiteSelected: (String) -> Void

    @State private var selectedSiteID: String?
    @State private var focusedSiteID: String?

    private var defaultSiteID: String {
        sites.first(where: { $0.matches(location: location) })?.id ?? sites.first?.id ?? PlanetarySite.currentLocation(from: location).id
    }

    private var resolvedSelectedSiteID: String {
        selectedSiteID ?? defaultSiteID
    }

    private var resolvedFocusedSiteID: String {
        focusedSiteID ?? defaultSiteID
    }

    private var focusedSite: PlanetarySite {
        sites.first(where: { $0.id == resolvedFocusedSiteID }) ??
        sites.first(where: { $0.matches(location: location) }) ??
        .currentLocation(from: location)
    }

    var body: some View {
        content
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            PlanetaryGlobeView(
                celestialBody: location.body,
                focusedLocation: focusedSite.location,
                sites: sites,
                sunlightEnabled: sunlightEnabled,
                selectedSiteID: resolvedSelectedSiteID,
                onSiteSelected: { siteID in
                    selectedSiteID = siteID
                    onSiteSelected(siteID)
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: maxHeight)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PlanetaryGlobeView: View {
    let celestialBody: CelestialBody
    let focusedLocation: CardLocation
    let sites: [PlanetarySite]
    let sunlightEnabled: Bool
    let selectedSiteID: String
    let onSiteSelected: (String) -> Void

    var body: some View {
        PlanetarySceneContainer(
            celestialBody: celestialBody,
            focusedLocation: focusedLocation,
            sites: sites,
            sunlightEnabled: sunlightEnabled,
            selectedSiteID: selectedSiteID,
            onSiteSelected: onSiteSelected
        )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
    }
}

#if os(macOS)
private struct PlanetarySceneContainer: NSViewRepresentable {
    let celestialBody: CelestialBody
    let focusedLocation: CardLocation
    let sites: [PlanetarySite]
    let sunlightEnabled: Bool
    let selectedSiteID: String
    let onSiteSelected: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SCNView {
        context.coordinator.makeView(
            celestialBody: celestialBody,
            focusedLocation: focusedLocation,
            sites: sites,
            sunlightEnabled: sunlightEnabled,
            selectedSiteID: selectedSiteID,
            onSiteSelected: onSiteSelected
        )
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.update(
            view: nsView,
            celestialBody: celestialBody,
            focusedLocation: focusedLocation,
            sites: sites,
            sunlightEnabled: sunlightEnabled,
            selectedSiteID: selectedSiteID,
            onSiteSelected: onSiteSelected
        )
    }
}
#else
private struct PlanetarySceneContainer: UIViewRepresentable {
    let celestialBody: CelestialBody
    let focusedLocation: CardLocation
    let sites: [PlanetarySite]
    let sunlightEnabled: Bool
    let selectedSiteID: String
    let onSiteSelected: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        context.coordinator.makeView(
            celestialBody: celestialBody,
            focusedLocation: focusedLocation,
            sites: sites,
            sunlightEnabled: sunlightEnabled,
            selectedSiteID: selectedSiteID,
            onSiteSelected: onSiteSelected
        )
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.update(
            view: uiView,
            celestialBody: celestialBody,
            focusedLocation: focusedLocation,
            sites: sites,
            sunlightEnabled: sunlightEnabled,
            selectedSiteID: selectedSiteID,
            onSiteSelected: onSiteSelected
        )
    }
}
#endif

private extension PlanetarySceneContainer {
    final class Coordinator: NSObject {
        private let scene = SCNScene()
        private let globeNode = SCNNode()
        private let siteNodes = SCNNode()
        private let textureMaterial = SCNMaterial()
        private let cameraNode = SCNNode()
        private let ambientNode = SCNNode()
        private let keyNode = SCNNode()
        private let fillNode = SCNNode()
        private let sunLightNode = SCNNode()
        private let globeRadius: CGFloat = 1.0
        private let minimumSurfaceClearance: CGFloat = 0.08
        private var focusedLocationID: String?
        private var loadedBody: CelestialBody?
        private var currentBody: CelestialBody = .moon
        private var textureTask: Task<Void, Never>?
        private var inertiaTask: Task<Void, Never>?
        private var onSiteSelected: ((String) -> Void)?
        private weak var sceneView: SCNView?

        private var lastPanPoint: CGPoint?
        private var lastMagnificationValue: CGFloat?
        #if os(macOS)
        private weak var panView: SCNView?
        #endif

        func makeView(
            celestialBody: CelestialBody,
            focusedLocation: CardLocation,
            sites: [PlanetarySite],
            sunlightEnabled: Bool,
            selectedSiteID: String,
            onSiteSelected: @escaping (String) -> Void
        ) -> SCNView {
            let view = SCNView()
            configure(
                sceneView: view,
                celestialBody: celestialBody,
                focusedLocation: focusedLocation,
                sites: sites,
                sunlightEnabled: sunlightEnabled,
                selectedSiteID: selectedSiteID,
                onSiteSelected: onSiteSelected
            )
            return view
        }

        func update(
            view: SCNView,
            celestialBody: CelestialBody,
            focusedLocation: CardLocation,
            sites: [PlanetarySite],
            sunlightEnabled: Bool,
            selectedSiteID: String,
            onSiteSelected: @escaping (String) -> Void
        ) {
            self.onSiteSelected = onSiteSelected
            currentBody = celestialBody

            if view.scene == nil {
                configure(
                    sceneView: view,
                    celestialBody: celestialBody,
                    focusedLocation: focusedLocation,
                    sites: sites,
                    sunlightEnabled: sunlightEnabled,
                    selectedSiteID: selectedSiteID,
                    onSiteSelected: onSiteSelected
                )
            }

            if focusedLocationID != focusedLocation.id {
                focus(on: focusedLocation)
                focusedLocationID = focusedLocation.id
            }

            updateLighting(for: celestialBody, at: Date(), sunlightEnabled: sunlightEnabled)
            updateSites(sites, selectedSiteID: selectedSiteID)

            if loadedBody != celestialBody {
                loadedBody = celestialBody
                applyFallbackAppearance(for: celestialBody)
                loadTexture(for: celestialBody)
            }
        }

        private func configure(
            sceneView: SCNView,
            celestialBody: CelestialBody,
            focusedLocation: CardLocation,
            sites: [PlanetarySite],
            sunlightEnabled: Bool,
            selectedSiteID: String,
            onSiteSelected: @escaping (String) -> Void
        ) {
            self.onSiteSelected = onSiteSelected
            self.sceneView = sceneView
            currentBody = celestialBody
            sceneView.scene = scene
            sceneView.backgroundColor = .clear
            sceneView.allowsCameraControl = false
            sceneView.autoenablesDefaultLighting = false
            sceneView.rendersContinuously = true
            sceneView.antialiasingMode = .multisampling4X

            let camera = SCNCamera()
            camera.fieldOfView = 42
            camera.zNear = 0.01
            camera.zFar = 20
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0, 3.2)
            scene.rootNode.addChildNode(cameraNode)

            let ambientLight = SCNLight()
            ambientLight.type = .ambient
            ambientLight.intensity = 650
            ambientNode.light = ambientLight
            scene.rootNode.addChildNode(ambientNode)

            let keyLight = SCNLight()
            keyLight.type = .directional
            keyLight.intensity = 1250
            keyNode.light = keyLight
            keyNode.eulerAngles = SCNVector3(-0.55, 0.85, 0)
            scene.rootNode.addChildNode(keyNode)

            let fillLight = SCNLight()
            fillLight.type = .directional
            fillLight.intensity = 360
            fillNode.light = fillLight
            fillNode.eulerAngles = SCNVector3(0.4, -1.3, 0)
            scene.rootNode.addChildNode(fillNode)

            let sunLight = SCNLight()
            sunLight.type = .directional
            sunLight.intensity = 0
            sunLight.color = CGColor(red: 1.0, green: 0.97, blue: 0.91, alpha: 1.0)
            sunLightNode.light = sunLight

            let sphere = SCNSphere(radius: 1.0)
            sphere.segmentCount = 160
            textureMaterial.lightingModel = .physicallyBased
            textureMaterial.diffuse.contents = fallbackColor(for: celestialBody)
            textureMaterial.roughness.contents = 0.92
            textureMaterial.metalness.contents = 0.0
            textureMaterial.specular.contents = NSNull()
            sphere.firstMaterial = textureMaterial

            globeNode.geometry = sphere
            scene.rootNode.addChildNode(globeNode)
            globeNode.addChildNode(sunLightNode)
            globeNode.addChildNode(siteNodes)
            updateLighting(for: celestialBody, at: Date(), sunlightEnabled: sunlightEnabled)

            attachInteraction(to: sceneView)
            update(
                view: sceneView,
                celestialBody: celestialBody,
                focusedLocation: focusedLocation,
                sites: sites,
                sunlightEnabled: sunlightEnabled,
                selectedSiteID: selectedSiteID,
                onSiteSelected: onSiteSelected
            )
        }

        private func updateSites(_ sites: [PlanetarySite], selectedSiteID: String) {
            siteNodes.childNodes.forEach { $0.removeFromParentNode() }

            for site in sites {
                let isSelected = site.id == selectedSiteID
                let markerRadius = isSelected ? 0.045 : 0.026
                let markerCenterRadius = 1.0 - (Double(markerRadius) * 0.5)
                let position = pointOnSphere(latitude: site.latitude, longitude: site.longitude, radius: markerCenterRadius)
                let pulsePosition = pointOnSphere(latitude: site.latitude, longitude: site.longitude, radius: 1.01)
                let pulseNormal = normalizedVector(for: pulsePosition)

                let hitTarget = SCNNode(geometry: SCNSphere(radius: isSelected ? 0.08 : 0.055))
                let hitMaterial = SCNMaterial()
                hitMaterial.lightingModel = .constant
                hitMaterial.diffuse.contents = CGColor(red: 1, green: 1, blue: 1, alpha: 0.001)
                hitMaterial.transparency = 0.0
                hitMaterial.colorBufferWriteMask = []
                hitMaterial.readsFromDepthBuffer = false
                hitMaterial.writesToDepthBuffer = false
                hitTarget.geometry?.firstMaterial = hitMaterial
                hitTarget.position = position
                hitTarget.name = site.id
                siteNodes.addChildNode(hitTarget)

                let marker = SCNNode(geometry: SCNSphere(radius: markerRadius))
                let markerMaterial = SCNMaterial()
                markerMaterial.lightingModel = .constant
                markerMaterial.diffuse.contents = markerColor(for: site.celestialBody, isSelected: isSelected)
                marker.geometry?.firstMaterial = markerMaterial
                marker.position = position
                marker.name = site.id
                siteNodes.addChildNode(marker)

                if isSelected {
                    siteNodes.addChildNode(selectionHaloNode(position: pulsePosition, normal: pulseNormal))
                    siteNodes.addChildNode(selectionPingNode(position: pulsePosition, normal: pulseNormal, delay: 0.0))
                    siteNodes.addChildNode(selectionPingNode(position: pulsePosition, normal: pulseNormal, delay: 0.95))
                }
            }
        }

        private func selectionHaloNode(position: SCNVector3, normal: SIMD3<Float>) -> SCNNode {
            let halo = SCNNode(geometry: SCNTorus(ringRadius: 0.05, pipeRadius: 0.0028))
            let haloMaterial = SCNMaterial()
            haloMaterial.lightingModel = .constant
            haloMaterial.diffuse.contents = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.26)
            haloMaterial.emission.contents = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.18)
            haloMaterial.transparency = 0.3
            haloMaterial.readsFromDepthBuffer = false
            haloMaterial.writesToDepthBuffer = false
            halo.geometry?.firstMaterial = haloMaterial
            halo.position = position
            halo.simdOrientation = surfaceOrientation(for: normal)
            return halo
        }

        private func selectionPingNode(position: SCNVector3, normal: SIMD3<Float>, delay: TimeInterval) -> SCNNode {
            let ping = SCNNode(geometry: SCNTorus(ringRadius: 0.05, pipeRadius: 0.0038))
            let pingMaterial = SCNMaterial()
            pingMaterial.lightingModel = .constant
            pingMaterial.diffuse.contents = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.52)
            pingMaterial.emission.contents = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.34)
            pingMaterial.transparency = 0.5
            pingMaterial.readsFromDepthBuffer = false
            pingMaterial.writesToDepthBuffer = false
            ping.geometry?.firstMaterial = pingMaterial
            ping.position = position
            ping.simdOrientation = surfaceOrientation(for: normal)
            ping.opacity = 0.0
            ping.scale = SCNVector3(1.0, 1.0, 1.0)

            let reset = SCNAction.run { node in
                node.opacity = 0.68
                node.scale = SCNVector3(1.0, 1.0, 1.0)
            }
            let expand = SCNAction.scale(to: 2, duration: 1.9)
            expand.timingMode = .easeOut
            let fade = SCNAction.fadeOut(duration: 1.9)
            fade.timingMode = .easeOut
            let cycle = SCNAction.sequence([
                reset,
                .group([expand, fade]),
                .wait(duration: 0.15),
            ])
            ping.runAction(.sequence([
                .wait(duration: delay),
                .repeatForever(cycle),
            ]))

            return ping
        }

        private func focus(on location: CardLocation) {
            stopInertia()
            let yawRotation = simd_quatf(
                angle: Float(-location.longitude * .pi / 180),
                axis: SIMD3<Float>(0, 1, 0)
            )
            let pitchRotation = simd_quatf(
                angle: Float(location.latitude * .pi / 180),
                axis: SIMD3<Float>(1, 0, 0)
            )
            globeNode.simdOrientation = simd_normalize(yawRotation * pitchRotation)
        }

        private func applyFallbackAppearance(for body: CelestialBody) {
            textureMaterial.diffuse.contents = fallbackColor(for: body)
            applyTextureOrientation(for: body)
            textureMaterial.emission.contents = CGColor(gray: 0.0, alpha: 1.0)
        }

        private func loadTexture(for body: CelestialBody) {
            textureTask?.cancel()
            textureTask = Task(priority: .utility) {
                let texture = await PlanetaryTextureComposer.makeTexture(for: body)
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    if let texture {
                        self.textureMaterial.diffuse.contents = texture
                    } else {
                        self.textureMaterial.diffuse.contents = self.fallbackColor(for: body)
                    }
                    self.applyTextureOrientation(for: body)
                }
            }
        }

        private func updateLighting(for body: CelestialBody, at date: Date, sunlightEnabled: Bool) {
            guard sunlightEnabled else {
                ambientNode.light?.intensity = 650
                keyNode.light?.intensity = 1_250
                fillNode.light?.intensity = 360
                sunLightNode.light?.intensity = 0
                return
            }

            switch body {
            case .mars:
                ambientNode.light?.intensity = 80
                keyNode.light?.intensity = 0
                fillNode.light?.intensity = 120
                sunLightNode.light?.intensity = 1_850
                positionSunLight(
                    latitude: 0,
                    longitude: PlanetaryIllumination.marsSubsolarLongitude(at: date)
                )
            case .moon:
                ambientNode.light?.intensity = 50
                keyNode.light?.intensity = 0
                fillNode.light?.intensity = 70
                sunLightNode.light?.intensity = 2_100
                positionSunLight(
                    latitude: 0,
                    longitude: PlanetaryIllumination.moonSubsolarLongitude(at: date)
                )
            case .earth:
                ambientNode.light?.intensity = 650
                keyNode.light?.intensity = 1_250
                fillNode.light?.intensity = 360
                sunLightNode.light?.intensity = 0
            }
        }

        private func positionSunLight(latitude: Double, longitude: Double) {
            sunLightNode.position = pointOnSphere(latitude: latitude, longitude: longitude, radius: 4.0)
            sunLightNode.look(at: SCNVector3Zero)
        }

        private func applyTextureOrientation(for body: CelestialBody) {
            textureMaterial.diffuse.wrapS = .repeat
            textureMaterial.diffuse.wrapT = .repeat

            switch body {
            case .mars:
                textureMaterial.diffuse.contentsTransform = SCNMatrix4Translate(
                    SCNMatrix4MakeScale(1, -1, 1),
                    0,
                    -1,
                    0
                )
            case .moon, .earth:
                textureMaterial.diffuse.contentsTransform = SCNMatrix4Identity
            }
        }

        private func attachInteraction(to sceneView: SCNView) {
            #if os(macOS)
            let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            sceneView.addGestureRecognizer(panGesture)
            let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            sceneView.addGestureRecognizer(clickGesture)
            let magnificationGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
            sceneView.addGestureRecognizer(magnificationGesture)
            panView = sceneView
            #else
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            sceneView.addGestureRecognizer(panGesture)
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            sceneView.addGestureRecognizer(tapGesture)
            let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            sceneView.addGestureRecognizer(pinchGesture)
            #endif
        }

        #if os(macOS)
        @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
            let point = gesture.location(in: panView)
            switch gesture.state {
            case .began:
                stopInertia()
                lastPanPoint = point
            case .changed:
                guard let lastPanPoint, let panView else { return }
                rotateGlobe(from: lastPanPoint, to: point, in: panView)
                self.lastPanPoint = point
            case .ended:
                if let panView {
                    startInertia(with: gesture.velocity(in: panView), in: panView)
                }
                lastPanPoint = nil
            default:
                lastPanPoint = nil
            }
        }

        @objc private func handleTap(_ gesture: NSClickGestureRecognizer) {
            guard let panView else {
                return
            }

            selectSite(at: gesture.location(in: panView), in: panView)
        }

        @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
            switch gesture.state {
            case .began:
                stopInertia()
                lastMagnificationValue = gesture.magnification
            case .changed:
                let previous = lastMagnificationValue ?? 0
                let delta = gesture.magnification - previous
                applyZoom(delta: delta)
                lastMagnificationValue = gesture.magnification
            default:
                lastMagnificationValue = nil
            }
        }
        #else
        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began:
                stopInertia()
                lastPanPoint = point
            case .changed:
                guard let lastPanPoint, let view = gesture.view as? SCNView else { return }
                rotateGlobe(from: lastPanPoint, to: point, in: view)
                self.lastPanPoint = point
            case .ended:
                if let view = gesture.view as? SCNView {
                    startInertia(with: gesture.velocity(in: view), in: view)
                }
                lastPanPoint = nil
            default:
                lastPanPoint = nil
            }
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else {
                return
            }

            selectSite(at: gesture.location(in: view), in: view)
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                stopInertia()
            case .changed:
                applyZoom(delta: gesture.scale - 1)
                gesture.scale = 1
            default:
                break
            }
        }
        #endif

        private func rotateGlobe(from oldPoint: CGPoint, to newPoint: CGPoint, in view: SCNView) {
            let projectedRadius = projectedGlobeRadius(in: view)
            let deltaX = (newPoint.x - oldPoint.x) / projectedRadius
            let deltaY = platformAdjustedVerticalDelta((newPoint.y - oldPoint.y) / projectedRadius)
            let verticalDirection = verticalRotationDirection(for: currentBody)
            let upAxis = normalizedAxis(cameraAxis(for: SIMD3<Float>(0, 1, 0)))
            let rightAxis = normalizedAxis(cameraAxis(for: SIMD3<Float>(1, 0, 0)))
            let horizontalRotation = simd_quatf(angle: Float(deltaX), axis: upAxis)
            let verticalRotation = simd_quatf(angle: Float(verticalDirection * deltaY), axis: rightAxis)
            globeNode.simdOrientation = simd_normalize(verticalRotation * horizontalRotation * globeNode.simdOrientation)
        }

        private func selectSite(at point: CGPoint, in view: SCNView) {
            let results = view.hitTest(point, options: [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue
            ])

            for result in results {
                if let siteID = siteID(for: result.node) {
                    stopInertia()
                    onSiteSelected?(siteID)
                    return
                }
            }
        }

        private func startInertia(with velocity: CGPoint, in view: SCNView) {
            let projectedRadius = projectedGlobeRadius(in: view)
            let verticalDirection = verticalRotationDirection(for: currentBody)
            var angularVelocity = CGPoint(
                x: velocity.x / projectedRadius,
                y: verticalDirection * platformAdjustedVerticalDelta(velocity.y / projectedRadius)
            )

            guard max(abs(angularVelocity.x), abs(angularVelocity.y)) > 0.12 else {
                return
            }

            stopInertia()
            inertiaTask = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                let frameDuration = 1.0 / 60.0
                while !Task.isCancelled {
                    let upAxis = self.normalizedAxis(self.cameraAxis(for: SIMD3<Float>(0, 1, 0)))
                    let rightAxis = self.normalizedAxis(self.cameraAxis(for: SIMD3<Float>(1, 0, 0)))
                    let horizontalRotation = simd_quatf(angle: Float(angularVelocity.x * frameDuration), axis: upAxis)
                    let verticalRotation = simd_quatf(angle: Float(angularVelocity.y * frameDuration), axis: rightAxis)
                    self.globeNode.simdOrientation = simd_normalize(verticalRotation * horizontalRotation * self.globeNode.simdOrientation)

                    angularVelocity.x *= 0.94
                    angularVelocity.y *= 0.94

                    if max(abs(angularVelocity.x), abs(angularVelocity.y)) < 0.02 {
                        break
                    }

                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
        }

        private func stopInertia() {
            inertiaTask?.cancel()
            inertiaTask = nil
        }

        private func applyZoom(delta: CGFloat) {
            let currentDistance = CGFloat(cameraNode.position.z)
            let minimumDistance = globeRadius + minimumSurfaceClearance
            let nextDistance = min(max(currentDistance - (delta * 1.6), minimumDistance), 5.6)
            cameraNode.position.z = SCNFloat(nextDistance)
        }

        private func projectedGlobeRadius(in view: SCNView) -> CGFloat {
            let center = view.projectPoint(SCNVector3(0, 0, 0))
            let edge = view.projectPoint(SCNVector3(0, 1, 0))
            let dx = CGFloat(edge.x - center.x)
            let dy = CGFloat(edge.y - center.y)
            let radius = sqrt((dx * dx) + (dy * dy))
            if radius.isFinite, radius > 1 {
                return radius
            }
            return max(min(view.bounds.width, view.bounds.height) * 0.3, 1)
        }

        private func platformAdjustedVerticalDelta(_ value: CGFloat) -> CGFloat {
            #if os(macOS)
            value
            #else
            -value
            #endif
        }

        private func verticalRotationDirection(for body: CelestialBody) -> CGFloat {
            switch body {
            case .mars:
                -1
            case .moon, .earth:
                -1
            }
        }

        private func cameraAxis(for localAxis: SIMD3<Float>) -> SIMD3<Float> {
            simd_act(cameraNode.presentation.simdWorldOrientation, localAxis)
        }

        private func normalizedAxis(_ axis: SIMD3<Float>) -> SIMD3<Float> {
            let length = simd_length(axis)
            if length > 0 {
                return axis / length
            }
            return axis
        }

        private func normalizedVector(for vector: SCNVector3) -> SIMD3<Float> {
            normalizedAxis(SIMD3<Float>(Float(vector.x), Float(vector.y), Float(vector.z)))
        }

        private func surfaceOrientation(for normal: SIMD3<Float>) -> simd_quatf {
            simd_quatf(from: SIMD3<Float>(0, 1, 0), to: normal)
        }

        private func pointOnSphere(latitude: Double, longitude: Double, radius: Double) -> SCNVector3 {
            let latitudeRadians = latitude * .pi / 180
            let longitudeRadians = longitude * .pi / 180
            let x = radius * cos(latitudeRadians) * sin(longitudeRadians)
            let y = radius * sin(latitudeRadians)
            let z = radius * cos(latitudeRadians) * cos(longitudeRadians)
            return SCNVector3(x, y, z)
        }

        private func fallbackColor(for body: CelestialBody) -> CGColor {
            switch body {
            case .mars:
                return CGColor(red: 0.64, green: 0.31, blue: 0.18, alpha: 1.0)
            case .moon:
                return CGColor(gray: 0.64, alpha: 1.0)
            case .earth:
                return CGColor(red: 0.19, green: 0.42, blue: 0.83, alpha: 1.0)
            }
        }

        private func markerColor(for body: CelestialBody, isSelected: Bool) -> CGColor {
            if isSelected {
                return CGColor(red: 0.99, green: 0.88, blue: 0.48, alpha: 1.0)
            }

            switch body {
            case .mars:
                return CGColor(red: 1.0, green: 0.93, blue: 0.88, alpha: 0.95)
            case .moon:
                return CGColor(red: 0.83, green: 0.93, blue: 1.0, alpha: 0.95)
            case .earth:
                return CGColor(red: 0.72, green: 0.86, blue: 1.0, alpha: 0.95)
            }
        }

        private func siteID(for node: SCNNode?) -> String? {
            var currentNode = node
            while let node = currentNode {
                if let name = node.name, !name.isEmpty {
                    return name
                }
                currentNode = node.parent
            }
            return nil
        }
    }
}

private enum PlanetaryIllumination {
    private static let moonSynodicMonth = 29.530588853
    private static let moonReferenceNewMoon = ISO8601DateFormatter().date(from: "2000-01-06T18:14:00Z")!

    static func moonSubsolarLongitude(at date: Date) -> Double {
        let ageDays = positiveModulo(date.timeIntervalSince(moonReferenceNewMoon) / 86_400, moonSynodicMonth)
        let phaseDegrees = (ageDays / moonSynodicMonth) * 360
        return signedModulo(180 - phaseDegrees, 360)
    }

    static func marsSubsolarLongitude(at date: Date) -> Double {
        let utcJulianDate = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let terrestrialTimeJulianDate = utcJulianDate + 69.184 / 86_400
        let marsSolDate = (terrestrialTimeJulianDate - 2_405_522.002_877_9) / 1.027_491_251_7
        let coordinatedMarsTime = positiveModulo(marsSolDate * 24, 24)
        return signedModulo((12 - coordinatedMarsTime) * 15, 360)
    }

    private static func positiveModulo(_ value: Double, _ modulus: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder >= 0 ? remainder : remainder + modulus
    }

    private static func signedModulo(_ value: Double, _ modulus: Double) -> Double {
        let normalized = positiveModulo(value, modulus)
        return normalized > modulus / 2 ? normalized - modulus : normalized
    }
}

private enum PlanetaryTextureComposer {
    private struct TextureTileGrid {
        let rows: [[URL]]

        init(rows: [[URL]]) {
            self.rows = rows
        }

        init(basePath: String, fileExtension: String, zoomLevel: Int) {
            let rowCount = 1 << zoomLevel
            let columnCount = 2 << zoomLevel
            rows = (0..<rowCount).map { row in
                (0..<columnCount).map { column in
                    URL(
                        string: "https://trek.nasa.gov/tiles/\(basePath)/1.0.0/default/default028mm/\(zoomLevel)/\(row)/\(column).\(fileExtension)"
                    )!
                }
            }
        }
    }

    private static let tileCacheDirectory: URL = {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return (cachesDirectory ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("PlanetaryTextureTiles", isDirectory: true)
    }()

    static func makeTexture(for body: CelestialBody) async -> CGImage? {
        if let cached = await PlanetaryTextureCache.shared.cachedTexture(for: body) {
            return cached
        }

        if let inFlight = await PlanetaryTextureCache.shared.inFlightTexture(for: body) {
            return await inFlight.value
        }

        let task = Task(priority: .utility) { await renderTexture(for: body) }
        await PlanetaryTextureCache.shared.storeInFlight(task, for: body)
        let image = await task.value
        await PlanetaryTextureCache.shared.finish(texture: image, for: body)
        return image
    }

    private static func renderTexture(for body: CelestialBody) async -> CGImage? {
        let grid = textureTileGrid(for: body)
        guard !grid.rows.isEmpty else {
            return nil
        }

        var stitchedRows: [[CGImage]] = []
        for row in grid.rows {
            var images: [CGImage] = []
            for url in row {
                guard let image = await loadImage(from: url) else {
                    return nil
                }
                images.append(image)
            }
            guard !images.isEmpty else {
                return nil
            }
            stitchedRows.append(images)
        }

        guard let stitched = stitch(rows: stitchedRows) else {
            return nil
        }

        if body == .mars {
            return colorizeMarsTexture(stitched) ?? stitched
        }

        return stitched
    }

    private static func textureTileGrid(for body: CelestialBody) -> TextureTileGrid {
        switch body {
        case .mars:
            return TextureTileGrid(
                basePath: "Mars/EQ/msss_atlas_simp_clon",
                fileExtension: "png",
                zoomLevel: 3
            )
        case .moon:
            return TextureTileGrid(
                basePath: "Moon/EQ/LRO_WAC_Mosaic_Global_303ppd_v02",
                fileExtension: "jpg",
                zoomLevel: 2
            )
        case .earth:
            return TextureTileGrid(rows: [])
        }
    }

    private static func loadImage(from url: URL) async -> CGImage? {
        let cachedFileURL = cachedTileURL(for: url)
        if let cachedData = try? Data(contentsOf: cachedFileURL),
           let cachedImage = decodeImage(from: cachedData) {
            return cachedImage
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
                return nil
            }

            try? ensureTileCacheDirectoryExists()
            try? data.write(to: cachedFileURL, options: .atomic)
            return decodeImage(from: data)
        } catch {
            return nil
        }
    }

    private static func cachedTileURL(for remoteURL: URL) -> URL {
        let cacheKey = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let fileExtension = remoteURL.pathExtension.isEmpty ? "tile" : remoteURL.pathExtension
        return tileCacheDirectory.appendingPathComponent("\(cacheKey).\(fileExtension)")
    }

    private static func ensureTileCacheDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: tileCacheDirectory,
            withIntermediateDirectories: true
        )
    }

    private static func decodeImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func stitch(rows: [[CGImage]]) -> CGImage? {
        guard let firstRow = rows.first, !firstRow.isEmpty else {
            return nil
        }

        let width = firstRow.reduce(0) { $0 + $1.width }
        let height = rows.reduce(0) { partialResult, row in
            partialResult + (row.first?.height ?? 0)
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        var currentY = height
        for row in rows {
            guard let rowHeight = row.first?.height else {
                return nil
            }

            currentY -= rowHeight
            var currentX = 0
            for image in row {
                context.draw(
                    image,
                    in: CGRect(x: currentX, y: currentY, width: image.width, height: image.height)
                )
                currentX += image.width
            }
        }

        return context.makeImage()
    }

    private static func colorizeMarsTexture(_ image: CGImage) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: rect)

        context.setBlendMode(.multiply)
        context.setFillColor(CGColor(red: 0.78, green: 0.52, blue: 0.33, alpha: 0.75))
        context.fill(rect)

        context.setBlendMode(.overlay)
        context.setFillColor(CGColor(red: 0.96, green: 0.67, blue: 0.42, alpha: 0.22))
        context.fill(rect)

        return context.makeImage()
    }
}

private actor PlanetaryTextureCache {
    static let shared = PlanetaryTextureCache()

    private var textures: [String: CGImage] = [:]
    private var inFlightTasks: [String: Task<CGImage?, Never>] = [:]

    func cachedTexture(for body: CelestialBody) -> CGImage? {
        textures[body.rawValue]
    }

    func inFlightTexture(for body: CelestialBody) -> Task<CGImage?, Never>? {
        inFlightTasks[body.rawValue]
    }

    func storeInFlight(_ task: Task<CGImage?, Never>, for body: CelestialBody) {
        inFlightTasks[body.rawValue] = task
    }

    func finish(texture: CGImage?, for body: CelestialBody) {
        if let texture {
            textures[body.rawValue] = texture
        }
        inFlightTasks[body.rawValue] = nil
    }
}
