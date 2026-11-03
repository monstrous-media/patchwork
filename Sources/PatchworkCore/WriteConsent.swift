import Foundation

/// The rule every command that changes what the synth *stores* follows: an explicit `--yes`, or a
/// `y` typed at a terminal after being told what will be overwritten. Anything else — a script, a
/// pipe, a CI job, an agent — is refused before a byte is sent. Pure so the CLI's behaviour can be
/// tested without a terminal or a synth.
public enum WriteConsent {
    public enum Decision: Equatable {
        case proceed
        case refused(String)
    }

    public static let refusalMessage = "refusing to write to the M1 without --yes"

    /// - Parameters:
    ///   - yes: `--yes` was given.
    ///   - interactive: standard input is a terminal (someone can answer a prompt).
    ///   - description: what will be overwritten, shown before the prompt.
    ///   - prompt: shows the text and returns the line typed, or nil at end of input.
    public static func decide(yes: Bool, interactive: Bool, description: String,
                              prompt: (String) -> String?) -> Decision {
        if yes { return .proceed }
        guard interactive else { return .refused(refusalMessage + " (standard input is not a terminal)") }
        let answer = prompt(description + "\nContinue? [y/N] ")?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (answer == "y" || answer == "yes") ? .proceed : .refused("cancelled — nothing was sent")
    }

    /// Slot numbers as compact ranges with their labels: [0,1,2,5,7,8] → "I00–I02, I05, I07–I08".
    public static func slotRanges(_ slots: [Int], label: (Int) -> String) -> String {
        let s = Array(Set(slots)).sorted()
        var out: [String] = []
        var i = 0
        while i < s.count {
            var j = i
            while j + 1 < s.count && s[j + 1] == s[j] + 1 { j += 1 }
            out.append(j == i ? label(s[i]) : "\(label(s[i]))–\(label(s[j]))")
            i = j + 1
        }
        return out.joined(separator: ", ")
    }
}
