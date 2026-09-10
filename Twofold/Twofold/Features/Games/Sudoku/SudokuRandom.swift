//
//  SudokuRandom.swift
//  Twofold
//
//  A random number generator that gives the same numbers on both partners' phones, forever.
//
//  Puzzles are generated on device rather than fetched, so two people opening the same game must
//  derive an identical grid without talking to each other. Everything about that rests on this
//  file: same seed in, same sequence out, on every device and every future version of the app.
//
//  Which is why it is written out rather than taken from the standard library.
//  `SystemRandomNumberGenerator` is explicitly not reproducible, and `shuffled(using:)` — which
//  looks safe, since it takes the generator as a parameter — is also unsafe here: its *algorithm*
//  is an implementation detail of the standard library, free to change between Swift versions. It
//  would keep compiling, keep passing a casual test, and quietly hand two partners on different app
//  versions different puzzles. So the shuffle below is spelled out too.
//
//  SplitMix64 is the choice because it is short enough to read in one sitting and verify against
//  the published constants, which matters more here than statistical quality: this seeds a puzzle,
//  not a cipher.
//

import Foundation

/// Deterministic, portable, and fixed for the life of the app.
///
/// Changing any constant in here changes every puzzle every seed produces. That is a compatibility
/// break, not a refactor — see `SudokuGeneratorTests.knownSeedProducesKnownPuzzle`, which exists to
/// fail loudly if it ever happens.
struct SudokuRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Zero is a legal SplitMix64 state, but a seed of zero arriving by accident (an
        // uninitialised value, a truncated hash) is worth not treating as a real choice.
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    /// Derived from the puzzle's identity rather than from chance. Both partners read the same
    /// `content_id` from the same round, so both arrive here with the same 128 bits and fold them
    /// to the same 64.
    init(puzzleID: UUID) {
        let bytes = puzzleID.uuid
        func pack(_ b: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)) -> UInt64 {
            var v: UInt64 = 0
            for byte in [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7] { v = (v << 8) | UInt64(byte) }
            return v
        }
        let high = pack((bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7))
        let low = pack((bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15))
        self.init(seed: high ^ low)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `0..<bound`, by rejection rather than modulo.
    ///
    /// A plain `next() % bound` biases toward the low end whenever `bound` does not divide 2^64,
    /// which for a 9-way choice it does not. The bias is small and would never be noticed — the
    /// puzzles would simply be very slightly less varied than they look — which is exactly the kind
    /// of wrongness worth spending four lines to avoid.
    mutating func next(upperBound bound: Int) -> Int {
        precondition(bound > 0, "bound must be positive")
        let limit = UInt64.max - (UInt64.max % UInt64(bound))
        var value = next()
        while value >= limit { value = next() }
        return Int(value % UInt64(bound))
    }

    /// Fisher-Yates, written here rather than borrowed.
    ///
    /// `Array.shuffle(using:)` would take this generator and still not be safe: the standard
    /// library does not promise which permutation a given generator state produces, so a Swift
    /// upgrade could change every puzzle in the app without a single line of this code changing.
    mutating func shuffled<T>(_ items: [T]) -> [T] {
        var result = items
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            let j = next(upperBound: i + 1)
            if i != j { result.swapAt(i, j) }
        }
        return result
    }
}
