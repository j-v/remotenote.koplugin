#!/bin/bash
set -e

BUILD_DIR="build"
BIN_DIR="$BUILD_DIR/bin"
PLUGIN_NAME="remotenote.koplugin"

# Parse arguments
PACKAGE_ONLY=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--package)
            PACKAGE_ONLY=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -p, --package  Package only (skip Go compilation, reuse existing binaries)"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check for existing binaries if package-only mode
if $PACKAGE_ONLY; then
    if [[ ! -f "$BIN_DIR/certgen-arm-legacy" ]] || [[ ! -f "$BIN_DIR/certgen-armv7" ]] || [[ ! -f "$BIN_DIR/certgen-arm64" ]] || [[ ! -f "$BIN_DIR/certgen-x86_64" ]]; then
        echo "Error: Binaries not found. Run a full build first."
        exit 1
    fi
    echo "Package-only mode: reusing existing binaries"
fi

# Create build directories
if $PACKAGE_ONLY; then
    rm -rf "$BUILD_DIR/$PLUGIN_NAME"
    rm -f "$BUILD_DIR"/*.zip
else
    rm -rf "$BUILD_DIR"
    mkdir -p "$BIN_DIR"
fi
mkdir -p "$BUILD_DIR/$PLUGIN_NAME"
mkdir -p "$BUILD_DIR/$PLUGIN_NAME/bin"

# Copy plugin source files to build directory
cp *.lua "$BUILD_DIR/$PLUGIN_NAME/"
if [ -f "README.md" ]; then
    cp README.md "$BUILD_DIR/$PLUGIN_NAME/"
fi
if [ -f "LICENSE" ]; then
    cp LICENSE "$BUILD_DIR/$PLUGIN_NAME/"
fi

if ! $PACKAGE_ONLY; then
    cd certgen

    # Build for armv5 (soft-float, legacy devices like K3)
    echo "Building for armv5 (legacy)..."
    CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=5 go build -ldflags="-s -w" -o "../$BIN_DIR/certgen-arm-legacy" .
    echo "armv5: $(ls -lh "../$BIN_DIR/certgen-arm-legacy" | awk '{print $5}')"

    # Build for armv7 (32-bit ARM)
    echo "Building for armv7..."
    CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 go build -ldflags="-s -w" -o "../$BIN_DIR/certgen-armv7" .
    echo "armv7: $(ls -lh "../$BIN_DIR/certgen-armv7" | awk '{print $5}')"

    # Build for arm64 (64-bit ARM)
    echo "Building for arm64..."
    CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="-s -w" -o "../$BIN_DIR/certgen-arm64" .
    echo "arm64: $(ls -lh "../$BIN_DIR/certgen-arm64" | awk '{print $5}')"

    # Build for x86_64 (emulator/desktop)
    echo "Building for x86_64..."
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o "../$BIN_DIR/certgen-x86_64" .
    echo "x86_64: $(ls -lh "../$BIN_DIR/certgen-x86_64" | awk '{print $5}')"

    cd ..
fi

# Create armv5 zip (legacy)
echo "Creating armv5 zip..."
cp "$BIN_DIR/certgen-arm-legacy" "$BUILD_DIR/$PLUGIN_NAME/bin/certgen"
(cd "$BUILD_DIR" && zip -q -r "remotenote.koplugin-arm-legacy.zip" "$PLUGIN_NAME")

# Create armv7 zip
echo "Creating armv7 zip..."
cp "$BIN_DIR/certgen-armv7" "$BUILD_DIR/$PLUGIN_NAME/bin/certgen"
(cd "$BUILD_DIR" && zip -q -r "remotenote.koplugin-armv7.zip" "$PLUGIN_NAME")

# Create arm64 zip
echo "Creating arm64 zip..."
cp "$BIN_DIR/certgen-arm64" "$BUILD_DIR/$PLUGIN_NAME/bin/certgen"
(cd "$BUILD_DIR" && zip -q -r "remotenote.koplugin-arm64.zip" "$PLUGIN_NAME")

# Create x86_64 zip
echo "Creating x86_64 zip..."
cp "$BIN_DIR/certgen-x86_64" "$BUILD_DIR/$PLUGIN_NAME/bin/certgen"
(cd "$BUILD_DIR" && zip -q -r "remotenote.koplugin-x86_64.zip" "$PLUGIN_NAME")


# Clean up plugin staging dir (keep bins and zips)
rm -rf "$BUILD_DIR/$PLUGIN_NAME"

echo ""
echo "Done! Release files:"
ls -lh "$BUILD_DIR"/*.zip
echo ""
echo "Binaries:"
ls -lh "$BIN_DIR"/*
