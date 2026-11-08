import CRNNoise
import Foundation

/// Read-only RNNoise network weights.
///
/// Load once and share across denoisers: every
/// ``RNNoiseDenoiser`` keeps its model alive, because the C
/// layers point straight into this weight buffer.
public final class RNNoiseModel: @unchecked Sendable {
    // SAFETY: no lock needed. Both fields are set once in init
    // and never mutated; the C code only reads the weights.
    private let weights: UnsafeMutableRawBufferPointer
    let pointer: OpaquePointer

    /// Loads the model weights bundled with this package.
    public static func bundled() throws -> RNNoiseModel {
        guard let url = Bundle.module.url(
            forResource: "rnnoise_weights",
            withExtension: "bin"
        ) else {
            throw RNNoiseError.weightsNotFound
        }
        return try RNNoiseModel(
            weights: Data(contentsOf: url, options: .mappedIfSafe)
        )
    }

    /// Creates a model from a binary weights blob in the
    /// `write_weights` format used by upstream rnnoise.
    public init(weights data: Data) throws {
        guard !data.isEmpty, data.count <= Int(Int32.max) else {
            throw RNNoiseError.invalidWeights
        }
        // Weight arrays are read as float/int8 in place.
        let buffer = UnsafeMutableRawBufferPointer.allocate(
            byteCount: data.count,
            alignment: 64
        )
        buffer.copyBytes(from: data)
        guard let model = rnnoise_model_from_buffer(
            buffer.baseAddress,
            Int32(data.count)
        ) else {
            buffer.deallocate()
            throw RNNoiseError.invalidWeights
        }
        weights = buffer
        pointer = model
    }

    deinit {
        // Not rnnoise_model_free(): rnnoise_model_from_buffer
        // leaves `file` uninitialized, so free would fclose a
        // garbage pointer. The struct is a single malloc.
        free(UnsafeMutableRawPointer(pointer))
        weights.deallocate()
    }
}
