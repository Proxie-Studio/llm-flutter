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
# Build for iOS Simulator
./scripts/build_flutter.sh ios-sim
flutter run

# Build for Android
./scripts/build_flutter.sh android
flutter build apk --release
```

## Prerequisites

- Flutter SDK 3.10+
- Rust toolchain (https://rustup.rs)
- For iOS: Xcode 15+, CMake (`brew install cmake`)
- For Android: Android NDK r26+
- ~4GB storage for model weights

## Usage

```dart
import 'package:llm_flutter/llm_flutter.dart';

// Initialize
await RustLib.init(externalLibrary: await _loadLibrary());

// Create and load model
final llm = MnnLlm.create(configPath: '/path/to/model');
await llm.load();
await llm.tune();

// Stream response
llm.generateStream(prompt: 'Hello!').listen((chunk) {
  print(chunk);
});
```

## Documentation

- [Flutter Rust Bridge Setup](docs/FLUTTER_RUST_BRIDGE.md) - Complete FRB integration guide
- [iOS Setup](docs/IOS_SETUP.md) - iOS-specific instructions

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
    └── rust/                   # Generated Flutter Rust Bridge bindings
        ├── api.dart             # Dart API classes
        ├── frb_generated.dart   # FRB runtime
        └── frb_generated.io.dart # Platform-specific code

rust/mnn_llm/
├── src/
│   ├── lib.rs                  # Rust library
│   ├── api.rs                  # Flutter Rust Bridge API
│   ├── llm.rs                  # LLM wrapper
│   └── frb_generated.rs        # Generated FRB code
├── flutter_rust_bridge.yaml    # FRB configuration
└── scripts/
    └── build.sh               # MNN & Rust build script

scripts/
└── build_flutter.sh            # Flutter build script (iOS/Android)

android/app/src/main/jniLibs/arm64-v8a/
├── libMNN.so                  # MNN core
├── libMNN_Express.so          # MNN Express API
├── libMNNOpenCV.so            # OpenCV support
└── libllm.so                  # Rust FRB library
```

## API Usage

### Basic Generation

```dart
import 'package:llm_flutter/llm_flutter.dart';

// Initialize FRB (call once at startup)
await RustLib.init(externalLibrary: await _loadLibrary());

// Create LLM instance
final llm = MnnLlm.create(configPath: '/path/to/llm_config.json');

// Load model
await llm.load();
await llm.tune();

// Generate response
final response = await llm.generate(prompt: 'Hello, how are you?');
print(response);
```

### Streaming Generation

```dart
// Stream tokens as they're generated
llm.generateStream(prompt: 'Tell me a story').listen((chunk) {
  print(chunk);
});
```

### Configuration

```dart
// Configure model options
await llm.setConfig(configJson: jsonEncode({
  'use_mmap': true,           // Memory-map model files
  'tmp_path': '/tmp/mnn',     // Cache directory
}));

// Enable thinking mode (chain-of-thought)
await llm.setThinking(enabled: true);
```

## Regenerating FRB Bindings

If you modify the Rust API (`rust/mnn_llm/src/api.rs`):

```bash
./scripts/build_flutter.sh generate
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
