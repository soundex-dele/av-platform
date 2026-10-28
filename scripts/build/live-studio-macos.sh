#!/bin/bash
set -euo pipefail
workspace="$(cd "$(dirname "$0")/../.." && pwd)"
arch="${STUDIO_ARCH:-$(uname -m)}"
case "$arch" in x86_64|arm64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 1;; esac
for tool in cmake brew; do command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }; done
build="$workspace/livekit-app/out/live-studio-macos-$arch"
cmake -S "$workspace/livekit-app/apps/live-studio/desktop" -B "$build" \
  -DCMAKE_TOOLCHAIN_FILE="$workspace/livekit-sdk-cpp/cmake/MacOSToolchain.cmake" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="$arch" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${STUDIO_MACOS_TARGET:-14.0}" \
  -DOPENSSL_ROOT_DIR="$(brew --prefix openssl@3)" \
  -DLIVEKIT_FFMPEG_ROOT="$(brew --prefix ffmpeg)" \
  -DCMAKE_PREFIX_PATH="$(brew --prefix qt);$(brew --prefix libvpx);$(brew --prefix dav1d);$(brew --prefix ffmpeg)" \
  -DLIVEKIT_ENABLE_VIDEO_PLAYOUT=OFF -DBUILD_TESTING=ON
cmake --build "$build" --target av_live_studio studio_engine_tests studio_media_graph_tests \
  studio_publisher_fixture studio_widgets_tests studio_http_tests studio_macos_backend_tests --parallel "${STUDIO_JOBS:-4}"
ctest --test-dir "$build" --output-on-failure -R '^studio_'
cmake --install "$build" --prefix "$build/package" --component LiveStudio
printf 'App: %s\n' "$build/package/av_live_studio.app"
