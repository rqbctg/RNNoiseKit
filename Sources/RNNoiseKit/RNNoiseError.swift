/// Failures when loading the RNNoise model or creating a denoiser.
public enum RNNoiseError: Error, Equatable, Sendable {
    /// The bundled weights file is missing from the package bundle.
    case weightsNotFound
    /// The weights blob is empty or could not be parsed.
    case invalidWeights
}
