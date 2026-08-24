#!/bin/bash
set -e

echo "=== TG WS Proxy iOS — Build Script ==="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_DIR="build"
APP_NAME="TgWsProxy"

if ! command -v go &> /dev/null; then
    echo "ERROR: Go not found. Install from https://go.dev/dl/"
    exit 1
fi

if ! command -v xcodebuild &> /dev/null; then
    echo "ERROR: Xcode Command Line Tools not found."
    exit 1
fi

# uTLS and its dependencies are fetched here rather than committing go.sum:
# the module graph pulls golang.org/x/* which resolves differently depending on
# the toolchain, and `go mod tidy` on the build machine keeps it consistent.
echo "--- Step 0: Resolving Go modules ---"
go mod tidy

echo "--- Step 1: Building Go Library ---"
rm -rf $BUILD_DIR/$APP_NAME.xcframework
mkdir -p $BUILD_DIR/ios $BUILD_DIR/sim

# Каждая сборка получает уникальный CFBundleVersion (номер запуска CI, либо unix-время
# локально), чтобы iOS и sideload-тулзы точно видели новую версию и не подсовывали
# закэшированные ресурсы (иконку) от предыдущей установки с тем же bundle ID.
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-$(date +%s)}"
echo "Build number: $BUILD_NUMBER"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" TgWsProxy/Info.plist

# Сохраняем пути к SDK
IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
SIM_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

# Сборка для реального устройства (arm64)
SDKROOT=$IOS_SDK CGO_ENABLED=1 GOOS=ios GOARCH=arm64 \
  CC="$(xcrun --sdk iphoneos -f clang)" \
  CGO_CFLAGS="-isysroot $IOS_SDK -arch arm64 -mios-version-min=16.0" \
  CGO_LDFLAGS="-isysroot $IOS_SDK -arch arm64 -mios-version-min=16.0" \
  go build -v -buildmode=c-archive -o $BUILD_DIR/ios/libtgwsproxy.a .

# Сборка для симулятора (arm64)
SDKROOT=$SIM_SDK CGO_ENABLED=1 GOOS=ios GOARCH=arm64 \
  CC="$(xcrun --sdk iphonesimulator -f clang)" \
  CGO_CFLAGS="-isysroot $SIM_SDK -arch arm64 -mios-simulator-version-min=16.0" \
  CGO_LDFLAGS="-isysroot $SIM_SDK -arch arm64 -mios-simulator-version-min=16.0" \
  go build -buildmode=c-archive -o $BUILD_DIR/sim/libtgwsproxy.a .

xcodebuild -create-xcframework \
  -library $BUILD_DIR/ios/libtgwsproxy.a -headers include \
  -library $BUILD_DIR/sim/libtgwsproxy.a -headers include \
  -output $BUILD_DIR/$APP_NAME.xcframework

echo ""
echo "--- Step 2: Building .app ---"
# Напрямую "скармливаем" линковщику наш бинарник и системную библиотеку resolv
xcodebuild archive \
  -project TgWsProxy.xcodeproj \
  -scheme $APP_NAME \
  -configuration Release \
  -archivePath $BUILD_DIR/$APP_NAME.xcarchive \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  OTHER_LDFLAGS="\$(inherited) \"${PWD}/${BUILD_DIR}/ios/libtgwsproxy.a\" -lresolv"

echo ""
echo "--- Step 3: Creating .ipa ---"
mkdir -p $BUILD_DIR/ipa/Payload
cp -r $BUILD_DIR/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app $BUILD_DIR/ipa/Payload/
cd $BUILD_DIR/ipa
zip -r ../$APP_NAME.ipa Payload/
cd ../..

echo ""
echo "=== Done! ==="
echo "  IPA: $BUILD_DIR/$APP_NAME.ipa"
