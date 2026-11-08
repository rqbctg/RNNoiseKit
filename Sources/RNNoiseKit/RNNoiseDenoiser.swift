import CRNNoise

/// Streaming RNNoise noise suppressor for 48 kHz mono audio.
///
/// Feed consecutive ``frameSize``-sample frames in order; the
/// denoiser keeps state between frames and delays the output
/// by ``latency`` samples. Not thread-safe: use one instance
/// per stream from one thread. ``process(_:strength:)`` does
/// not allocate or lock, so it is safe to call from a
/// real-time render callback.
public final class RNNoiseDenoiser {
    /// Samples per frame (10 ms at 48 kHz).
    public static let frameSize = Int(rnnoise_get_frame_size())
    /// The only sample rate the network was trained for.
    public static let sampleRate: Double = 48_000
    /// Output delay in samples: two frames (20 ms), measured
    /// by cross-correlating input and output.
    public static let latency = 2 * frameSize

    /// rnnoise works on 16-bit PCM scale, not [-1, 1].
    private static let pcmScale: Float = 32_768

    private let model: RNNoiseModel
    private let state: OpaquePointer

    /// Input from two frames ago and one frame ago, so the dry
    /// signal lines up with the denoised output when blending.
    private var dryOlder: UnsafeMutableBufferPointer<Float>
    private var dryOld: UnsafeMutableBufferPointer<Float>
    /// Copy of the frame being processed.
    private var dryCurrent: UnsafeMutableBufferPointer<Float>

    /// Creates a denoiser that uses `model`'s weights.
    public init(model: RNNoiseModel) throws {
        guard let state = rnnoise_create(model.pointer) else {
            throw RNNoiseError.invalidWeights
        }
        self.model = model
        self.state = state
        dryOlder = Self.makeFrame()
        dryOld = Self.makeFrame()
        dryCurrent = Self.makeFrame()
    }

    deinit {
        rnnoise_destroy(state)
        dryOlder.deallocate()
        dryOld.deallocate()
        dryCurrent.deallocate()
    }

    /// Denoises one frame in place.
    ///
    /// - Parameters:
    ///   - frame: exactly ``frameSize`` samples in [-1, 1].
    ///     The output is delayed by ``latency`` samples.
    ///   - strength: how much of the denoised signal to use,
    ///     in [0, 1]. 1 is full RNNoise; lower values blend
    ///     in the time-aligned original, so less noise is
    ///     removed and the voice sounds more natural.
    /// - Returns: voice activity probability in [0, 1].
    @discardableResult
    public func process(
        _ frame: UnsafeMutableBufferPointer<Float>,
        strength: Float = 1
    ) -> Float {
        precondition(
            frame.count == Self.frameSize,
            "RNNoise frame must be \(Self.frameSize) samples"
        )
        guard let base = frame.baseAddress else { return 0 }
        let wet = min(max(strength, 0), 1)
        let dry = 1 - wet

        // Kept every frame, so changing strength never plays
        // stale history.
        _ = dryCurrent.update(fromContentsOf: frame)
        for i in frame.indices { frame[i] *= Self.pcmScale }
        // In place is safe: rnnoise copies `in` before it
        // writes `out`.
        let vad = rnnoise_process_frame(state, base, base)
        let scale = wet / Self.pcmScale
        for i in frame.indices {
            frame[i] = frame[i] * scale + dryOlder[i] * dry
        }

        swap(&dryOlder, &dryOld)
        swap(&dryOld, &dryCurrent)
        return vad
    }

    private static func makeFrame()
        -> UnsafeMutableBufferPointer<Float> {
        let frame = UnsafeMutableBufferPointer<Float>
            .allocate(capacity: frameSize)
        frame.initialize(repeating: 0)
        return frame
    }
}
