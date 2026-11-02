#if os(macOS)
import SwiftUI
import AppKit
import PatchworkCore

@main
struct PatchworkApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var help = HelpState()

    init() {
        // Running from `swift run` (no .app bundle) we still want a Dock icon, menu bar and key window.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Patchwork — \(ActiveSynth.displayName)") {
            ContentView()
                .environmentObject(model)
                .environmentObject(help)
        }
        .commands {
            GuideCommands()
            AppearanceCommands()
            PerfCommands()
            CommandGroup(replacing: .newItem) {
                Button("Init program") { model.load(M1Program(), announce: "Init program", thenSend: model.autoSend) }
                    .keyboardShortcut("n")
            }
            CommandMenu("M1") {
                Button("Request current program") { model.requestProgram() }.keyboardShortcut("r")
                Button("Switch M1 to Program mode") { model.switchToProgramMode() }
                Button("Ask M1 which mode it's in") { model.requestMode() }
                Button("Fetch bank from M1 (one program at a time)") { model.fetchBankFromM1() }
                Button("Request bank as one 16 KB dump") { model.requestAllPrograms() }
                Button("Send to edit buffer") { model.sendProgram() }.keyboardShortcut("s")
                Button("Write to slot I\(String(format: "%02d", model.writeSlot))") { model.writeToSlot() }.keyboardShortcut("w")
                Divider()
                Button(model.isPlaying ? "Stop phrase" : "Play phrase") { model.togglePlay() }.keyboardShortcut(.return, modifiers: .command)
                Button("All notes off") { model.stop() }.keyboardShortcut(".", modifiers: .command)
                Divider()
                Button("Randomise") { model.randomise() }.keyboardShortcut("g")
                Button("Mutate 20%") { model.mutate(amount: 0.2) }.keyboardShortcut("m")
                Divider()
                Button("Rescan MIDI devices") { model.refreshEndpoints() }
            }
        }
        Window("Patchwork Guide", id: "help") {
            HelpView()
                .environmentObject(help)
                .tint(Theme.accent)
        }
        .defaultSize(width: 900, height: 640)
    }
}
#endif

#if os(macOS)
/// View ▸ Appearance: dark (default), light, or follow the system.
struct AppearanceCommands: Commands {
    @AppStorage("appearance") private var appearance: Appearance = .dark
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { a in Text(a.title).tag(a) }
            }
        }
    }
}

/// Help menu → the bundled guide.
struct GuideCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Patchwork Guide") { openWindow(id: "help") }.keyboardShortcut("?", modifiers: .command)
        }
    }
}
#else
@main
struct PatchworkApp {
    static func main() { print("Patchwork is a macOS app (SwiftUI + CoreMIDI).") }
}
#endif
