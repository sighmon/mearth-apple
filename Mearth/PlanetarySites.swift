import Foundation

struct PlanetarySite: Identifiable, Hashable {
    let id: String
    let name: String
    let mission: String
    let celestialBody: CelestialBody
    let category: String
    let latitude: Double
    let longitude: Double
    let year: Int?
    let note: String

    init(
        name: String,
        mission: String,
        celestialBody: CelestialBody,
        category: String,
        latitude: Double,
        longitude: Double,
        year: Int? = nil,
        note: String
    ) {
        self.name = name
        self.mission = mission
        self.celestialBody = celestialBody
        self.category = category
        self.latitude = latitude
        self.longitude = Self.normalizedLongitude(longitude)
        self.year = year
        self.note = note
        self.id = "\(celestialBody.rawValue)-\(mission)-\(name)"
    }

    var location: CardLocation {
        CardLocation(
            title: name,
            subtitle: mission,
            body: celestialBody,
            latitude: latitude,
            longitude: longitude,
            note: note
        )
    }

    var metadataLine: String {
        if let year {
            return "\(category) · \(year)"
        }
        return category
    }

    func matches(location: CardLocation) -> Bool {
        celestialBody == location.body &&
        abs(latitude - location.latitude) < 0.02 &&
        abs(longitude - Self.normalizedLongitude(location.longitude)) < 0.02
    }

    static func currentLocation(from location: CardLocation) -> PlanetarySite {
        PlanetarySite(
            name: location.title,
            mission: location.subtitle,
            celestialBody: location.body,
            category: "Current selection",
            latitude: location.latitude,
            longitude: location.longitude,
            note: location.note
        )
    }

    private static func normalizedLongitude(_ longitude: Double) -> Double {
        var normalized = longitude.truncatingRemainder(dividingBy: 360)
        if normalized > 180 {
            normalized -= 360
        } else if normalized <= -180 {
            normalized += 360
        }
        return normalized
    }
}

enum PlanetarySiteCatalog {
    static func sites(for body: CelestialBody, selectedLocation: CardLocation) -> [PlanetarySite] {
        guard body == .mars || body == .moon else {
            return []
        }

        var sites = curatedSites(for: body)
        if let selectedIndex = sites.firstIndex(where: { $0.matches(location: selectedLocation) }) {
            let selectedSite = sites.remove(at: selectedIndex)
            sites.insert(selectedSite, at: 0)
        } else {
            sites.insert(.currentLocation(from: selectedLocation), at: 0)
        }
        return sites
    }

    private static func curatedSites(for body: CelestialBody) -> [PlanetarySite] {
        switch body {
        case .mars:
            marsSites
        case .moon:
            moonSites
        case .earth:
            []
        }
    }

    private static let marsSites: [PlanetarySite] = [
        PlanetarySite(name: "Viking 1", mission: "Chryse Planitia", celestialBody: .mars, category: "Robotic lander", latitude: 22.48, longitude: -47.97, year: 1976, note: "NASA's first successful Mars landing."),
        PlanetarySite(name: "Viking 2", mission: "Utopia Planitia", celestialBody: .mars, category: "Robotic lander", latitude: 47.97, longitude: -134.01, year: 1976, note: "The second Viking lander touched down in northern Utopia Planitia."),
        PlanetarySite(name: "Pathfinder", mission: "Ares Vallis", celestialBody: .mars, category: "Robotic lander", latitude: 19.13, longitude: -33.22, year: 1997, note: "Mars Pathfinder delivered the Sojourner rover to Ares Vallis."),
        PlanetarySite(name: "Sojourner", mission: "Mars Pathfinder", celestialBody: .mars, category: "Rover landing", latitude: 19.13, longitude: -33.22, year: 1997, note: "First rover to operate on another planet."),
        PlanetarySite(name: "Spirit", mission: "Gusev Crater", celestialBody: .mars, category: "Rover landing", latitude: -14.57, longitude: 175.48, year: 2004, note: "MER-A landed inside Gusev Crater."),
        PlanetarySite(name: "Opportunity", mission: "Meridiani Planum", celestialBody: .mars, category: "Rover landing", latitude: -1.95, longitude: -5.53, year: 2004, note: "MER-B landed on Meridiani Planum."),
        PlanetarySite(name: "Phoenix", mission: "Green Valley", celestialBody: .mars, category: "Robotic lander", latitude: 68.22, longitude: -125.75, year: 2008, note: "Phoenix sampled near-surface ice in the northern plains."),
        PlanetarySite(name: "Curiosity Rover", mission: "Gale Crater", celestialBody: .mars, category: "Rover landing", latitude: -4.5895, longitude: 137.4417, year: 2012, note: "Curiosity is exploring Gale Crater and Mount Sharp."),
        PlanetarySite(name: "Beagle 2", mission: "Isidis Planitia", celestialBody: .mars, category: "Robotic lander", latitude: 11.53, longitude: 90.43, year: 2003, note: "Beagle 2 reached the surface but never fully deployed."),
        PlanetarySite(name: "InSight", mission: "Elysium Planitia", celestialBody: .mars, category: "Robotic lander", latitude: 4.5024, longitude: 135.6234, year: 2018, note: "InSight measured marsquakes and interior structure."),
        PlanetarySite(name: "Perseverance", mission: "Jezero Crater", celestialBody: .mars, category: "Rover landing", latitude: 18.4446, longitude: 77.4509, year: 2021, note: "Perseverance is caching samples in Jezero Crater."),
        PlanetarySite(name: "Zhurong", mission: "Utopia Planitia", celestialBody: .mars, category: "Rover landing", latitude: 25.066, longitude: 109.925, year: 2021, note: "China's Zhurong rover landed in southern Utopia Planitia.")
    ]

