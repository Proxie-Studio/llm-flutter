#!/bin/bash
# Build script for Flutter with flutter_rust_bridge
# Supports: iOS Simulator, iOS Device, Android
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUST_PROJECT="$FLUTTER_ROOT/rust/mnn_llm"

cd "$RUST_PROJECT"

# Default to arm64-v8a for Android
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"

show_usage() {
    echo -e "${BLUE}MNN-LLM Flutter Rust Bridge Build Script${NC}"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  ios-sim        Build for iOS Simulator (arm64)"
    echo "  ios-device     Build for iOS Device (arm64)"
    echo "  android        Build for Android (arm64-v8a)"
    echo "  generate       Generate FRB Dart bindings only"
    echo "  all            Build all platforms"
    echo "  clean          Clean build artifacts"
    echo ""
    echo "Examples:"
    echo "  $0 ios-sim                    # Build for iOS Simulator"
    echo "  $0 android                    # Build for Android"
    echo "  ANDROID_ABI=x86_64 $0 android # Build for Android x86_64"
    echo ""
}

get_rust_target() {
    case "$ANDROID_ABI" in
        arm64-v8a)      echo "aarch64-linux-android" ;;
        armeabi-v7a)    echo "armv7-linux-androideabi" ;;
        x86)            echo "i686-linux-android" ;;
        x86_64)         echo "x86_64-linux-android" ;;
    esac
}

generate_bindings() {
    echo -e "${BLUE}Generating Flutter Rust Bridge bindings...${NC}"
    cd "$FLUTTER_ROOT"
    flutter_rust_bridge_codegen generate --config-file rust/mnn_llm/flutter_rust_bridge.yaml
    echo -e "${GREEN}✓ Bindings generated${NC}"
}

build_ios_sim() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Building for iOS Simulator                          ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    
    MNN_LIB="$RUST_PROJECT/scripts/mnn_lib/lib"
    MNN_INCLUDE="$RUST_PROJECT/scripts/mnn_lib/include"
    
    if [ ! -d "$MNN_LIB" ]; then
        echo -e "${RED}❌ MNN libraries not found at $MNN_LIB${NC}"
        echo "Run: ./scripts/build.sh mnn"
        exit 1
    fi
    
    export MNN_LIB_PATH="$MNN_LIB"
    export MNN_INCLUDE_PATH="$MNN_INCLUDE"
    
    # Build static library for iOS Simulator
    echo -e "${YELLOW}Building Rust static library...${NC}"
    cargo build --release --target aarch64-apple-ios-sim
    
    # Create universal static library
    STATIC_LIB="$RUST_PROJECT/target/aarch64-apple-ios-sim/release/libllm.a"
    if [ -f "$STATIC_LIB" ]; then
        echo -e "${GREEN}✓ Static library built: $STATIC_LIB${NC}"
    fi
    
    # Copy MNN dylibs to Flutter iOS folder
    IOS_FRAMEWORKS="$FLUTTER_ROOT/ios/Frameworks"
    mkdir -p "$IOS_FRAMEWORKS"
    cp "$MNN_LIB"/*.dylib "$IOS_FRAMEWORKS/" 2>/dev/null || true
    
    echo -e "${GREEN}✓ iOS Simulator build complete${NC}"
}

build_ios_device() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Building for iOS Device                             ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    
    MNN_LIB="$RUST_PROJECT/scripts/mnn_lib/lib"
    MNN_INCLUDE="$RUST_PROJECT/scripts/mnn_lib/include"
    
    if [ ! -d "$MNN_LIB" ]; then
        echo -e "${RED}❌ MNN libraries not found at $MNN_LIB${NC}"
        exit 1
    fi
    
    export MNN_LIB_PATH="$MNN_LIB"
    export MNN_INCLUDE_PATH="$MNN_INCLUDE"
    
    echo -e "${YELLOW}Building Rust static library...${NC}"
    cargo build --release --target aarch64-apple-ios
    
    STATIC_LIB="$RUST_PROJECT/target/aarch64-apple-ios/release/libllm.a"
    if [ -f "$STATIC_LIB" ]; then
        echo -e "${GREEN}✓ Static library built: $STATIC_LIB${NC}"
    fi
    
    echo -e "${GREEN}✓ iOS Device build complete${NC}"
}

build_android() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Building for Android ($ANDROID_ABI)                 ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    
    RUST_TARGET=$(get_rust_target)
    MNN_LIB="$RUST_PROJECT/scripts/mnn_lib_android_${ANDROID_ABI}/lib"
    MNN_INCLUDE="$RUST_PROJECT/scripts/mnn_lib_android_${ANDROID_ABI}/include"
    
    if [ ! -d "$MNN_LIB" ]; then
        echo -e "${YELLOW}MNN libraries not found. Building MNN for Android...${NC}"
        ./scripts/build.sh mnn-android
    fi
    
    # Build Rust library using build.sh (handles NDK setup)
    echo -e "${YELLOW}Building Rust library...${NC}"
    ANDROID_ABI=$ANDROID_ABI ./scripts/build.sh rust-android
    
    # Copy libraries to Flutter jniLibs
    JNILIBS_DIR="$FLUTTER_ROOT/android/app/src/main/jniLibs/$ANDROID_ABI"
    mkdir -p "$JNILIBS_DIR"
    
    echo -e "${BLUE}Copying libraries to $JNILIBS_DIR${NC}"
    
    # Copy Rust library (FRB cdylib)
    if [ -f "$RUST_PROJECT/target/$RUST_TARGET/release/libllm.so" ]; then
        cp "$RUST_PROJECT/target/$RUST_TARGET/release/libllm.so" "$JNILIBS_DIR/"
        echo -e "  ✓ libllm.so (Rust FRB)"
    fi
    
    # Copy MNN libraries
    for lib in libMNN.so libMNN_Express.so libMNNOpenCV.so; do
        if [ -f "$MNN_LIB/$lib" ]; then
            cp "$MNN_LIB/$lib" "$JNILIBS_DIR/"
            echo -e "  ✓ $lib"
        fi
    done
    
    echo -e "\n${GREEN}✓ Android build complete${NC}"
    echo -e "${BLUE}Libraries in jniLibs:${NC}"
    ls -lh "$JNILIBS_DIR"/*.so 2>/dev/null | awk '{print "  " $NF ": " $5}'
}

clean_build() {
    echo -e "${YELLOW}Cleaning build artifacts...${NC}"
    cargo clean
    rm -rf "$FLUTTER_ROOT/android/app/src/main/jniLibs"
    rm -rf "$FLUTTER_ROOT/ios/Frameworks"
    echo -e "${GREEN}✓ Clean complete${NC}"
}

# Main
case "${1:-}" in
    ios-sim)
        build_ios_sim
        ;;
    ios-device)
        build_ios_device
        ;;
    android)
        build_android
        ;;
    generate)
        generate_bindings
        ;;
    all)
        build_ios_sim
        build_android
        generate_bindings
        ;;
    clean)
        clean_build
        ;;
    *)
        show_usage
        ;;
esac
