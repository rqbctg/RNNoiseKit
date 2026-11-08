import XCTest
@testable import RNNoiseKit

final class RNNoiseDenoiserTests: XCTestCase {
    private let frameSize = RNNoiseDenoiser.frameSize

    func testFrameSizeIs10msAt48k() {
        XCTAssertEqual(frameSize, 480)
    }

    func testSuppressesWhiteNoise() throws {
        let denoiser = try RNNoiseDenoiser(
            model: try RNNoiseModel.bundled()
        )
        var rng = SplitMix64(seed: 42)
        let frames = 200 // 2 s
        var inEnergy: Float = 0
        var outEnergy: Float = 0
        var frame = [Float](repeating: 0, count: frameSize)

        for index in 0..<frames {
            for i in frame.indices {
                frame[i] = 0.1 * rng.nextSignedUnit()
            }
            let input = energy(frame)
            let vad = frame.withUnsafeMutableBufferPointer {
                denoiser.process($0)
            }
            XCTAssert((0...1).contains(vad))
            // Skip warm-up while the recurrent state settles.
            guard index >= 50 else { continue }
            inEnergy += input
            outEnergy += energy(frame)
        }
        XCTAssertLessThan(outEnergy, inEnergy * 0.1)
    }

    func testZeroStrengthIsInputDelayedByLatency() throws {
        let denoiser = try RNNoiseDenoiser(
            model: try RNNoiseModel.bundled()
        )
        var rng = SplitMix64(seed: 7)
        let input = (0..<(frameSize * 6)).map { _ in
            0.1 * rng.nextSignedUnit()
        }
        var output = input
        for start in stride(
            from: 0, to: output.count, by: frameSize
        ) {
            output.withUnsafeMutableBufferPointer { all in
                let frame = UnsafeMutableBufferPointer(
                    rebasing: all[start..<start + frameSize]
                )
                denoiser.process(frame, strength: 0)
            }
        }
        let latency = RNNoiseDenoiser.latency
        for i in latency..<output.count {
            XCTAssertEqual(output[i], input[i - latency])
        }
    }

    func testHalfStrengthRemovesLessNoise() throws {
        let full = try noiseEnergyRatio(strength: 1)
        let half = try noiseEnergyRatio(strength: 0.5)
        XCTAssertLessThan(full, half)
        XCTAssertLessThan(half, 1)
    }

    func testEmptyWeightsThrow() {
        XCTAssertThrowsError(
            try RNNoiseModel(weights: Data())
        ) { error in
            XCTAssertEqual(
                error as? RNNoiseError,
                .invalidWeights
            )
        }
    }

    func testGarbageWeightsThrow() throws {
        let model = try RNNoiseModel(
            weights: Data(repeating: 7, count: 1_024)
        )
        XCTAssertThrowsError(
            try RNNoiseDenoiser(model: model)
        )
    }

    /// Output over input energy for white noise, after
    /// warm-up.
    private func noiseEnergyRatio(
        strength: Float
    ) throws -> Float {
        let denoiser = try RNNoiseDenoiser(
            model: try RNNoiseModel.bundled()
        )
        var rng = SplitMix64(seed: 42)
        var inEnergy: Float = 0
        var outEnergy: Float = 0
        var frame = [Float](repeating: 0, count: frameSize)
        for index in 0..<200 {
            for i in frame.indices {
                frame[i] = 0.1 * rng.nextSignedUnit()
            }
            let input = energy(frame)
            frame.withUnsafeMutableBufferPointer {
                denoiser.process($0, strength: strength)
            }
            guard index >= 50 else { continue }
            inEnergy += input
            outEnergy += energy(frame)
        }
        return outEnergy / inEnergy
    }

    private func energy(_ samples: [Float]) -> Float {
        samples.reduce(0) { $0 + $1 * $1 }
    }
}

/// Deterministic noise so the test is reproducible.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func nextSignedUnit() -> Float {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Float(z >> 40) / Float(1 << 23) - 1
    }
}
