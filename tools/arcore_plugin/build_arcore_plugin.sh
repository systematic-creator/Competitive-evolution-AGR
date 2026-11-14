#!/usr/bin/env bash
# Build the patched GodotVR ARCore plugin and install it into
# addons/ARCorePlugin/ (bin/ + plugin.gdextension).
#
# Godot 4.4+ only: upstream's camera passthrough uses CameraFeed.set_external()
# and get_texture_tex_id(), which Godot 4.3 does not have.
#
# Requires: git, python3 + scons, JDK 17, and an Android SDK with
#   platforms;android-33  build-tools;33.0.2  cmake;3.22.1  ndk;23.2.8568313
# (sdkmanager "platforms;android-33" "build-tools;33.0.2" "cmake;3.22.1" "ndk;23.2.8568313")
#
# Usage: ANDROID_HOME=/path/to/sdk GODOT_BIN=/path/to/godot-4.4.x \
#        tools/arcore_plugin/build_arcore_plugin.sh
# GODOT_BIN (recommended) dumps the exact engine API that godot-cpp binds
# against; without it, upstream's bundled 4.4-dev API file is used.
set -euo pipefail

UPSTREAM="https://github.com/GodotVR/godot_arcore.git"
COMMIT="1509a01cc9115ac2933c0a2fc333ae6e98bb59d2"
NDK_VERSION="23.2.8568313"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HERE/../.." && pwd)"
: "${ANDROID_HOME:?Set ANDROID_HOME to your Android SDK}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-$ANDROID_HOME/ndk/$NDK_VERSION}"
WORK="${WORK:-$(mktemp -d)}"
JOBS="$(nproc 2>/dev/null || echo 4)"

echo "==> Fetching godot_arcore @ $COMMIT into $WORK"
if [ ! -d "$WORK/godot_arcore/.git" ]; then
	git clone "$UPSTREAM" "$WORK/godot_arcore"
fi
cd "$WORK/godot_arcore"
git checkout -q "$COMMIT"
git submodule update --init godot-cpp

echo "==> Applying AGR patch (plane hit test + anchors)"
if git apply --check "$HERE/agr-arcore.patch" 2>/dev/null; then
	git apply "$HERE/agr-arcore.patch"
else
	echo "    patch already applied (or does not apply cleanly); continuing"
fi

if [ -n "${GODOT_BIN:-}" ]; then
	echo "==> Dumping the engine API from $GODOT_BIN"
	mkdir -p "$WORK/api"
	(cd "$WORK/api" && "$GODOT_BIN" --headless --dump-extension-api >/dev/null 2>&1)
	API_FILE="$WORK/api/extension_api.json"
else
	API_FILE="$WORK/godot_arcore/thirdparty/godot_cpp_extension_api/extension_api.json"
fi
[ -f "$API_FILE" ] || { echo "missing engine API file: $API_FILE" >&2; exit 1; }

echo "==> Building godot-cpp for Android arm64 against $API_FILE"
(cd godot-cpp && scons platform=android arch=arm64 target=template_debug custom_api_file="$API_FILE" -j"$JOBS" \
	&& scons platform=android arch=arm64 target=template_release custom_api_file="$API_FILE" -j"$JOBS")

echo "==> Building the plugin AAR + GDExtension"
echo "sdk.dir=$ANDROID_HOME" > local.properties
./gradlew --no-daemon assemble

echo "==> Installing into $PROJECT/addons/ARCorePlugin"
OUT="plugin/demo/addons/ARCorePlugin/bin"
rm -rf "$PROJECT/addons/ARCorePlugin/bin"
mkdir -p "$PROJECT/addons/ARCorePlugin/bin"
cp -R "$OUT/." "$PROJECT/addons/ARCorePlugin/bin/"
cp "$HERE/plugin.gdextension" "$PROJECT/addons/ARCorePlugin/plugin.gdextension"
find "$PROJECT/addons/ARCorePlugin/bin" -type f | sed "s#$PROJECT/##"
echo "==> Done. Export with the 'Android AR' preset (Gradle build)."
