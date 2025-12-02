#!/bin/bash
# Flutter Rust Bridge Build Script
# Builds MNN-LLM Rust library for iOS and Android using flutter_rust_bridge

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/rust/mnn_llm"
IOS_DIR="$PROJECT_ROOT/ios"
ANDROID_DIR="$PROJECT_ROOT/android"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Build MNN-LLM with Flutter Rust Bridge for mobile platforms"
    echo ""
    echo "Options:"
    echo "  --ios-sim       Build for iOS Simulator (arm64)"
    echo "  --ios-device    Build for iOS Device (arm64)"
    echo "  --android       Build for Android (arm64-v8a)"
    echo "  --all           Build for all platforms"
    echo "  --generate      Only regenerate FRB Dart bindings"
    echo "  --clean         Clean build artifacts"
    echo "  --skip-mnn      Skip MNN framework build (use existing)"
    echo "  --help          Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --ios-sim              # Build for iOS Simulator"
    echo "  $0 --android              # Build for Android"
    echo "  $0 --all                  # Build everything"
    echo "  $0 --generate             # Just regenerate Dart bindings"
}

# Options
BUILD_IOS_SIM=false
BUILD_IOS_DEVICE=false
BUILD_ANDROID=false
GENERATE_ONLY=false
CLEAN_BUILD=false
SKIP_MNN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --ios-sim) BUILD_IOS_SIM=true; shift ;;
        --ios-device) BUILD_IOS_DEVICE=true; shift ;;
        --android) BUILD_ANDROID=true; shift ;;
        --all)
            BUILD_IOS_SIM=true
            BUILD_IOS_DEVICE=true
            BUILD_ANDROID=true
            shift ;;
        --generate) GENERATE_ONLY=true; shift ;;
        --clean) CLEAN_BUILD=true; shift ;;
        --skip-mnn) SKIP_MNN=true; shift ;;
        --help) usage; exit 0 ;;
        *) print_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# Default to iOS sim if nothing specified
if [[ "$BUILD_IOS_SIM" == "false" && "$BUILD_IOS_DEVICE" == "false" && "$BUILD_ANDROID" == "false" && "$GENERATE_ONLY" == "false" ]]; then
    BUILD_IOS_SIM=true
fi

echo "========================================"
echo "  MNN-LLM Flutter Rust Bridge Builder"
echo "========================================"
echo ""

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v rustc &> /dev/null; then
        print_error "Rust not found. Install from https://rustup.rs"
        exit 1
    fi
    
    if ! command -v flutter &> /dev/null; then
        print_error "Flutter not found"
        exit 1
    fi
    
    if ! command -v flutter_rust_bridge_codegen &> /dev/null; then
        print_warning "flutter_rust_bridge_codegen not found, installing..."
        cargo install flutter_rust_bridge_codegen@2.11.1
    fi
    
    # Check iOS targets
    if [[ "$BUILD_IOS_SIM" == "true" ]]; then
        if ! rustup target list --installed | grep -q "aarch64-apple-ios-sim"; then
            print_warning "Adding iOS Simulator target..."
            rustup target add aarch64-apple-ios-sim
        fi
    fi
    
    if [[ "$BUILD_IOS_DEVICE" == "true" ]]; then
        if ! rustup target list --installed | grep -q "aarch64-apple-ios"; then
            print_warning "Adding iOS Device target..."
            rustup target add aarch64-apple-ios
        fi
    fi
    
    if [[ "$BUILD_ANDROID" == "true" ]]; then
        if ! rustup target list --installed | grep -q "aarch64-linux-android"; then
            print_warning "Adding Android target..."
            rustup target add aarch64-linux-android
        fi
    fi
    
    print_status "Prerequisites OK"
}

# Clean build artifacts
clean_build() {
    print_info "Cleaning build artifacts..."
    cd "$RUST_DIR"
    cargo clean
    rm -rf "$IOS_DIR/Frameworks/libllm.a" 2>/dev/null || true
    rm -rf "$PROJECT_ROOT/lib/src/rust/"*.dart 2>/dev/null || true
    print_status "Cleaned"
}

