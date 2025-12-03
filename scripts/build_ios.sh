#!/bin/bash
# iOS Build Script for llm-flutter
# Calls the MNN-LLM build script and packages for Flutter

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
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

usage() {
    echo -e "${BLUE}iOS Build Script for llm-flutter${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --simulator     Build for iOS Simulator (arm64)"
    echo "  --device        Build for iOS Device (arm64)"
    echo "  --all           Build for both simulator and device"
    echo "  --clean         Clean build artifacts before building"
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
    
    if ! command -v xcodebuild &> /dev/null; then
        print_error "Xcode not found. Install from App Store"
        exit 1
    fi
    
    if ! command -v rustup &> /dev/null; then
        print_error "rustup not found. Install from https://rustup.rs"
        exit 1
    fi
    
    if ! command -v cargo &> /dev/null; then
        print_error "cargo not found. Install Rust first"
        exit 1
    fi
    
    print_status "Prerequisites OK"
}

# Clean build artifacts
clean_build() {
    if [[ "$CLEAN_BUILD" == "true" ]]; then
        print_status "Cleaning build artifacts..."
        rm -rf "$FRAMEWORKS_DIR"
        
        cd "$RUST_DIR"
        ./scripts/build_ios.sh clean
        cd "$PROJECT_ROOT"
        
        print_status "Clean complete"
    fi
}

# Build MNN framework and Rust library using the MNN-LLM script
build_with_mnn_script() {
    local target=$1  # "simulator" or "device"
    
    print_status "Building MNN framework and Rust for iOS $target..."
    
    cd "$RUST_DIR"
    
    if [[ "$target" == "simulator" ]]; then
        # Build framework for simulator
        ./scripts/build_ios.sh framework-sim
        
        # Build Rust for simulator
        ./scripts/build_ios.sh rust-sim
    else
        # Build framework for device
        ./scripts/build_ios.sh framework
        
        # Build Rust for device
        ./scripts/build_ios.sh rust
    fi
    
    cd "$PROJECT_ROOT"
    
    print_status "MNN and Rust build complete for $target"
}

# Copy libraries to Flutter iOS folder
copy_to_flutter() {
    print_status "Copying libraries to Flutter iOS..."
    
    mkdir -p "$FRAMEWORKS_DIR"
    
    local mnn_lib_dir="$RUST_DIR/scripts/mnn_lib_ios"
    
    # Determine which framework to use
    if [[ "$BUILD_DEVICE" == "true" ]]; then
        # Use device framework
        if [[ -d "$mnn_lib_dir/device/MNN.framework" ]]; then
            cp -R "$mnn_lib_dir/device/MNN.framework" "$FRAMEWORKS_DIR/"
            print_status "Copied device MNN.framework"
        fi
    elif [[ "$BUILD_SIMULATOR" == "true" ]]; then
        # Use simulator framework
        if [[ -d "$mnn_lib_dir/simulator/MNN.framework" ]]; then
            cp -R "$mnn_lib_dir/simulator/MNN.framework" "$FRAMEWORKS_DIR/"
            print_status "Copied simulator MNN.framework"
        fi
    fi
    
    # Copy Rust static library
    if [[ "$BUILD_SIMULATOR" == "true" && "$BUILD_DEVICE" == "true" ]]; then
        # Create universal library
        print_status "Creating universal Rust library..."
        lipo -create \
            "$RUST_DIR/target/aarch64-apple-ios-sim/release/libllm.a" \
            "$RUST_DIR/target/aarch64-apple-ios/release/libllm.a" \
            -output "$FRAMEWORKS_DIR/libllm.a" 2>/dev/null || {
            # If lipo fails (same arch), just copy one
            cp "$RUST_DIR/target/aarch64-apple-ios/release/libllm.a" "$FRAMEWORKS_DIR/"
        }
    elif [[ "$BUILD_SIMULATOR" == "true" ]]; then
        cp "$RUST_DIR/target/aarch64-apple-ios-sim/release/libllm.a" "$FRAMEWORKS_DIR/"
    elif [[ "$BUILD_DEVICE" == "true" ]]; then
        cp "$RUST_DIR/target/aarch64-apple-ios/release/libllm.a" "$FRAMEWORKS_DIR/"
    fi
    
    print_status "Libraries copied to $FRAMEWORKS_DIR"
}

# Verify build
verify_build() {
    print_status "Verifying build..."
    
    if [[ ! -d "$FRAMEWORKS_DIR/MNN.framework" ]]; then
        print_error "MNN.framework not found!"
        exit 1
    fi
    
    if [[ ! -f "$FRAMEWORKS_DIR/libllm.a" ]]; then
        print_error "libllm.a not found!"
        exit 1
    fi
    
    # Check FFI symbols
    local symbol_count=$(nm "$FRAMEWORKS_DIR/libllm.a" 2>/dev/null | grep -c "T _llm_" || echo "0")
    if [[ "$symbol_count" -lt 5 ]]; then
        print_warning "Few FFI symbols found ($symbol_count). Build may be incomplete."
    else
        print_status "Found $symbol_count FFI symbols"
    fi
    
    # Show sizes
    echo ""
    print_status "Build artifacts:"
    echo "  • MNN.framework: $(du -sh "$FRAMEWORKS_DIR/MNN.framework" | cut -f1)"
    echo "  • libllm.a: $(du -h "$FRAMEWORKS_DIR/libllm.a" | cut -f1)"
    
    local archs=$(lipo -info "$FRAMEWORKS_DIR/libllm.a" 2>/dev/null | sed 's/.*: //' || echo "unknown")
    echo "  • Architectures: $archs"
}

# Setup Podfile if needed
setup_podfile() {
    local podfile="$IOS_DIR/Podfile"
    
    # Check if MNN.framework is already referenced
    if ! grep -q "MNN.framework" "$podfile" 2>/dev/null; then
        print_warning "You may need to update your Podfile to link MNN.framework and libllm.a"
        echo ""
        echo "Add to your Podfile's post_install hook:"
        echo ""
        echo '  post_install do |installer|'
        echo '    installer.pods_project.targets.each do |target|'
        echo '      target.build_configurations.each do |config|'
        echo '        config.build_settings["OTHER_LDFLAGS"] ||= ["$(inherited)"]'
        echo '        config.build_settings["OTHER_LDFLAGS"] << "-lc++"'
        echo '        config.build_settings["FRAMEWORK_SEARCH_PATHS"] ||= ["$(inherited)"]'
        echo '        config.build_settings["FRAMEWORK_SEARCH_PATHS"] << "$(PROJECT_DIR)/Frameworks"'
        echo '        config.build_settings["LIBRARY_SEARCH_PATHS"] ||= ["$(inherited)"]'
        echo '        config.build_settings["LIBRARY_SEARCH_PATHS"] << "$(PROJECT_DIR)/Frameworks"'
        echo '      end'
        echo '    end'
        echo '  end'
        echo ""
    fi
}

# Main build flow
main() {
    check_prerequisites
    clean_build
    
    if [[ "$BUILD_SIMULATOR" == "true" ]]; then
        build_with_mnn_script "simulator"
    fi
    
    if [[ "$BUILD_DEVICE" == "true" ]]; then
        build_with_mnn_script "device"
    fi
    
    copy_to_flutter
    verify_build
    setup_podfile
    
    echo ""
    print_status "iOS build complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Run 'cd ios && pod install'"
    echo "  2. Open ios/Runner.xcworkspace in Xcode"
    echo "  3. Build and run on simulator or device"
}

main