    private static let moonSites: [PlanetarySite] = [
        PlanetarySite(name: "Luna 9", mission: "Oceanus Procellarum", celestialBody: .moon, category: "Robotic lander", latitude: 7.08, longitude: -64.37, year: 1966, note: "First successful soft landing on the Moon."),
        PlanetarySite(name: "Surveyor 1", mission: "Oceanus Procellarum", celestialBody: .moon, category: "Robotic lander", latitude: -2.47, longitude: -43.34, year: 1966, note: "NASA's first successful soft lunar landing."),
        PlanetarySite(name: "Luna 13", mission: "Oceanus Procellarum", celestialBody: .moon, category: "Robotic lander", latitude: 18.87, longitude: -62.05, year: 1966, note: "Follow-on Soviet soft landing in Oceanus Procellarum."),
        PlanetarySite(name: "Surveyor 3", mission: "Oceanus Procellarum", celestialBody: .moon, category: "Robotic lander", latitude: -3.01, longitude: -23.44, year: 1967, note: "Surveyor 3 was later visited by Apollo 12 astronauts."),
        PlanetarySite(name: "Surveyor 5", mission: "Mare Tranquillitatis", celestialBody: .moon, category: "Robotic lander", latitude: 1.41, longitude: 23.18, year: 1967, note: "Soft landed in Mare Tranquillitatis."),
        PlanetarySite(name: "Surveyor 6", mission: "Sinus Medii", celestialBody: .moon, category: "Robotic lander", latitude: 0.47, longitude: -1.42, year: 1967, note: "Surveyor 6 performed a short engine hop after landing."),
        PlanetarySite(name: "Surveyor 7", mission: "Tycho foothills", celestialBody: .moon, category: "Robotic lander", latitude: -40.98, longitude: -11.47, year: 1968, note: "Last Surveyor mission, landed near Tycho crater."),
        PlanetarySite(name: "Apollo 11", mission: "Tranquility Base", celestialBody: .moon, category: "Crewed landing", latitude: 0.6741, longitude: 23.4729, year: 1969, note: "First human landing site on the Moon."),
        PlanetarySite(name: "Apollo 12", mission: "Ocean of Storms", celestialBody: .moon, category: "Crewed landing", latitude: -3.0124, longitude: -23.4216, year: 1969, note: "Apollo 12 landed near Surveyor 3."),
        PlanetarySite(name: "Luna 16", mission: "Mare Fecunditatis", celestialBody: .moon, category: "Sample return", latitude: -0.69, longitude: 56.30, year: 1970, note: "First robotic sample return from the Moon."),
        PlanetarySite(name: "Luna 17", mission: "Mare Imbrium", celestialBody: .moon, category: "Robotic lander", latitude: 38.28, longitude: -35.00, year: 1970, note: "Delivered the Lunokhod 1 rover."),
        PlanetarySite(name: "Apollo 14", mission: "Fra Mauro", celestialBody: .moon, category: "Crewed landing", latitude: -3.6453, longitude: -17.4714, year: 1971, note: "Apollo 14 sampled the Fra Mauro formation."),
        PlanetarySite(name: "Apollo 15", mission: "Hadley-Apennine", celestialBody: .moon, category: "Crewed landing", latitude: 26.1322, longitude: 3.6339, year: 1971, note: "First lunar rover used on the surface."),
        PlanetarySite(name: "Luna 20", mission: "Apollonius Highlands", celestialBody: .moon, category: "Sample return", latitude: 3.79, longitude: 56.62, year: 1972, note: "Robotic sample return from the lunar highlands."),
        PlanetarySite(name: "Apollo 16", mission: "Descartes Highlands", celestialBody: .moon, category: "Crewed landing", latitude: -8.9734, longitude: 15.5011, year: 1972, note: "Apollo 16 explored the Descartes Highlands."),
        PlanetarySite(name: "Apollo 17", mission: "Taurus-Littrow", celestialBody: .moon, category: "Crewed landing", latitude: 20.1908, longitude: 30.7717, year: 1972, note: "Most recent crewed lunar landing site."),
        PlanetarySite(name: "Luna 21", mission: "Le Monnier", celestialBody: .moon, category: "Robotic lander", latitude: 25.85, longitude: 30.45, year: 1973, note: "Delivered the Lunokhod 2 rover."),
        PlanetarySite(name: "Luna 24", mission: "Mare Crisium", celestialBody: .moon, category: "Sample return", latitude: 12.71, longitude: 62.21, year: 1976, note: "Final Soviet lunar sample return mission."),
        PlanetarySite(name: "Chang'e 3", mission: "Mare Imbrium", celestialBody: .moon, category: "Robotic lander", latitude: 44.12, longitude: -19.51, year: 2013, note: "Delivered the Yutu rover to Mare Imbrium."),
        PlanetarySite(name: "Chang'e 4", mission: "Von Karman crater", celestialBody: .moon, category: "Robotic lander", latitude: -45.46, longitude: 177.60, year: 2019, note: "First soft landing on the lunar far side."),
        PlanetarySite(name: "Chang'e 5", mission: "Mons Rumker", celestialBody: .moon, category: "Sample return", latitude: 43.06, longitude: -51.92, year: 2020, note: "Returned fresh lunar samples from Oceanus Procellarum."),
        PlanetarySite(name: "SLIM", mission: "Shioli crater", celestialBody: .moon, category: "Robotic lander", latitude: -13.31, longitude: 25.25, year: 2024, note: "Japan's precision lunar landing mission."),
        PlanetarySite(name: "Chang'e 6", mission: "Apollo basin", celestialBody: .moon, category: "Sample return", latitude: -41.64, longitude: -153.99, year: 2024, note: "Sample-return landing on the lunar far side.")
    ]
}
