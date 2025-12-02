#!/bin/bash
# iOS Build Script for llm-flutter
# Builds MNN framework and Rust FFI library for iOS (device and/or simulator)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/rust/mnn_llm"
IOS_DIR="$PROJECT_ROOT/ios"
FRAMEWORKS_DIR="$IOS_DIR/Frameworks"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --simulator     Build for iOS Simulator (arm64)"
    echo "  --device        Build for iOS Device (arm64)"
    echo "  --all           Build for both simulator and device"
    echo "  --clean         Clean build artifacts before building"
    echo "  --skip-mnn      Skip MNN framework build (use existing)"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --simulator              # Build for simulator only"
    echo "  $0 --device                 # Build for device only"
    echo "  $0 --all                    # Build universal (both)"
    echo "  $0 --simulator --clean      # Clean build for simulator"
}

# Default options
BUILD_SIMULATOR=false
BUILD_DEVICE=false
CLEAN_BUILD=false
SKIP_MNN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --simulator)
            BUILD_SIMULATOR=true
            shift
            ;;
        --device)
            BUILD_DEVICE=true
            shift
            ;;
        --all)
            BUILD_SIMULATOR=true
            BUILD_DEVICE=true
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --skip-mnn)
            SKIP_MNN=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Default to simulator if nothing specified
if [[ "$BUILD_SIMULATOR" == "false" && "$BUILD_DEVICE" == "false" ]]; then
    BUILD_SIMULATOR=true
fi

echo "========================================"
echo "  iOS Build Script for llm-flutter"
echo "========================================"
echo ""
echo "Build targets:"
[[ "$BUILD_SIMULATOR" == "true" ]] && echo "  • iOS Simulator (arm64)"
[[ "$BUILD_DEVICE" == "true" ]] && echo "  • iOS Device (arm64)"
echo ""

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v rustup &> /dev/null; then
        print_error "rustup not found. Install from https://rustup.rs"
        exit 1
    fi
    
    if ! command -v cmake &> /dev/null; then
        print_error "cmake not found. Install with: brew install cmake"
        exit 1
    fi
    
    if ! command -v xcodebuild &> /dev/null; then
        print_error "Xcode not found. Install from App Store"
        exit 1
    fi
    
    # Add iOS targets if needed
    if [[ "$BUILD_SIMULATOR" == "true" ]]; then
        rustup target add aarch64-apple-ios-sim 2>/dev/null || true
    fi
    if [[ "$BUILD_DEVICE" == "true" ]]; then
        rustup target add aarch64-apple-ios 2>/dev/null || true
    fi
    
    print_status "Prerequisites OK"
}

# Clean build artifacts
clean_build() {
    if [[ "$CLEAN_BUILD" == "true" ]]; then
        print_status "Cleaning build artifacts..."
        rm -rf "$FRAMEWORKS_DIR"
        rm -rf "$RUST_DIR/target/aarch64-apple-ios-sim"
        rm -rf "$RUST_DIR/target/aarch64-apple-ios"
        rm -rf "$RUST_DIR/scripts/mnn_lib_ios"
        print_status "Clean complete"
    fi
}

