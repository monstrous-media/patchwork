#if os(macOS)
import SwiftUI
import QuartzCore

/// Lightweight render statistics, switched on from View ▸ Show render stats.
///
/// `.measured("Name")` on a view counts how often that view's body is evaluated; the badge in the status
/// bar shows counts per second. A high count while nothing is happening means something is invalidating
/// views needlessly; a high count per edit shows how wide one change fans out. Page switches are timed
/// from the sidebar selection change to the first frame after the new page appears.
///
/// Deliberately separate from AppModel: the badge observes PerfStats only, so updating the readout
/// never re-renders the editor.
final class PerfStats: ObservableObject {
    static let shared = PerfStats()
    @Published var summary = ""
    @Published var enabled = UserDefaults.standard.bool(forKey: "perfStats") {
        didSet { UserDefaults.standard.set(enabled, forKey: "perfStats"); if enabled { start() } else { stop() } }
    }

    private var counts: [String: Int] = [:]
    private var timer: Timer?
    private var switchStart: CFTimeInterval?
    private var lastSwitch: String = ""

    init() { if enabled { start() } }

    func tick(_ name: String) {
        guard enabled else { return }
        counts[name, default: 0] += 1
    }

    func pageSwitchBegan() {
        guard enabled else { return }
        switchStart = CACurrentMediaTime()
    }

    /// Call from the new page's onAppear; the elapsed time is taken one run-loop turn later, after
    /// layout and the first draw have been committed.
    func pageAppeared(_ name: String) {
        guard enabled, let t0 = switchStart else { return }
        switchStart = nil
        DispatchQueue.main.async { [weak self] in
            let ms = (CACurrentMediaTime() - t0) * 1000
            self?.lastSwitch = String(format: "%@ %.0f ms", name, ms)
        }
    }

    private func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.flush() }
    }
    private func stop() { timer?.invalidate(); timer = nil; counts = [:]; summary = "" }

    private func flush() {
        let top = counts.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key) \($0.value)" }
        counts = [:]
        var s = "bodies/s: " + (top.isEmpty ? "0" : top.joined(separator: " · "))
        if !lastSwitch.isEmpty { s += "   switch: " + lastSwitch }
        if s != summary { summary = s }
    }
}

struct Measured: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        PerfStats.shared.tick(name)
        return content
    }
}

extension View {
    /// Count this view's body evaluations under `name` when render stats are on.
    func measured(_ name: String) -> some View { modifier(Measured(name: name)) }
}

/// The readout in the status bar.
struct PerfBadge: View {
    @ObservedObject var stats = PerfStats.shared
    var body: some View {
        if stats.enabled {
            Text(stats.summary.isEmpty ? "render stats on" : stats.summary)
                .font(Theme.monoCaption).foregroundStyle(Theme.blue).lineLimit(1)
                .help("Body evaluations per second for the busiest views, and the last page switch to first frame. View ▸ Show render stats to turn off.")
        }
    }
}

struct PerfCommands: Commands {
    @ObservedObject var stats = PerfStats.shared
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Show render stats", isOn: $stats.enabled)
        }
    }
}
#endif
