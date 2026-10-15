import SwiftUI

struct AgentSoundsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let env = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: env.store, activity: env.activity, previewer: env.previewer, setup: env.setup,
                     updates: env.updates)
        } label: {
            Image(nsImage: EqualizerIcon.image(
                animating: env.activity.isAnimating,
                phase: env.activity.phase,
                muted: env.store.config.muted || env.store.config.volume == 0,
                level: env.store.config.volume))
        }
        .menuBarExtraStyle(.window)

        Window("Agent Sounds Configuration", id: "config") {
            ConfigWindow(store: env.store, activity: env.activity, previewer: env.previewer, setup: env.setup,
                         updates: env.updates)
        }
        .defaultSize(width: 760, height: 600)
    }
}
