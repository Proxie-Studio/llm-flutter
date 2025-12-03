#!/bin/bash
# Unified Build Script for llm-flutter
# Build flow: MNN lib → Rust lib → FRB bindings → Copy to Flutter
# Supports: Android (arm64-v8a), iOS Device (arm64), iOS Simulator (arm64)
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
CYAN='\033[0;36m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_step() { echo -e "${BLUE}[→]${NC} $1"; }

usage() {
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Unified Build Script for llm-flutter${NC}"
    echo -e "${CYAN}  MNN lib → Rust lib → FRB bindings → Copy to Flutter${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Usage: $0 <platform> [options]"
    echo ""
    echo "Platforms:"
    echo "  android       Build for Android (arm64-v8a)"
    echo "  ios-sim       Build for iOS Simulator (arm64)"
    echo "  ios-device    Build for iOS Device (arm64)"
    echo "  all           Build all platforms"
    echo ""
    echo "Options:"
    echo "  --clean       Clean before building"
    echo "  --skip-mnn    Skip MNN compilation (use existing)"
    echo "  --skip-rust   Skip Rust compilation (use existing)"
    echo "  --skip-frb    Skip FRB codegen (use existing bindings)"
    echo ""
    echo "Other Commands:"
    echo "  generate      Run FRB codegen only"
    echo "  clean         Clean all build artifacts"
    echo ""
    echo "Examples:"
    echo "  $0 android                 # Full Android build"
    echo "  $0 ios-sim --skip-mnn      # iOS sim, reuse MNN"
    echo "  $0 all --clean             # Clean build all platforms"
}

# ============================================================================
# Step 1: Build MNN Library
# ============================================================================

build_mnn_android() {
    print_step "Building MNN for Android (arm64-v8a)..."
    cd "$RUST_DIR"
    ./scripts/build.sh mnn-android -DMNN_ARM82=ON -DMNN_OPENCL=ON
    cd "$PROJECT_ROOT"
    print_status "MNN Android built"
}

build_mnn_ios_sim() {
    print_step "Building MNN for iOS Simulator..."
    cd "$RUST_DIR"
    ./scripts/build_ios.sh framework-sim
    cd "$PROJECT_ROOT"
    print_status "MNN iOS Simulator built"
}

build_mnn_ios_device() {
    print_step "Building MNN for iOS Device..."
    cd "$RUST_DIR"
    ./scripts/build_ios.sh framework
    cd "$PROJECT_ROOT"
    print_status "MNN iOS Device built"
}

# ============================================================================
# Step 2: Build Rust Library
# ============================================================================

build_rust_android() {
    print_step "Building Rust for Android..."
    cd "$RUST_DIR"
    ./scripts/build.sh rust-android
    cd "$PROJECT_ROOT"
    print_status "Rust Android built"
}

build_rust_ios_sim() {
    print_step "Building Rust for iOS Simulator..."
    cd "$RUST_DIR"
    ./scripts/build_ios.sh rust-sim
    cd "$PROJECT_ROOT"
    print_status "Rust iOS Simulator built"
}

build_rust_ios_device() {
    print_step "Building Rust for iOS Device..."
    cd "$RUST_DIR"
    ./scripts/build_ios.sh rust
    cd "$PROJECT_ROOT"
    print_status "Rust iOS Device built"
}

# ============================================================================
# Step 3: Generate FRB Bindings
# ============================================================================

generate_frb() {
    print_step "Generating Flutter Rust Bridge bindings..."
    cd "$PROJECT_ROOT"
    
    if ! command -v flutter_rust_bridge_codegen &> /dev/null; then
        print_warning "flutter_rust_bridge_codegen not found, installing..."
        cargo install flutter_rust_bridge_codegen
    fi
    
    flutter_rust_bridge_codegen generate \
        --config-file "$RUST_DIR/flutter_rust_bridge.yaml"
    
    print_status "FRB bindings generated"
}

# ============================================================================
# Step 4: Copy Libraries to Flutter
# ============================================================================

