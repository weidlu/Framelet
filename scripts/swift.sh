#!/bin/bash
# Work around partially upgraded Apple CLT installations without changing system files.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${SWIFTPM_CUSTOM_LIBS_DIR:-}" ]]; then
    TOOLCHAIN="$(xcode-select -p)/usr/lib/swift/pm/ManifestAPI"
    PUBLIC="$TOOLCHAIN/PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface"
    PRIVATE="$TOOLCHAIN/PackageDescription.swiftmodule/arm64-apple-macos.private.swiftinterface"
    if [[ -f "$PUBLIC" && -f "$PRIVATE" ]]; then
        PUBLIC_VERSION="$(sed -n '2p' "$PUBLIC")"
        PRIVATE_VERSION="$(sed -n '2p' "$PRIVATE")"
        if [[ "$PUBLIC_VERSION" != "$PRIVATE_VERSION" ]]; then
            mkdir -p .build/toolchain-libs/ManifestAPI
            ditto "$TOOLCHAIN" .build/toolchain-libs/ManifestAPI
            find .build/toolchain-libs/ManifestAPI -name '*.private.swiftinterface' -delete
            export SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/toolchain-libs"
        fi
    fi
fi
exec xcrun swift "$@"