# Build MNN framework for iOS
build_mnn() {
    local target=$1  # "simulator" or "device"
    local mnn_output_dir="$RUST_DIR/scripts/mnn_lib_ios/$target"
    
    if [[ "$SKIP_MNN" == "true" && -d "$mnn_output_dir/MNN.framework" ]]; then
        print_warning "Skipping MNN build (using existing)"
        return 0
    fi
    
    print_status "Building MNN framework for iOS $target..."
    
    local mnn_dir="$RUST_DIR/MNN"
    local build_dir="$mnn_dir/build_ios_$target"
    
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    # CMake configuration based on target
    if [[ "$target" == "simulator" ]]; then
        cmake .. \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_OSX_SYSROOT=iphonesimulator \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
            -DMNN_BUILD_SHARED_LIBS=OFF \
            -DMNN_SEP_BUILD=OFF \
            -DMNN_BUILD_MINI=ON \
            -DMNN_SUPPORT_BF16=ON \
            -DMNN_ARM82=ON \
            -DMNN_LOW_MEMORY=ON \
            -DMNN_BUILD_LLM=ON \
            -DMNN_CPU_WEIGHT_DEQUANT_GEMM=ON \
            -DMNN_BUILD_OPENCV=ON \
            -DMNN_IMGCODECS=ON \
            -DMNN_BUILD_TEST=OFF \
            -DMNN_BUILD_BENCHMARK=OFF \
            -DMNN_BUILD_TOOLS=OFF \
            -DMNN_BUILD_DEMO=OFF \
            -DMNN_AAPL_FMWK=ON \
            -DMNN_METAL=ON
    else
        cmake .. \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_OSX_SYSROOT=iphoneos \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
            -DMNN_BUILD_SHARED_LIBS=OFF \
            -DMNN_SEP_BUILD=OFF \
            -DMNN_BUILD_MINI=ON \
            -DMNN_SUPPORT_BF16=ON \
            -DMNN_ARM82=ON \
            -DMNN_LOW_MEMORY=ON \
            -DMNN_BUILD_LLM=ON \
            -DMNN_CPU_WEIGHT_DEQUANT_GEMM=ON \
            -DMNN_BUILD_OPENCV=ON \
            -DMNN_IMGCODECS=ON \
            -DMNN_BUILD_TEST=OFF \
            -DMNN_BUILD_BENCHMARK=OFF \
            -DMNN_BUILD_TOOLS=OFF \
            -DMNN_BUILD_DEMO=OFF \
            -DMNN_AAPL_FMWK=ON \
            -DMNN_METAL=ON \
            -DMNN_COREML=ON
    fi
    
    cmake --build . -j$(sysctl -n hw.ncpu)
    
    # Copy framework to output
    mkdir -p "$mnn_output_dir"
    cp -R MNN.framework "$mnn_output_dir/"
    
    print_status "MNN framework built for $target"
    cd "$PROJECT_ROOT"
}

# Build Rust FFI library
build_rust() {
    local target=$1  # "simulator" or "device"
    
    print_status "Building Rust FFI library for iOS $target..."
    
    cd "$RUST_DIR"
    
    local rust_target
    local mnn_lib_path
    
    if [[ "$target" == "simulator" ]]; then
        rust_target="aarch64-apple-ios-sim"
        mnn_lib_path="$RUST_DIR/scripts/mnn_lib_ios/simulator/MNN.framework"
    else
        rust_target="aarch64-apple-ios"
        mnn_lib_path="$RUST_DIR/scripts/mnn_lib_ios/device/MNN.framework"
    fi
    
    # Build with proper flags to ensure FFI symbols are exported
    # -C embed-bitcode=no: Avoid LLVM version mismatch with Xcode
    # -C link-dead-code: Preserve FFI functions that appear unused to Rust
    MNN_LIB_PATH="$mnn_lib_path" \
    MNN_INCLUDE_PATH="$mnn_lib_path/Headers" \
    RUSTFLAGS="-C link-dead-code -C embed-bitcode=no -C codegen-units=1 -C lto=no" \
    cargo build --release --target "$rust_target"
    
    print_status "Rust library built for $target"
    cd "$PROJECT_ROOT"
}

# Copy libraries to iOS Frameworks folder
copy_to_frameworks() {
    print_status "Copying libraries to iOS Frameworks..."
    
    mkdir -p "$FRAMEWORKS_DIR"
    
    if [[ "$BUILD_SIMULATOR" == "true" && "$BUILD_DEVICE" == "true" ]]; then
        # Create universal/fat libraries
        print_status "Creating universal libraries..."
        
        # MNN Framework - create universal binary
        cp -R "$RUST_DIR/scripts/mnn_lib_ios/simulator/MNN.framework" "$FRAMEWORKS_DIR/"
        lipo -create \
            "$RUST_DIR/scripts/mnn_lib_ios/simulator/MNN.framework/MNN" \
            "$RUST_DIR/scripts/mnn_lib_ios/device/MNN.framework/MNN" \
            -output "$FRAMEWORKS_DIR/MNN.framework/MNN"
        
        # Rust library - create universal binary
        lipo -create \
            "$RUST_DIR/target/aarch64-apple-ios-sim/release/libllm.a" \
            "$RUST_DIR/target/aarch64-apple-ios/release/libllm.a" \
            -output "$FRAMEWORKS_DIR/libllm.a"
            
    elif [[ "$BUILD_SIMULATOR" == "true" ]]; then
        # Simulator only
        cp -R "$RUST_DIR/scripts/mnn_lib_ios/simulator/MNN.framework" "$FRAMEWORKS_DIR/"
        cp "$RUST_DIR/target/aarch64-apple-ios-sim/release/libllm.a" "$FRAMEWORKS_DIR/"
        
    elif [[ "$BUILD_DEVICE" == "true" ]]; then
        # Device only
        cp -R "$RUST_DIR/scripts/mnn_lib_ios/device/MNN.framework" "$FRAMEWORKS_DIR/"
        cp "$RUST_DIR/target/aarch64-apple-ios/release/libllm.a" "$FRAMEWORKS_DIR/"
    fi
    
    print_status "Libraries copied to $FRAMEWORKS_DIR"
}

