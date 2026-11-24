#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -swift-version 5 native/macos/Sources/Support.swift native/macos/Sources/Installer.swift \
    native/macos/Tests/main.swift -o build/test-native-installer
build/test-native-installer
