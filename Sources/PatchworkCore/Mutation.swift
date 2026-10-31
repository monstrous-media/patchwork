import Foundation

/// Deterministic, seedable RNG (SplitMix64) so "random" patches are reproducible from a seed.
public struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Synth-agnostic generators: they only know a program through `ProgramData` and its parameter table.
public enum Mutation {

    /// A fully random (but in-range) program. Parameters marked non-randomisable (names, raw effect
    /// bytes) are inherited from `base`. `finish` lets a synth definition apply its own "keep it playable" tweaks.
    public static func randomise<P: ProgramData>(definitions: [ParamDef], base: P, seed: UInt64,
                                                 finish: ((inout P, inout SeededRandom) -> Void)? = nil) -> P {
        var rng = SeededRandom(seed: seed)
        var p = base
        for def in definitions where def.randomisable {
            setRandom(def, in: &p, using: &rng)
        }
        finish?(&p, &rng)
        return p
    }

    /// Nudge each randomisable parameter with probability `amount` (0…1), by a step scaled to its range.
    public static func mutate<P: ProgramData>(definitions: [ParamDef], _ program: P, amount: Double, seed: UInt64) -> P {
        var rng = SeededRandom(seed: seed)
        var p = program
        let prob = max(0, min(1, amount))
        for def in definitions where def.randomisable {
            guard Double.random(in: 0..<1, using: &rng) < prob else { continue }
            switch def.kind {
            case .unsigned(let mx):
                let step = max(1, Int(Double(mx) * 0.15))
                p.setUnsigned(def.index, max(0, min(mx, p.unsigned(def.index) + Int.random(in: -step...step, using: &rng))))
            case .signed(let mn, let mx):
                let step = max(1, Int(Double(mx - mn) * 0.08))
                p.setSigned(def.index, max(mn, min(mx, p.signed(def.index) + Int.random(in: -step...step, using: &rng))))
            case .note:
                p.setUnsigned(def.index, max(0, min(127, p.unsigned(def.index) + Int.random(in: -7...7, using: &rng))))
            case .multisound:
                if Double.random(in: 0..<1, using: &rng) < 0.3 {
                    p.setUnsigned(def.index, Int.random(in: 0...99, using: &rng))
                }
            default:
                if Double.random(in: 0..<1, using: &rng) < 0.3 {
                    setRandom(def, in: &p, using: &rng)
                }
            }
        }
        return p
    }

    /// Linear interpolation between two programs for numeric parameters; discrete ones switch at t = 0.5.
    public static func morph<P: ProgramData>(definitions: [ParamDef], _ a: P, _ b: P, t: Double) -> P {
        let t = max(0, min(1, t))
        var p = t < 0.5 ? a : b
        func lerp(_ x: Int, _ y: Int) -> Int { Int((Double(x) + (Double(y) - Double(x)) * t).rounded()) }
        for def in definitions {
            switch def.kind {
            case .unsigned, .note, .pan:
                p.setUnsigned(def.index, lerp(a.unsigned(def.index), b.unsigned(def.index)))
            case .signed:
                p.setSigned(def.index, lerp(a.signed(def.index), b.signed(def.index)))
            default:
                break
            }
        }
        p.name = String((a.name + "/" + b.name).prefix(10))
        return p
    }

    static func setRandom<P: ProgramData>(_ def: ParamDef, in p: inout P, using rng: inout SeededRandom) {
        switch def.kind {
        case .unsigned(let mx):
            p.setUnsigned(def.index, Int.random(in: 0...mx, using: &rng))
        case .signed(let mn, let mx):
            p.setSigned(def.index, Int.random(in: mn...mx, using: &rng))
        case .choice(let labels):
            p.setUnsigned(def.index, Int.random(in: 0..<labels.count, using: &rng))
        case .bits(let fields):
            for f in fields {
                p.setField(def.index, shift: f.shift, width: f.width, Int.random(in: 0..<(1 << f.width), using: &rng))
            }
        case .note:
            p.setUnsigned(def.index, Int.random(in: 36...84, using: &rng))
        case .multisound:
            p.setUnsigned(def.index, Int.random(in: 0...99, using: &rng))
        case .octave:
            p.setSigned(def.index, Int.random(in: -1...1, using: &rng))
        case .pan:
            p.setUnsigned(def.index, Int.random(in: 0...101, using: &rng))
        case .effectType:
            p.setUnsigned(def.index, Int.random(in: 0...EffectTypes.thruValue, using: &rng))
        case .ascii, .effectParam:
            break
        }
    }
}

// MARK: - Generators as part of a synth definition (defaults use the generic Mutation; synths may override)

public extension SynthDefinition {
    static func randomise(base: Program, seed: UInt64) -> Program {
        Mutation.randomise(definitions: parameters, base: base, seed: seed)
    }
    static func mutate(_ program: Program, amount: Double, seed: UInt64) -> Program {
        Mutation.mutate(definitions: parameters, program, amount: amount, seed: seed)
    }
    static func morph(_ a: Program, _ b: Program, t: Double) -> Program {
        Mutation.morph(definitions: parameters, a, b, t: t)
    }
}
