# MNN-LLM Flutter Integration

On-device Large Language Model inference for Flutter using MNN backend and Flutter Rust Bridge.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App (Dart)                    │
├─────────────────────────────────────────────────────────┤
│              Flutter Rust Bridge (Generated)             │
├─────────────────────────────────────────────────────────┤
│                   Rust API (api.rs)                      │
│              MnnLlm wrapper with async/stream            │
├─────────────────────────────────────────────────────────┤
│                 Rust LLM Core (llm.rs)                   │
│              C++ bindings via bindgen                    │
├─────────────────────────────────────────────────────────┤
│                  MNN C++ Framework                       │
│         Metal/CoreML (iOS) | OpenCL/Vulkan (Android)    │
└─────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

1. **Rust** (with rustup): https://rustup.rs
2. **Flutter**: https://flutter.dev/docs/get-started/install
3. **Xcode** (for iOS): Install from App Store
4. **Android NDK** (for Android): Via Android Studio SDK Manager

### Build & Run

```bash
# iOS Simulator
./scripts/build_flutter.sh ios-sim
flutter run

# iOS Device
./scripts/build_flutter.sh ios-device
flutter run --release

# Android
./scripts/build_flutter.sh android
flutter build apk --release

# All platforms
./scripts/build_flutter.sh all
```

## Project Structure

```
llm-flutter/
├── lib/
│   ├── main.dart                 # Flutter app entry
│   ├── llm_flutter.dart          # Library exports
│   └── src/rust/                 # Generated FRB bindings
│       ├── api.dart              # Dart API classes
│       ├── frb_generated.dart    # FRB runtime
│       └── frb_generated.io.dart # Platform-specific code
├── rust/mnn_llm/
│   ├── src/
│   │   ├── api.rs                # FRB API (main interface)
│   │   ├── llm.rs                # Core LLM implementation
│   │   ├── frb_generated.rs      # Generated FRB code
│   │   └── lib.rs                # Crate root
│   ├── MNN/                      # MNN submodule
│   ├── flutter_rust_bridge.yaml  # FRB configuration
│   └── Cargo.toml                # Rust dependencies
├── ios/
│   ├── Frameworks/               # Native libraries
│   │   ├── libllm.a              # Rust static library
│   │   └── MNN.framework/        # MNN framework
│   └── Flutter/
│       └── MNN.xcconfig          # Build configuration
├── android/
│   └── app/src/main/jniLibs/     # Native libraries
│       └── arm64-v8a/
│           ├── libllm.so
│           └── libMNN*.so
└── scripts/
    └── build_flutter.sh           # Automated build script
```

## API Usage

### Basic Usage

```dart
import 'package:llm_flutter/llm_flutter.dart';

// Initialize (call once at app startup)
await RustLib.init(externalLibrary: await _loadLibrary());

// Create LLM instance
final llm = MnnLlm.create(configPath: '/path/to/model');

// Configure (optional)
await llm.setConfig(configJson: '{"use_mmap": true}');

// Load model
await llm.load();
await llm.tune();

// Generate response (non-streaming)
final response = await llm.generate(prompt: 'Hello!');
print(response);

// Generate response (streaming)
llm.generateStream(prompt: 'Tell me a story').listen((chunk) {
  print(chunk); // Print each token as it arrives
});

// Reset conversation
await llm.reset();
```

### Vision Models

```dart
// Check if model supports vision
final config = llm.dumpConfig();
final isVision = jsonDecode(config)['is_visual'] == true;

// Generate with image (streaming)
llm.visionGenerateStream(
  prompt: 'Describe this image',
  imagePaths: '/path/to/image.jpg',
).listen((chunk) {
  print(chunk);
});

// Multiple images
llm.visionGenerateStream(
  prompt: 'Compare these images',
  imagePaths: 'image1.jpg,image2.jpg',
).listen((chunk) => print(chunk));
```

### Performance Metrics

```dart
final info = await llm.getContextInfo();
if (info != null) {
  print('Prompt tokens: ${info.promptTokens}');
  print('Decode tokens: ${info.decodeTokens}');
  print('Prompt time: ${info.promptUs / 1000}ms');
  print('Decode time: ${info.decodeUs / 1000}ms');
}
```

