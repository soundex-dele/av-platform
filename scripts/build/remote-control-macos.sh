#!/bin/bash
set -euo pipefail
workspace="$(cd "$(dirname "$0")/../.." && pwd)"
arch="${REMOTE_ARCH:-$(uname -m)}"
case "$arch" in x86_64|arm64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 1;; esac
build="$workspace/livekit-app/out/remote-control-macos-$arch"
args=(-DCMAKE_TOOLCHAIN_FILE="$workspace/livekit-sdk-cpp/cmake/MacOSToolchain.cmake"
 -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="$arch"
 -DCMAKE_OSX_DEPLOYMENT_TARGET="${REMOTE_MACOS_TARGET:-14.0}"
 -DOPENSSL_ROOT_DIR="$(brew --prefix openssl@3)"
 -DCMAKE_PREFIX_PATH="${QT_ROOT:-$(brew --prefix qtbase)};$(brew --prefix qtsvg);$(brew --prefix libvpx);$(brew --prefix dav1d)"
 -DLIVEKIT_ENABLE_VIDEO_PLAYOUT=OFF -DBUILD_TESTING=ON)
if [[ -n "${REMOTE_WEBRTC_PREBUILT:-}" ]]; then args+=(-DWEBRTC_PREBUILT_DIR="$REMOTE_WEBRTC_PREBUILT"); else args+=(-DWEBRTC_PREBUILT_DIR=); fi
if [[ -n "${REMOTE_PROTOC:-}" ]]; then args+=(-DLIVEKIT_PROTOC_EXECUTABLE="$REMOTE_PROTOC"); fi
cmake -S "$workspace/livekit-app/apps/remote-control/desktop" -B "$build" "${args[@]}"
cmake --build "$build" --parallel "${REMOTE_JOBS:-4}" --target av_remote_host remote_host_fixture remote_controller_fixture remote_host_render_test remote_protocol_test remote_sdk_test remote_lifecycle_test
ctest --test-dir "$build" --output-on-failure
cmake --install "$build" --prefix "$build/package" --component RemoteControl
python3 "$workspace/livekit-app/apps/remote-control/desktop/tests/validate_macos_bundle.py" "$build/package/av_remote_host.app"
printf 'App: %s\n' "$build/package/av_remote_host.app"
