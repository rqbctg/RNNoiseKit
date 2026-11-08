import CRNNoise

/// Streaming RNNoise noise suppressor for 48 kHz mono audio.
///
/// Feed consecutive ``frameSize``-sample frames in order; the
/// denoiser keeps state between frames and adds one frame of
/// latency. Not thread-safe: use one instance per stream from
/// one thread. ``process(_:)`` does not allocate or lock, so it
/// is safe to call from a real-time render callback.
public final class RNNoiseDenoiser {
    /// Samples per frame (10 ms at 48 kHz).
    public static let frameSize = Int(rnnoise_get_frame_size())
    /// The only sample rate the network was trained for.
    public static let sampleRate: Double = 48_000

    /// rnnoise works on 16-bit PCM scale, not [-1, 1].
    private static let pcmScale: Float = 32_768

    private let model: RNNoiseModel
    private let state: OpaquePointer

    /// Creates a denoiser that uses `model`'s weights.
    public init(model: RNNoiseModel) throws {
        guard let state = rnnoise_create(model.pointer) else {
            throw RNNoiseError.invalidWeights
        }
        self.model = model
        self.state = state
    }

    deinit {
        rnnoise_destroy(state)
    }

    /// Denoises one frame in place.
    ///
    /// - Parameter frame: exactly ``frameSize`` samples in
    ///   [-1, 1]. The output is delayed by one frame.
    /// - Returns: voice activity probability in [0, 1].
    @discardableResult
    public func process(
        _ frame: UnsafeMutableBufferPointer<Float>
    ) -> Float {
        precondition(
            frame.count == Self.frameSize,
            "RNNoise frame must be \(Self.frameSize) samples"
        )
        guard let base = frame.baseAddress else { return 0 }
        for i in frame.indices { frame[i] *= Self.pcmScale }
        // In place is safe: rnnoise copies `in` before it
        // writes `out`.
        let vad = rnnoise_process_frame(state, base, base)
        for i in frame.indices { frame[i] /= Self.pcmScale }
        return vad
    }
}