copy_android_libs() {
    print_step "Copying Android libraries to Flutter..."
    
    local JNI_DIR="$ANDROID_DIR/app/src/main/jniLibs/arm64-v8a"
    local MNN_LIB="$RUST_DIR/scripts/mnn_lib_android_arm64-v8a/lib"
    local RUST_LIB="$RUST_DIR/target/aarch64-linux-android/release"
    
    mkdir -p "$JNI_DIR"
    
    # Copy MNN .so files
    cp "$MNN_LIB"/*.so "$JNI_DIR/" 2>/dev/null || true
    
    # Copy Rust .so (named libmnn_llm_frb.so -> libllm.so)
    if [ -f "$RUST_LIB/libmnn_llm_frb.so" ]; then
        cp "$RUST_LIB/libmnn_llm_frb.so" "$JNI_DIR/libllm.so"
    fi
    
    print_status "Android libs copied to $JNI_DIR"
    ls "$JNI_DIR"/*.so 2>/dev/null | xargs -I {} basename {}
}

copy_ios_sim_libs() {
    print_step "Copying iOS Simulator libraries to Flutter..."
    
    local FRAMEWORKS_DIR="$IOS_DIR/Frameworks"
    local MNN_FW="$RUST_DIR/scripts/mnn_lib_ios/simulator/MNN.framework"
    local RUST_LIB="$RUST_DIR/target/aarch64-apple-ios-sim/release/libmnn_llm_frb.a"
    
    mkdir -p "$FRAMEWORKS_DIR"
    rm -rf "$FRAMEWORKS_DIR/MNN.framework"
    
    # Copy MNN framework
    cp -R "$MNN_FW" "$FRAMEWORKS_DIR/"
    
    # Copy Rust static lib
    if [ -f "$RUST_LIB" ]; then
        cp "$RUST_LIB" "$FRAMEWORKS_DIR/libllm.a"
    fi
    
    print_status "iOS Simulator libs copied to $FRAMEWORKS_DIR"
}

copy_ios_device_libs() {
    print_step "Copying iOS Device libraries to Flutter..."
    
    local FRAMEWORKS_DIR="$IOS_DIR/Frameworks"
    local MNN_FW="$RUST_DIR/scripts/mnn_lib_ios/device/MNN.framework"
    local RUST_LIB="$RUST_DIR/target/aarch64-apple-ios/release/libmnn_llm_frb.a"
    
    mkdir -p "$FRAMEWORKS_DIR"
    rm -rf "$FRAMEWORKS_DIR/MNN.framework"
    
    # Copy MNN framework
    cp -R "$MNN_FW" "$FRAMEWORKS_DIR/"
    
    # Copy Rust static lib
    if [ -f "$RUST_LIB" ]; then
        cp "$RUST_LIB" "$FRAMEWORKS_DIR/libllm.a"
    fi
    
    print_status "iOS Device libs copied to $FRAMEWORKS_DIR"
}

# ============================================================================
# Clean
# ============================================================================

clean_all() {
    print_step "Cleaning all build artifacts..."
    
    # Android
    rm -rf "$ANDROID_DIR/app/src/main/jniLibs"
    rm -rf "$RUST_DIR/scripts/mnn_build_android_*"
    rm -rf "$RUST_DIR/scripts/mnn_lib_android_*"
    
    # iOS
    rm -rf "$IOS_DIR/Frameworks"
    rm -rf "$RUST_DIR/scripts/mnn_build_ios"
    rm -rf "$RUST_DIR/scripts/mnn_lib_ios"
    
    # Rust targets
    rm -rf "$RUST_DIR/target/aarch64-linux-android"
    rm -rf "$RUST_DIR/target/aarch64-apple-ios"
    rm -rf "$RUST_DIR/target/aarch64-apple-ios-sim"
    
    print_status "Cleaned"
}

# ============================================================================
# Full Build Pipelines
# ============================================================================

build_android() {
    echo ""
    echo -e "${CYAN}═══ Building for Android (arm64-v8a) ═══${NC}"
    echo ""
    
    [[ "$SKIP_MNN" != "true" ]] && build_mnn_android
    [[ "$SKIP_RUST" != "true" ]] && build_rust_android
    [[ "$SKIP_FRB" != "true" ]] && generate_frb
    copy_android_libs
    
    echo ""
    print_status "Android build complete!"
    echo "  Run: flutter build apk"
}

build_ios_sim() {
    echo ""
    echo -e "${CYAN}═══ Building for iOS Simulator (arm64) ═══${NC}"
    echo ""
    
    [[ "$SKIP_MNN" != "true" ]] && build_mnn_ios_sim
    [[ "$SKIP_RUST" != "true" ]] && build_rust_ios_sim
    [[ "$SKIP_FRB" != "true" ]] && generate_frb
    copy_ios_sim_libs
    
    echo ""
    print_status "iOS Simulator build complete!"
    echo "  Run: cd ios && pod install && cd .. && flutter build ios --simulator"
}

build_ios_device() {
    echo ""
    echo -e "${CYAN}═══ Building for iOS Device (arm64) ═══${NC}"
    echo ""
    
    [[ "$SKIP_MNN" != "true" ]] && build_mnn_ios_device
    [[ "$SKIP_RUST" != "true" ]] && build_rust_ios_device
    [[ "$SKIP_FRB" != "true" ]] && generate_frb
    copy_ios_device_libs
    
    echo ""
    print_status "iOS Device build complete!"
    echo "  Run: cd ios && pod install && cd .. && flutter build ios"
}

# ============================================================================
# Main
# ============================================================================

PLATFORM=""
CLEAN_BUILD=false
SKIP_MNN=false
SKIP_RUST=false
SKIP_FRB=false

while [[ $# -gt 0 ]]; do
    case $1 in
        android|ios-sim|ios-device|all|generate|clean)
            PLATFORM="$1"
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
        --skip-rust)
            SKIP_RUST=true
            shift
            ;;
        --skip-frb)
            SKIP_FRB=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown: $1"
            usage
            exit 1
            ;;
    esac
done

if [ -z "$PLATFORM" ]; then
    usage
    exit 1
fi

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  llm-flutter Build System${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

[[ "$CLEAN_BUILD" == "true" ]] && clean_all

case "$PLATFORM" in
    android)
        build_android
        ;;
    ios-sim)
        build_ios_sim
        ;;
    ios-device)
        build_ios_device
        ;;
    all)
        build_android
        build_ios_sim
        build_ios_device
        ;;
    generate)
        generate_frb
        ;;
    clean)
        clean_all
        ;;
esac
