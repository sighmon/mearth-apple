import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct MearthApp: App {
    var body: some Scene {
        #if os(macOS)
        WindowGroup("Mearth", id: MacWindowConfigurator.mainWindowID) {
            DashboardView()
                .background(MacWindowConfigurator())
                .modifier(MacWindowChromeModifier())
        }
        .windowStyle(.hiddenTitleBar)
        #else
        WindowGroup {
            DashboardView()
        }
        #endif
    }
}

#if os(macOS)
private struct MacWindowChromeModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .toolbar(removing: .title)
        } else {
            content
        }
    }
}

private struct MacWindowConfigurator: NSViewRepresentable {
    static let mainWindowID = "main-window"
    private static let autosaveName = "MearthMainWindow"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else {
            return
        }

        if window.identifier?.rawValue != Self.mainWindowID {
            window.identifier = NSUserInterfaceItemIdentifier(Self.mainWindowID)
        }
        if window.frameAutosaveName.isEmpty {
            window.setFrameAutosaveName(Self.autosaveName)
        }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
    }
}
#endif