### Tokenization

```dart
// Encode text to tokens
final tokens = await llm.tokenize(text: 'Hello world');
print('Tokens: $tokens');

// Decode tokens to text
final text = await llm.detokenize(tokens: tokens);
print('Text: $text');
```

## API Reference

### MnnLlm Class

| Method | Description |
|--------|-------------|
| `create(configPath)` | Create LLM instance from config path |
| `load()` | Load model into memory |
| `tune()` | Optimize model for device |
| `setConfig(configJson)` | Set configuration (mmap, tmp_path, etc.) |
| `setThinking(enabled)` | Enable/disable thinking mode |
| `generate(prompt)` | Generate complete response |
| `generateStream(prompt)` | Generate streaming response |
| `visionGenerate(...)` | Vision model response |
| `visionGenerateStream(...)` | Vision model streaming |
| `chat(messagesJson)` | Chat with message history |
| `reset()` | Clear conversation history |
| `tokenize(text)` | Encode text to tokens |
| `detokenize(tokens)` | Decode tokens to text |
| `applyChatTemplate(messagesJson)` | Format messages with template |
| `dumpConfig()` | Get current config as JSON |
| `getContextInfo()` | Get performance metrics |
| `getHistoryLength()` | Get token history length |
| `eraseHistory(begin, end)` | Remove history range |

### ContextInfo Class

| Property | Type | Description |
|----------|------|-------------|
| `promptTokens` | int | Number of prompt tokens |
| `decodeTokens` | int | Number of generated tokens |
| `promptUs` | int | Prompt processing time (μs) |
| `decodeUs` | int | Token generation time (μs) |

## Build Script Options

```bash
./scripts/build_flutter.sh [COMMAND]

Commands:
  ios-sim        Build for iOS Simulator (arm64)
  ios-device     Build for iOS Device (arm64)
  android        Build for Android (arm64-v8a)
  all            Build for all platforms
  generate       Only regenerate FRB Dart bindings
  clean          Clean build artifacts

Examples:
  ./scripts/build_flutter.sh ios-sim
  ./scripts/build_flutter.sh android
  ANDROID_ABI=x86_64 ./scripts/build_flutter.sh android
```

## Configuration

### Model Configuration (llm_config.json)

```json
{
  "llm_model": "model.mnn",
  "llm_weight": "model.mnn.weight",
  "tokenizer_file": "tokenizer.txt",
  "is_visual": false,
  "max_new_tokens": 512,
  "prompt_template": "<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n"
}
```

### Runtime Configuration

```dart
await llm.setConfig(configJson: jsonEncode({
  'use_mmap': true,           // Memory-map model files
  'tmp_path': '/tmp/mnn',     // Cache directory
  'backend': 'metal',         // Backend: metal, opencl, cpu
  'thread_num': 4,            // CPU thread count
}));
```

## Troubleshooting

### iOS: Symbol not found

Ensure `MNN.xcconfig` includes force_load:
```
OTHER_LDFLAGS = $(inherited) -force_load $(PROJECT_DIR)/Frameworks/libllm.a -framework MNN -lc++
```

### iOS: LLVM version mismatch

Build Rust with:
```bash
RUSTFLAGS="-C embed-bitcode=no" cargo build --release --target aarch64-apple-ios-sim
```

### Android: Library not found

Ensure libraries are in `android/app/src/main/jniLibs/arm64-v8a/`:
- libllm.so
- libMNN.so
- libMNN_Express.so

### FRB: Regenerate bindings

```bash
./scripts/build_flutter.sh generate
```

## Supported Platforms

| Platform | Architecture | Backend |
|----------|--------------|---------|
| iOS Simulator | arm64 | Metal |
| iOS Device | arm64 | Metal, CoreML |
| Android | arm64-v8a | OpenCL, Vulkan |
| macOS | arm64, x86_64 | Metal |
| Linux | x86_64 | CPU, Vulkan |
| Windows | x86_64 | CPU, Vulkan |

## License

This project uses:
- MNN: Apache 2.0
- Flutter Rust Bridge: MIT
