#!/usr/bin/env bash
# Builds the TV helper (HAAM Keep Awake) with the Android SDK's command-line
# tools only (aapt2, javac, d8, zipalign, apksigner) and copies it into the
# phone app's assets, where the phone app installs it on the TV over ADB.
#
#   ANDROID_HOME=/path/to/sdk tool... tv_app/build.sh [version-code]
set -euo pipefail
cd "$(dirname "$0")"

VERSION_CODE="${1:-1}"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[ -n "$SDK" ] || { echo "Set ANDROID_HOME" >&2; exit 1; }
BUILD_TOOLS="$(ls -d "$SDK"/build-tools/*/ | sort -V | tail -1)"
PLATFORM="$(ls -d "$SDK"/platforms/android-*/ | sort -V | tail -1)"
ANDROID_JAR="$PLATFORM/android.jar"
echo "build-tools: $BUILD_TOOLS"
echo "platform:    $PLATFORM"

OUT=build
rm -rf "$OUT" && mkdir -p "$OUT/classes" "$OUT/dex"

"$BUILD_TOOLS/aapt2" link \
  -I "$ANDROID_JAR" \
  --manifest AndroidManifest.xml \
  --min-sdk-version 26 \
  --target-sdk-version 30 \
  --version-code "$VERSION_CODE" \
  --version-name "1.$VERSION_CODE" \
  -o "$OUT/unsigned.apk"

javac -source 1.8 -target 1.8 -Xlint:-options -Werror \
  -bootclasspath "$ANDROID_JAR" \
  -d "$OUT/classes" $(find src -name '*.java')

"$BUILD_TOOLS/d8" --release --min-api 26 --lib "$ANDROID_JAR" \
  --output "$OUT/dex" $(find "$OUT/classes" -name '*.class')

(cd "$OUT/dex" && zip -q ../unsigned.apk classes.dex)
"$BUILD_TOOLS/zipalign" -f -p 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"
"$BUILD_TOOLS/apksigner" sign \
  --ks ../android/signing/sideload.p12 --ks-type PKCS12 \
  --ks-pass pass:haamremote --ks-key-alias haam \
  --out "$OUT/keep-awake.apk" "$OUT/aligned.apk"
"$BUILD_TOOLS/apksigner" verify "$OUT/keep-awake.apk"
"$BUILD_TOOLS/aapt2" dump badging "$OUT/keep-awake.apk" | head -5

# The phone starts the service from the ADB shell, which only works if it is
# exported and guarded by a permission the shell holds (a TV refused it with
# "Requires permission not exported" before). Fail the build otherwise.
"$BUILD_TOOLS/aapt2" dump xmltree --file AndroidManifest.xml "$OUT/keep-awake.apk" > "$OUT/manifest.txt"
python3 - "$OUT/manifest.txt" <<'PY'
import re, sys
tree = open(sys.argv[1]).read()
service = tree[tree.index('E: service'):]
service = service[:service.find('E: receiver')] if 'E: receiver' in service else service
exported = re.search(r'exported\(0x01010010\)=(true|\(type 0x12\)0xffffffff|-1)', service)
guarded = 'permission(0x01010006)="android.permission.DUMP"' in service
assert exported and guarded, "service must be exported and guarded by DUMP:\n" + service
print("manifest check: service exported, guarded by android.permission.DUMP")
PY

mkdir -p ../assets/tv
cp "$OUT/keep-awake.apk" ../assets/tv/keep-awake.apk
echo "TV helper: $(stat -c %s ../assets/tv/keep-awake.apk) bytes -> assets/tv/keep-awake.apk"
