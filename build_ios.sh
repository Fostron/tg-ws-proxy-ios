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
rm -rf $BUILD_DIR/ios $BUILD_DIR/ipa $BUILD_DIR/$APP_NAME.ipa $BUILD_DIR/$APP_NAME.xcarchive
mkdir -p $BUILD_DIR/ios

# Каждая сборка получает уникальный CFBundleVersion (номер запуска CI, либо unix-время
# локально), чтобы iOS и sideload-тулзы точно видели новую версию и не подсовывали
# закэшированные ресурсы (иконку) от предыдущей установки с тем же bundle ID.
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-$(date +%s)}"
echo "Build number: $BUILD_NUMBER"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" TgWsProxy/Info.plist

# Расширение Live Activity обязано иметь те же версии, что и приложение,
# иначе iOS откажется его устанавливать.
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" TgWsProxy/Info.plist)
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" TgWsProxyLiveActivity/Info.plist
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" TgWsProxyLiveActivity/Info.plist

IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)

# Только arm64 для устройства: таргет приложения линкует этот .a напрямую
# (OTHER_LDFLAGS в project.pbxproj; расширение Live Activity его не получает).
# Симуляторная сборка и xcframework нигде не использовались.
SDKROOT=$IOS_SDK CGO_ENABLED=1 GOOS=ios GOARCH=arm64 \
  CC="$(xcrun --sdk iphoneos -f clang)" \
  CGO_CFLAGS="-isysroot $IOS_SDK -arch arm64 -mios-version-min=16.0" \
  CGO_LDFLAGS="-isysroot $IOS_SDK -arch arm64 -mios-version-min=16.0" \
  go build -v -buildmode=c-archive -o $BUILD_DIR/ios/libtgwsproxy.a .

echo ""
echo "--- Step 2: Building .app ---"
# EXPERIMENTAL=1 собирает тестовую сборку: в ней видны экспериментальные
# функции (FakeTLS/nginx, TLS-отпечаток, SNI, фрагментация, DoH). Публичный
# релиз собирается без них.
EXTRA_SETTINGS=()
if [ "${EXPERIMENTAL:-0}" = "1" ]; then
    echo "Flavor: test (experimental features included)"
    EXTRA_SETTINGS+=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) EXPERIMENTAL')
else
    echo "Flavor: public"
fi

xcodebuild archive \
  -project TgWsProxy.xcodeproj \
  -scheme $APP_NAME \
  -configuration Release \
  -archivePath $BUILD_DIR/$APP_NAME.xcarchive \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  "${EXTRA_SETTINGS[@]}"

echo ""
echo "--- Step 3: Creating .ipa ---"
mkdir -p $BUILD_DIR/ipa/Payload
cp -r $BUILD_DIR/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app $BUILD_DIR/ipa/Payload/

APPEX="$BUILD_DIR/ipa/Payload/$APP_NAME.app/PlugIns/TgWsProxyLiveActivity.appex"
if [ ! -d "$APPEX" ]; then
    echo "ERROR: Live Activity extension is missing from the app bundle"
    exit 1
fi
echo "Live Activity extension embedded: $APPEX"
cd $BUILD_DIR/ipa
zip -r ../$APP_NAME.ipa Payload/
cd ../..

echo ""
echo "=== Done! ==="
echo "  IPA: $BUILD_DIR/$APP_NAME.ipa"
