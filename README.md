# Mearth

SwiftUI app target for iOS, macOS, and Apple TV.

Data sources:
- Curiosity / REMS: CAB's official Mars weather widget feed at `http://cab.inta-csic.es/rems/wp-content/plugins/marsweather-widget/api.php`
- Earth and local current temperatures: Open-Meteo
- Local position fallback: `ipapi.co`, then `ipwho.is`
- Moon card: modeled estimate for Apollo 11's Tranquility Base based on lunar phase and local solar angle

Build examples:
- `xcodebuild -project Mearth.xcodeproj -scheme Mearth -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project Mearth.xcodeproj -scheme Mearth -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project Mearth.xcodeproj -scheme Mearth -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build`
