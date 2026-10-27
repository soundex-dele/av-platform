#!/bin/bash
set -euo pipefail
workspace="$(cd "$(dirname "$0")/../.." && pwd)"
arch="${SC_ARCH:-$(uname -m)}"
case "$arch" in x86_64|arm64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 1;; esac
for tool in cmake brew qtpaths6; do command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }; done
build="$workspace/livekit-app/out/screen-cast-macos-$arch"
args=()
prebuilt="${SC_WEBRTC_PREBUILT:-$workspace/webrtc/out/macos-$arch}"
if [[ -f "$prebuilt/Release/libwebrtc.a" ]]; then args+=("-DWEBRTC_PREBUILT_DIR=$prebuilt"); fi
for dependency in ixwebsocket protobuf sdl2; do
  source="$workspace/livekit-sdk-cpp/out/macos-$arch/_deps/$dependency-src"
  if [[ -d "$source" ]]; then
    key="$(printf '%s' "$dependency" | tr '[:lower:]' '[:upper:]')"
    args+=("-DFETCHCONTENT_SOURCE_DIR_$key=$source")
  fi
done
cmake -S "$workspace/livekit-app/apps/screen-cast/desktop" -B "$build" \
  -DCMAKE_TOOLCHAIN_FILE="$workspace/livekit-sdk-cpp/cmake/MacOSToolchain.cmake" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="$arch" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${SC_MACOS_TARGET:-14.0}" \
  -DOPENSSL_ROOT_DIR="$(brew --prefix openssl@3)" \
  -DCMAKE_PREFIX_PATH="$(qtpaths6 --query QT_INSTALL_PREFIX);$(brew --prefix libvpx);$(brew --prefix dav1d)" \
  -DBUILD_TESTING=ON "${args[@]}"
cmake --build "$build" --target av_screen_cast screen_cast_render_test screen_cast_session_test screen_cast_capture_test screen_cast_fixture --parallel "${SC_JOBS:-4}"
ctest --test-dir "$build" --output-on-failure -R '^screen_cast_'
cmake --install "$build" --prefix "$build/package" --component ScreenCast
QT_QPA_PLATFORM=offscreen "$build/package/av_screen_cast.app/Contents/MacOS/av_screen_cast" --check-runtime
printf 'App: %s\n' "$build/package/av_screen_cast.app"
