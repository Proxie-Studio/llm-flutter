# MNN-LLM Flutter

On-device Large Language Model inference for Flutter using MNN backend.

## Features

- 🚀 On-device inference (no cloud required)
- 📱 Android arm64 support
- 🍎 iOS support (device and simulator)
- 🔄 Streaming text generation
- 💬 Chat interface with Qwen3-4B model
- 🧠 Memory-mapped file loading for reduced RAM usage

## Prerequisites

- Flutter SDK 3.10+
- Rust toolchain
- For Android: Android NDK r26+
- For iOS: Xcode 15+, CMake (`brew install cmake`)
- ~4GB storage for model weights

## Quick Start

### iOS (Simulator)

```bash
# 1. Build native libraries
./scripts/build_ios.sh --simulator

# 2. Setup Flutter
flutter pub get
cd ios && pod install && cd ..

# 3. Run
flutter run
```

See [docs/IOS_SETUP.md](docs/IOS_SETUP.md) for detailed iOS instructions.

### Android

```bash
# 1. Install Rust Android targets
rustup target add aarch64-linux-android

# 2. Build native libraries
cd rust/mnn_llm
./scripts/build_flutter.sh arm64-v8a
cd ../..

# 3. Setup Flutter
flutter pub get

# 4. Run
flutter run
```

### Download Model

Download the Qwen3-4B-Instruct MNN model (~2.7GB):

```bash
# On your Android device or emulator
adb shell mkdir -p /data/local/tmp/Qwen3-4B-Instruct-2507-MNN
adb push /path/to/model/* /data/local/tmp/Qwen3-4B-Instruct-2507-MNN/
```

The model directory should contain:
- `llm_config.json` - Model configuration
- `llm.mnn` - Model weights
- `tokenizer.txt` - Tokenizer vocabulary

### 4. Run the App

```bash
# Get Flutter dependencies
flutter pub get

# Run on Android device/emulator
flutter run
```

## Project Structure

```
lib/
├── main.dart                    # Flutter chat UI
├── llm_flutter.dart            # Library exports
└── src/
    ├── llm.dart                # High-level Dart API
    └── llm_bindings_generated.dart  # Auto-generated FFI bindings

rust/mnn_llm/
├── src/
│   ├── lib.rs                  # Rust library
│   ├── llm.rs                  # LLM wrapper
│   └── ffi.rs                  # C FFI exports
├── include/
│   └── mnn_llm.h              # C header for ffigen
└── scripts/
    └── build_flutter.sh       # Build script

android/app/src/main/jniLibs/arm64-v8a/
├── libc++_shared.so           # C++ runtime
├── libMNN.so                  # MNN core
├── libMNN_Express.so          # MNN Express API
├── libllm.so                  # MNN LLM engine
├── libMNNOpenCV.so            # OpenCV support
└── libmnn_llm_rust.so         # Rust FFI wrapper
```

## API Usage

### Basic Generation

```dart
import 'package:llm_flutter/llm_flutter.dart';

// Create LLM instance
final llm = Llm('/path/to/llm_config.json');

// Load model
llm.load();
llm.tune();

// Generate response
final response = llm.generate('Hello, how are you?');
print(response);

// Cleanup
llm.dispose();
```

### Streaming Generation

```dart
// Stream tokens as they're generated
await for (final token in llm.generateStream('Tell me a story')) {
  stdout.write(token);
}
```

### Configuration

```dart
// Enable memory-mapped loading (reduces RAM usage)
final llm = Llm(
  '/path/to/llm_config.json',
  useMmap: true,
  tmpPath: '/path/to/cache/dir',
);

// Enable thinking mode (chain-of-thought)
llm.setThinking(true);
```

## Regenerating FFI Bindings

If you modify the Rust FFI interface:

```bash
# Regenerate Dart bindings from C header
dart run ffigen --config ffigen.yaml
```

## Troubleshooting

### App crashes on startup
- Ensure all native libraries are in `jniLibs/arm64-v8a/`
- Check library loading order (libc++_shared.so must load first)

### Out of memory errors
- Enable mmap: `Llm(path, useMmap: true)`
- Ensure device has 4GB+ RAM
- Use a smaller model variant

### Model not found
- Verify model path: `/data/local/tmp/Qwen3-4B-Instruct-2507-MNN/llm_config.json`
- Check file permissions: `adb shell chmod -R 755 /data/local/tmp/Qwen3-4B-Instruct-2507-MNN`

### Emulator issues
- Emulators have limited storage; use a real device for best results
- Allocate at least 6GB storage to the emulator AVD

## License

MIT