# Build MNN Framework for iOS
build_mnn_ios() {
    local target=$1  # "simulator" or "device"
    local mnn_output="$RUST_DIR/scripts/mnn_lib_ios/$target/MNN.framework"
    
    if [[ -d "$mnn_output" && "$SKIP_MNN" == "true" ]]; then
        print_status "Using existing MNN framework for $target"
        return
    fi
    
    print_info "Building MNN framework for iOS $target..."
    
    cd "$RUST_DIR/MNN"
    
    local build_dir="build_ios_$target"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    local cmake_args=(
        -DCMAKE_BUILD_TYPE=Release
        -DMNN_BUILD_LLM=ON
        -DMNN_LOW_MEMORY=ON
        -DMNN_SUPPORT_TRANSFORMER_FUSE=ON
        -DMNN_BUILD_OPENCV=ON
        -DMNN_IMGCODECS=ON
        -DMNN_BUILD_TOOLS=OFF
        -DMNN_BUILD_DEMO=OFF
        -DMNN_AAPL_FMWK=ON
        -DMNN_METAL=ON
        -DMNN_COREML=ON
    )
    
    if [[ "$target" == "simulator" ]]; then
        cmake .. "${cmake_args[@]}" \
            -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_SYSROOT=iphonesimulator \
            -DCMAKE_OSX_ARCHITECTURES=arm64
    else
        cmake .. "${cmake_args[@]}" \
            -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_SYSROOT=iphoneos \
            -DCMAKE_OSX_ARCHITECTURES=arm64
    fi
    
    cmake --build . -j$(sysctl -n hw.ncpu)
    
    mkdir -p "$(dirname "$mnn_output")"
    cp -R MNN.framework "$mnn_output"
    
    print_status "MNN framework built for iOS $target"
    cd "$PROJECT_ROOT"
}

# Generate FRB bindings
generate_frb_bindings() {
    print_info "Generating Flutter Rust Bridge bindings..."
    
    cd "$RUST_DIR"
    
    # Use iOS simulator MNN for codegen (need headers for compilation)
    local mnn_path="$RUST_DIR/scripts/mnn_lib_ios/simulator/MNN.framework"
    
    if [[ ! -d "$mnn_path" ]]; then
        # Try device
        mnn_path="$RUST_DIR/scripts/mnn_lib_ios/device/MNN.framework"
    fi
    
    if [[ ! -d "$mnn_path" ]]; then
        # Try Android
        mnn_path="$RUST_DIR/scripts/mnn_lib_android_arm64-v8a"
        export MNN_LIB_PATH="$mnn_path/lib"
        export MNN_INCLUDE_PATH="$mnn_path/include"
    else
        export MNN_LIB_PATH="$mnn_path"
        export MNN_INCLUDE_PATH="$mnn_path/Headers"
    fi
    
    flutter_rust_bridge_codegen generate
    
    print_status "FRB bindings generated"
    cd "$PROJECT_ROOT"
}

# Build Rust library for iOS
build_rust_ios() {
    local target=$1  # "simulator" or "device"
    
    print_info "Building Rust library for iOS $target..."
    
    cd "$RUST_DIR"
    
    local rust_target
    local mnn_path
    
    if [[ "$target" == "simulator" ]]; then
        rust_target="aarch64-apple-ios-sim"
        mnn_path="$RUST_DIR/scripts/mnn_lib_ios/simulator/MNN.framework"
    else
        rust_target="aarch64-apple-ios"
        mnn_path="$RUST_DIR/scripts/mnn_lib_ios/device/MNN.framework"
    fi
    
    MNN_LIB_PATH="$mnn_path" \
    MNN_INCLUDE_PATH="$mnn_path/Headers" \
    RUSTFLAGS="-C link-dead-code -C embed-bitcode=no" \
    cargo build --release --target "$rust_target"
    
    print_status "Rust library built for iOS $target"
    cd "$PROJECT_ROOT"
}