# Verify the build
verify_build() {
    print_status "Verifying build..."
    
    # Check library exists
    if [[ ! -f "$FRAMEWORKS_DIR/libllm.a" ]]; then
        print_error "libllm.a not found!"
        exit 1
    fi
    
    # Check FFI symbols are present
    local symbol_count=$(nm "$FRAMEWORKS_DIR/libllm.a" 2>/dev/null | grep -c "T _llm_.*_ffi" || echo "0")
    if [[ "$symbol_count" -lt 10 ]]; then
        print_error "FFI symbols not found in libllm.a (found: $symbol_count)"
        print_error "This usually means the Rust build flags were incorrect"
        exit 1
    fi
    
    # Check MNN framework
    if [[ ! -d "$FRAMEWORKS_DIR/MNN.framework" ]]; then
        print_error "MNN.framework not found!"
        exit 1
    fi
    
    # Show library info
    echo ""
    print_status "Build verification passed!"
    echo "  • libllm.a: $(du -h "$FRAMEWORKS_DIR/libllm.a" | cut -f1)"
    echo "  • MNN.framework: $(du -sh "$FRAMEWORKS_DIR/MNN.framework" | cut -f1)"
    echo "  • FFI symbols: $symbol_count functions"
    
    local archs=$(lipo -info "$FRAMEWORKS_DIR/libllm.a" 2>/dev/null | sed 's/.*: //')
    echo "  • Architectures: $archs"
}

# Setup iOS project configuration
setup_ios_project() {
    print_status "Setting up iOS project configuration..."
    
    # Create MNN.xcconfig if it doesn't exist
    cat > "$IOS_DIR/Flutter/MNN.xcconfig" << 'EOF'
// MNN and Rust FFI library linking
// Force-load libllm.a to prevent FFI symbols from being stripped
FRAMEWORK_SEARCH_PATHS = $(inherited) $(PROJECT_DIR)/Frameworks
LIBRARY_SEARCH_PATHS = $(inherited) $(PROJECT_DIR)/Frameworks
OTHER_LDFLAGS = $(inherited) -force_load $(PROJECT_DIR)/Frameworks/libllm.a -framework MNN -lc++

// Exclude x86_64 for simulator - our native libs are arm64 only
EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64
EOF

    # Ensure xcconfig is included in Debug.xcconfig
    if ! grep -q "MNN.xcconfig" "$IOS_DIR/Flutter/Debug.xcconfig" 2>/dev/null; then
        echo '#include "MNN.xcconfig"' >> "$IOS_DIR/Flutter/Debug.xcconfig"
    fi
    
    # Ensure xcconfig is included in Release.xcconfig
    if ! grep -q "MNN.xcconfig" "$IOS_DIR/Flutter/Release.xcconfig" 2>/dev/null; then
        echo '#include "MNN.xcconfig"' >> "$IOS_DIR/Flutter/Release.xcconfig"
    fi
    
    print_status "iOS project configured"
}

# Main build flow
main() {
    check_prerequisites
    clean_build
    
    if [[ "$BUILD_SIMULATOR" == "true" ]]; then
        build_mnn "simulator"
        build_rust "simulator"
    fi
    
    if [[ "$BUILD_DEVICE" == "true" ]]; then
        build_mnn "device"
        build_rust "device"
    fi
    
    copy_to_frameworks
    setup_ios_project
    verify_build
    
    echo ""
    echo "========================================"
    print_status "iOS build complete!"
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo "  1. cd $PROJECT_ROOT"
    echo "  2. flutter pub get"
    echo "  3. cd ios && pod install && cd .."
    if [[ "$BUILD_SIMULATOR" == "true" ]]; then
        echo "  4. flutter build ios --simulator"
        echo "  5. flutter run (with simulator running)"
    fi
    if [[ "$BUILD_DEVICE" == "true" ]]; then
        echo "  4. flutter build ios"
        echo "  5. flutter run (with device connected)"
    fi
}

main
