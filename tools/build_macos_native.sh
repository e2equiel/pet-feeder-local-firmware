#!/bin/sh
# Build a true native app. The only runtime libraries are provided by macOS.
set -eu
cd "$(dirname "$0")/.."
project_root=$PWD
version=$(cat native/macos/VERSION)
architecture=$(uname -m)
case "$architecture" in arm64|x86_64) ;; *) printf '%s\n' 'Unsupported Mac architecture.' >&2; exit 1 ;; esac
staging="$project_root/build/native-$architecture"
native_temp=$(mktemp -d "${TMPDIR:-/tmp}/pet-feeder-native-build.XXXXXX")
trap 'rm -rf "$native_temp"' 0
trap 'exit 1' HUP INT TERM
app="$native_temp/PetFeederLocalInstaller.app"
mkdir -p "$staging" dist
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/bundle"
for item in release.json pf_local.so boot.sh uninstall.sh; do
    cp "bundle/$item" "$app/Contents/Resources/bundle/$item"
done
cp native/macos/Assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PetFeederLocalInstaller</string>
<key>CFBundleIdentifier</key><string>io.github.e2equiel.pet-feeder-local.installer</string>
<key>CFBundleName</key><string>Pet Feeder Local Installer</string>
<key>CFBundleDisplayName</key><string>Pet Feeder Local Installer</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$version</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>PFLNativeInstaller</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Connect directly to the one pet feeder you select to check compatibility, save private backups and install local control. No network scan is performed.</string>
</dict></plist>
EOF
xcrun swiftc -swift-version 5 -O -whole-module-optimization -target "$architecture-apple-macosx13.0" \
    native/macos/Sources/*.swift -o "$app/Contents/MacOS/PetFeederLocalInstaller"
identity=${MACOS_SIGNING_IDENTITY:-}
if test -n "$identity"; then
    codesign --force --sign "$identity" --options runtime --timestamp "$app"
    codesign --display --verbose=4 "$app" 2>&1 | /usr/bin/grep -q '^Authority=Developer ID Application:'
    printf '%s\n' 'Native Swift app. Developer ID signed; notarization is still required.' > "$staging/SIGNING-STATUS.txt"
else
    codesign --force --sign - --options runtime "$app"
    printf '%s\n' 'Native Swift app; no Python runtime or third-party libraries.' \
        'Ad-hoc integrity signature only. NOT Developer ID signed or notarized by Apple.' \
        'Gatekeeper may block this app. No security settings or quarantine metadata are changed.' > "$staging/SIGNING-STATUS.txt"
fi
codesign --verify --deep --strict --verbose=2 "$app"
"$app/Contents/MacOS/PetFeederLocalInstaller" --verify-bundle
output="$project_root/dist/pet-feeder-local-$version-macos-$architecture.zip"
if test -e "$output"; then rm "$output"; fi
ditto -c -k --sequesterRsrc --keepParent "$app" "$output"
/usr/bin/zip -q -j "$output" README.md LICENSE "$staging/SIGNING-STATUS.txt"
shasum -a 256 "$output" | sed "s|$project_root/dist/||" > "$output.sha256"
printf '%s\n' "$output"