# Build Rust library for Android
build_rust_android() {
    print_info "Building Rust library for Android..."
    
    cd "$RUST_DIR"
    
    local mnn_path="$RUST_DIR/scripts/mnn_lib_android_arm64-v8a"
    
    if [[ ! -d "$mnn_path" ]]; then
        print_error "Android MNN libraries not found at $mnn_path"
        exit 1
    fi
    
    # Set up Android NDK
    if [[ -z "$ANDROID_NDK_HOME" ]]; then
        # Try common locations
        if [[ -d "$HOME/Library/Android/sdk/ndk" ]]; then
            export ANDROID_NDK_HOME=$(ls -d "$HOME/Library/Android/sdk/ndk"/*/ 2>/dev/null | head -1)
        fi
    fi
    
    if [[ -z "$ANDROID_NDK_HOME" ]]; then
        print_error "ANDROID_NDK_HOME not set"
        exit 1
    fi
    
    MNN_LIB_PATH="$mnn_path/lib" \
    MNN_INCLUDE_PATH="$mnn_path/include" \
    cargo build --release --target aarch64-linux-android
    
    print_status "Rust library built for Android"
    cd "$PROJECT_ROOT"
}

# Copy iOS libraries to Frameworks
copy_ios_libs() {
    local target=$1
    
    print_info "Copying iOS $target libraries..."
    
    local rust_target
    local mnn_path
    
    if [[ "$target" == "simulator" ]]; then
        rust_target="aarch64-apple-ios-sim"
        mnn_path="$RUST_DIR/scripts/mnn_lib_ios/simulator/MNN.framework"
    else
        rust_target="aarch64-apple-ios"
        mnn_path="$RUST_DIR/scripts/mnn_lib_ios/device/MNN.framework"
    fi
    
    mkdir -p "$IOS_DIR/Frameworks"
    
    # Copy Rust static library
    cp "$RUST_DIR/target/$rust_target/release/libllm.a" "$IOS_DIR/Frameworks/"
    
    # Copy MNN framework
    rm -rf "$IOS_DIR/Frameworks/MNN.framework"
    cp -R "$mnn_path" "$IOS_DIR/Frameworks/"
    
    print_status "iOS libraries copied"
}

# Copy Android libraries
copy_android_libs() {
    print_info "Copying Android libraries..."
    
    local jni_dir="$ANDROID_DIR/app/src/main/jniLibs/arm64-v8a"
    mkdir -p "$jni_dir"
    
    # Copy Rust library
    cp "$RUST_DIR/target/aarch64-linux-android/release/libllm.so" "$jni_dir/"
    
    # Copy MNN libraries
    local mnn_path="$RUST_DIR/scripts/mnn_lib_android_arm64-v8a/lib"
    cp "$mnn_path"/*.so "$jni_dir/" 2>/dev/null || true
    
    print_status "Android libraries copied"
}

# Setup iOS xcconfig
setup_ios_xcconfig() {
    print_info "Setting up iOS build configuration..."
    
    local xcconfig="$IOS_DIR/Flutter/MNN.xcconfig"
    
    cat > "$xcconfig" << 'EOF'
// MNN-LLM Build Configuration
// Auto-generated by build_frb.sh

// Force load static library to preserve FFI symbols
OTHER_LDFLAGS = $(inherited) -force_load $(PROJECT_DIR)/Frameworks/libllm.a -framework MNN -lc++

// Build only for arm64 (our native libs are arm64 only)
EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64
EOF

    # Include in Debug and Release configs
    for config in Debug Release; do
        local flutter_config="$IOS_DIR/Flutter/Flutter-$config.xcconfig"
        if [[ -f "$flutter_config" ]]; then
            if ! grep -q "MNN.xcconfig" "$flutter_config"; then
                echo '#include "MNN.xcconfig"' >> "$flutter_config"
            fi
        fi
    done
    
    print_status "iOS xcconfig setup complete"
}

# Run flutter pub get and pod install
setup_flutter() {
    print_info "Setting up Flutter dependencies..."
    
    cd "$PROJECT_ROOT"
    flutter pub get
    
    if [[ "$BUILD_IOS_SIM" == "true" || "$BUILD_IOS_DEVICE" == "true" ]]; then
        cd "$IOS_DIR"
        pod install
    fi
    
    cd "$PROJECT_ROOT"
    print_status "Flutter setup complete"
}

# Main build flow
main() {
    check_prerequisites
    
    if [[ "$CLEAN_BUILD" == "true" ]]; then
        clean_build
    fi
    
    # Build MNN if needed
    if [[ "$BUILD_IOS_SIM" == "true" ]]; then
        build_mnn_ios "simulator"
    fi
    
    if [[ "$BUILD_IOS_DEVICE" == "true" ]]; then
        build_mnn_ios "device"
    fi
    
    # Generate FRB bindings
    generate_frb_bindings
    
    if [[ "$GENERATE_ONLY" == "true" ]]; then
        print_status "FRB bindings generation complete!"
        exit 0
    fi
    
    # Build Rust libraries
    if [[ "$BUILD_IOS_SIM" == "true" ]]; then
        build_rust_ios "simulator"
        copy_ios_libs "simulator"
    fi
    
    if [[ "$BUILD_IOS_DEVICE" == "true" ]]; then
        build_rust_ios "device"
        copy_ios_libs "device"
    fi
    
    if [[ "$BUILD_ANDROID" == "true" ]]; then
        build_rust_android
        copy_android_libs
    fi
    
    # Setup configurations
    if [[ "$BUILD_IOS_SIM" == "true" || "$BUILD_IOS_DEVICE" == "true" ]]; then
        setup_ios_xcconfig
    fi
    
    setup_flutter
    
    echo ""
    echo "========================================"
    print_status "Build complete!"
    echo "========================================"
    echo ""
    echo "Next steps:"
    if [[ "$BUILD_IOS_SIM" == "true" ]]; then
        echo "  • iOS Simulator: flutter run"
    fi
    if [[ "$BUILD_IOS_DEVICE" == "true" ]]; then
        echo "  • iOS Device: flutter run --release"
    fi
    if [[ "$BUILD_ANDROID" == "true" ]]; then
        echo "  • Android: flutter run"
    fi
}

main
