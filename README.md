# MNN-LLM Flutter

On-device Large Language Model inference for Flutter using MNN backend and Flutter Rust Bridge.

## Features

- 🚀 On-device inference (no cloud required)
- 📱 Android arm64 support
- 🍎 iOS support (device and simulator)
- 🔄 Streaming text generation
- 👁️ Vision model support (image input)
- 💬 Chat interface with conversation history
- 🧠 Memory-mapped file loading for reduced RAM usage
- 🦀 Type-safe Rust FFI via Flutter Rust Bridge

## Quick Start

```bash
# Clone the repository
git clone https://github.com/Proxie-Studio/llm-flutter.git
cd llm-flutter

# Build for your platform
./scripts/build.sh ios-sim      # iOS Simulator
./scripts/build.sh ios-device   # iOS Device
./scripts/build.sh android      # Android arm64

# Run
cd ios && pod install && cd ..  # iOS only
flutter run
```

## Prerequisites

### All Platforms
- Flutter SDK 3.10+
- Rust toolchain (https://rustup.rs)
- CMake (`brew install cmake` on macOS)
- Flutter Rust Bridge CLI: `cargo install flutter_rust_bridge_codegen`

### iOS
- Xcode 15+ with command line tools
- iOS deployment target: 12.0+
- Add Rust targets:
  ```bash
  rustup target add aarch64-apple-ios        # Device
  rustup target add aarch64-apple-ios-sim    # Simulator
  ```

### Android
- Android NDK r26+ (set `ANDROID_NDK` or `NDK_HOME` env var)
- Add Rust target:
  ```bash
  rustup target add aarch64-linux-android
  ```

## Build System

The unified build script handles everything: MNN compilation → Rust compilation → FRB codegen → Library copying.

```bash
./scripts/build.sh <platform> [options]
```

### Platforms

| Platform | Description | Output |
|----------|-------------|--------|
| `android` | Android arm64-v8a | `android/app/src/main/jniLibs/` |
| `ios-sim` | iOS Simulator (arm64 Mac) | `ios/Frameworks/` |
| `ios-device` | iOS Device (arm64) | `ios/Frameworks/` |
| `all` | Build all platforms | All locations |

### Options

| Option | Description |
|--------|-------------|
| `--skip-mnn` | Skip MNN compilation (reuse existing) |
| `--skip-rust` | Skip Rust compilation (reuse existing) |
| `--skip-frb` | Skip FRB codegen (reuse existing bindings) |
| `--clean` | Clean before building |

### Other Commands

```bash
./scripts/build.sh generate    # Run FRB codegen only
./scripts/build.sh clean       # Clean all build artifacts
```

### Examples

```bash
# Full build from scratch
./scripts/build.sh ios-sim

# Rebuild only Rust after code changes
./scripts/build.sh ios-sim --skip-mnn

# Regenerate Dart bindings only
./scripts/build.sh generate

# Clean everything and rebuild
./scripts/build.sh android --clean
```

## Project Structure

```
llm-flutter/
├── scripts/
│   └── build.sh                    # Unified build script
├── lib/
│   ├── main.dart                   # Flutter chat UI
│   ├── llm_flutter.dart            # Library exports
│   └── src/rust/                   # Generated FRB Dart bindings
├── rust/mnn_llm/
│   ├── src/
│   │   ├── lib.rs                  # Rust library entry
│   │   ├── api.rs                  # FRB API definitions
│   │   └── llm.rs                  # MNN LLM wrapper
│   ├── cpp/
│   │   ├── llm_c_api.cpp           # C++ wrapper for MNN
│   │   └── llm_c_api.h             # C API header
│   ├── MNN/                        # MNN submodule
│   ├── flutter_rust_bridge.yaml    # FRB config
│   └── scripts/
│       ├── build.sh                # Android/host builds
│       └── build_ios.sh            # iOS builds
├── ios/
│   ├── Frameworks/                 # MNN.framework + libllm.a
│   └── Podfile
└── android/
    └── app/src/main/jniLibs/       # .so libraries
```

## Build Outputs

### iOS

After building for iOS, the following are copied to `ios/Frameworks/`:

| File | Description |
|------|-------------|
| `MNN.framework` | MNN framework with Metal support |
| `libllm.a` | Static library (Rust + C++ wrapper) |

The Podfile links these automatically.

### Android

After building for Android, the following are copied to `android/app/src/main/jniLibs/arm64-v8a/`:

| File | Description |
|------|-------------|
| `libMNN.so` | MNN core library |
| `libllm.so` | LLM engine |
| `libMNN_Express.so` | MNN Express API |
| `libmnn_llm_frb.so` | Rust FRB library |
| `libc++_shared.so` | C++ runtime |

## API Usage

### Initialize

```dart
import 'package:llm_flutter/llm_flutter.dart';

// Call once at app startup
await RustLib.init();
```

### Create and Load Model

```dart
final llm = MnnLlm.create(
  configPath: '/path/to/model/llm_config.json',
  useMmap: true,  // Memory-map for reduced RAM
);

await llm.load();
await llm.tune();  // Warmup run
```

### Generate Text

```dart
// Blocking generation
final response = await llm.generate(prompt: 'Hello!');

// Streaming generation
llm.generateStream(prompt: 'Tell me a story').listen((chunk) {
  print(chunk);  // Each token as it's generated
});
```

### Vision Models

```dart
// Check if model supports images
if (llm.isVisionModel()) {
  // Set image before generation
  await llm.setImage(imagePath: '/path/to/image.jpg');
  final response = await llm.generate(prompt: 'What is in this image?');
}
```

### Configuration

```dart
// Enable thinking mode (shows reasoning)
await llm.setThinking(enabled: true);

// Get context info
final info = llm.getContextInfo();
print('History: ${info.historyLen} tokens');
print('Context: ${info.contextLen} max');

// Reset conversation
await llm.reset();
```

## Model Setup

### Download Model

Get an MNN-converted model (e.g., Qwen3-0.6B for testing):

```bash
# Example: Download from HuggingFace
huggingface-cli download mnn-team/Qwen3-0.6B-MNN --local-dir ~/Models/Qwen3-0.6B
```

### Copy to Device

**iOS Simulator:**
```bash
# Models go in app's Documents directory
# Use the app's file picker or airdrop
```

**Android:**
```bash
adb push ~/Models/Qwen3-0.6B /data/local/tmp/
adb shell chmod -R 755 /data/local/tmp/Qwen3-0.6B
```

### Model Directory Structure

```
Qwen3-0.6B/
├── llm_config.json    # Model configuration (required)
├── llm.mnn            # Model weights
├── tokenizer.txt      # Tokenizer vocabulary
└── embeddings_bf16.bin # (optional) Embeddings
```

## Troubleshooting

### Build Errors

**MNN build fails:**
```bash
# Clean and retry
./scripts/build.sh clean
./scripts/build.sh ios-sim
```

**Rust build fails with missing symbols:**
```bash
# Ensure MNN was built first
./scripts/build.sh ios-sim  # Full build, not --skip-mnn
```

**FRB codegen fails:**
```bash
# Update flutter_rust_bridge
cargo install flutter_rust_bridge_codegen --force
```

### Runtime Errors

**App crashes on startup (iOS):**
- Check that `MNN.framework` and `libllm.a` are in `ios/Frameworks/`
- Run `pod install` after copying frameworks

**Model not loading:**
- Verify config path points to `llm_config.json`
- Check file permissions on device

**Out of memory:**
- Enable mmap: `useMmap: true`
- Use a smaller model (0.6B or 1.8B)
- Close other apps

### iOS Simulator Specific

**Architecture mismatch:**
```bash
# Ensure you built for simulator, not device
./scripts/build.sh ios-sim  # NOT ios-device
```

**Framework not found:**
```bash
cd ios && pod install && cd ..
```

## Development

### Modifying Rust API

1. Edit `rust/mnn_llm/src/api.rs`
2. Regenerate bindings:
   ```bash
   ./scripts/build.sh generate
   ```
3. Rebuild:
   ```bash
   ./scripts/build.sh ios-sim --skip-mnn
   ```

### Adding New Platforms

The build system supports adding new targets by extending:
- `scripts/build.sh` - Main orchestration
- `rust/mnn_llm/scripts/build_ios.sh` - iOS-specific builds
- `rust/mnn_llm/scripts/build.sh` - Android/host builds

## License

MIT
