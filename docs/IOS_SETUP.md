# iOS Setup Guide for llm-flutter

This guide explains how to build and run the Flutter LLM app on iOS (simulator and device).

## Prerequisites

1. **Xcode** - Install from App Store
2. **Rust** - Install from https://rustup.rs
3. **CMake** - `brew install cmake`
4. **CocoaPods** - `sudo gem install cocoapods`

## Quick Start (Simulator)

```bash
# 1. Build native libraries for iOS Simulator
./scripts/build_ios.sh --simulator

# 2. Setup Flutter dependencies
flutter pub get
cd ios && pod install && cd ..

# 3. Run on simulator
flutter run
```

## Build Script Options

The `scripts/build_ios.sh` script automates the native library build process:

```bash
# Build for simulator only (default)
./scripts/build_ios.sh --simulator

# Build for physical device only
./scripts/build_ios.sh --device

# Build universal libraries (both simulator and device)
./scripts/build_ios.sh --all

# Clean build (removes previous artifacts)
./scripts/build_ios.sh --simulator --clean

# Skip MNN rebuild (use existing framework)
./scripts/build_ios.sh --simulator --skip-mnn
```

## What the Build Script Does

1. **Builds MNN Framework** - Compiles the MNN neural network library for iOS
2. **Builds Rust FFI Library** - Compiles the Rust wrapper with FFI exports
3. **Copies to ios/Frameworks/** - Places libraries where Xcode can find them
4. **Configures Xcode** - Sets up xcconfig files for linking

## Project Structure

After building, the iOS project will have:

```
ios/
├── Frameworks/
│   ├── MNN.framework/     # MNN neural network framework
│   └── libllm.a           # Rust FFI static library
├── Flutter/
│   ├── Debug.xcconfig     # Includes MNN.xcconfig
│   ├── Release.xcconfig   # Includes MNN.xcconfig
│   └── MNN.xcconfig       # Linker flags for native libs
└── Podfile                # CocoaPods configuration
```

## Manual Build Steps (if needed)

If the script doesn't work, you can build manually:

### 1. Build MNN Framework

```bash
cd rust/mnn_llm/MNN
mkdir build_ios_sim && cd build_ios_sim

cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DMNN_BUILD_SHARED_LIBS=OFF \
    -DMNN_SEP_BUILD=OFF \
    -DMNN_BUILD_LLM=ON \
    -DMNN_AAPL_FMWK=ON \
    -DMNN_METAL=ON

cmake --build . -j$(sysctl -n hw.ncpu)

# Copy framework
mkdir -p ../../scripts/mnn_lib_ios/simulator
cp -R MNN.framework ../../scripts/mnn_lib_ios/simulator/
```

### 2. Build Rust Library

```bash
cd rust/mnn_llm

# Set MNN paths
export MNN_LIB_PATH="$PWD/scripts/mnn_lib_ios/simulator/MNN.framework"
export MNN_INCLUDE_PATH="$PWD/scripts/mnn_lib_ios/simulator/MNN.framework/Headers"

# Build with proper flags (CRITICAL: embed-bitcode=no avoids LLVM version mismatch)
RUSTFLAGS="-C link-dead-code -C embed-bitcode=no -C codegen-units=1 -C lto=no" \
cargo build --release --target aarch64-apple-ios-sim
```

### 3. Copy to iOS Frameworks

```bash
mkdir -p ios/Frameworks
cp rust/mnn_llm/scripts/mnn_lib_ios/simulator/MNN.framework ios/Frameworks/
cp rust/mnn_llm/target/aarch64-apple-ios-sim/release/libllm.a ios/Frameworks/
```

### 4. Create MNN.xcconfig

Create `ios/Flutter/MNN.xcconfig`:
```
FRAMEWORK_SEARCH_PATHS = $(inherited) $(PROJECT_DIR)/Frameworks
LIBRARY_SEARCH_PATHS = $(inherited) $(PROJECT_DIR)/Frameworks
OTHER_LDFLAGS = $(inherited) -force_load $(PROJECT_DIR)/Frameworks/libllm.a -framework MNN -lc++
EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64
```

Add to `ios/Flutter/Debug.xcconfig` and `ios/Flutter/Release.xcconfig`:
```
#include "MNN.xcconfig"
```

## Troubleshooting

### "Failed to lookup symbol 'llm_create_ffi'"

This means the FFI symbols aren't being linked. Check:

1. **Verify symbols exist in libllm.a:**
   ```bash
   nm ios/Frameworks/libllm.a | grep "T _llm_.*_ffi"
   ```
   You should see ~20 FFI functions listed.

2. **If no symbols, rebuild Rust with correct flags:**
   ```bash
   RUSTFLAGS="-C link-dead-code -C embed-bitcode=no" cargo build ...
   ```

3. **Check force_load is in build settings:**
   ```bash
   cd ios && xcodebuild -showBuildSettings | grep OTHER_LDFLAGS
   ```

### Build fails with LLVM version mismatch

The Rust compiler uses a newer LLVM than Xcode. Fix by adding `-C embed-bitcode=no` to RUSTFLAGS.

### Simulator shows x86_64 errors

Ensure `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64` is set. Our libraries are arm64 only.

### Model not found

The app looks for the model at the path specified in `lib/main.dart`. Update `_modelPath` to point to your model location:

```dart
String get _modelPath {
  if (Platform.isAndroid) {
    return '/data/local/tmp/YourModel/config.json';
  } else {
    return '/Users/yourname/path/to/YourModel/config.json';
  }
}
```

## Building for Physical Device

For App Store / TestFlight distribution:

```bash
# Build universal libraries
./scripts/build_ios.sh --all

# Build release IPA
flutter build ipa
```

Note: Physical devices require code signing. Configure in Xcode or use `--export-options-plist`.
