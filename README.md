# RNNoiseKit

Swift package for [xiph/rnnoise](https://github.com/xiph/rnnoise), the
recurrent neural network noise suppressor. Real-time safe, no
dependencies, works on iOS, macOS, watchOS and visionOS.

## Requirements

- iOS 16, macOS 13, watchOS 9, visionOS 1
- Swift 5.9+
- 48 kHz mono audio, in 480-sample (10 ms) frames

## Installation

In Xcode: **File → Add Package Dependencies…** and enter
`https://github.com/rqbctg/RNNoiseKit`.

Or in `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/rqbctg/RNNoiseKit",
        from: "1.1.0"
    ),
],
targets: [
    .target(name: "App", dependencies: ["RNNoiseKit"]),
]
```

## Usage

```swift
import RNNoiseKit

// Load once and share: the weights are read-only.
let model = try RNNoiseModel.bundled()
let denoiser = try RNNoiseDenoiser(model: model)

// One frame of RNNoiseDenoiser.frameSize (480) samples
// in [-1, 1], processed in place.
var frame = [Float](repeating: 0, count: RNNoiseDenoiser.frameSize)
let voiceProbability = frame.withUnsafeMutableBufferPointer {
    denoiser.process($0)
}

// Softer suppression: blend in 40% of the original voice.
frame.withUnsafeMutableBufferPointer {
    denoiser.process($0, strength: 0.6)
}
```

- `process(_:strength:)` does not allocate or lock, so it is safe to call from
  a real-time audio render callback.
- Use one `RNNoiseDenoiser` per stream, from one thread. Feed frames in
  order: it keeps state between frames.
- Output is delayed by `RNNoiseDenoiser.latency` samples (960, or
  20 ms), measured by cross-correlating input and output.
- `strength` (0–1, default 1) blends the denoised signal with the
  time-aligned original. Lower values remove less noise but keep the
  voice more natural, which helps with singing.
- Audio at other sample rates must be resampled to 48 kHz first.
- Host buffers are rarely multiples of 480 samples. Collect samples
  into 480-sample frames before calling `process(_:strength:)`.

## How the model is bundled

Upstream ships its model as a 78 MB C source file of float literals.
RNNoiseKit compiles it once into a 14 MB binary blob
(`Sources/RNNoiseKit/Resources/rnnoise_weights.bin`) and builds the C
library with `USE_WEIGHTS_FILE`, so the large file never enters git.

## Updating rnnoise

```sh
scripts/update.sh          # latest upstream main
scripts/update.sh <ref>    # a specific commit or tag
```

The script clones rnnoise, downloads the model and checks its SHA-256,
rebuilds the weights blob and re-vendors the C sources. The pinned
upstream commit and model hash are in `UPSTREAM`. Do not edit
`Sources/CRNNoise` by hand.

## License

BSD 3-Clause, the same license as upstream rnnoise (© Jean-Marc
Valin, Amazon, Mozilla, Xiph.Org Foundation, Mark Borgerding). See
`LICENSE`.
