#!/bin/bash
# Off-device compile check for OITI: Logos-preprocess every OITI_FILES source and syntax-compile it for arm64 iOS 16 with clang
# against a Theos iPhoneOS SDK, then check that every OITI-owned symbol is defined somewhere, and syntax-compile the Settings bundle.
# It catches compile errors, unknown selectors and undefined OITI symbols. It is NOT a Theos build (no link, no package, no signing)
# and cannot show runtime behavior (the v0.3.0 batch 1 bootloop compiled cleanly).
#
# Usage:  tools/offline_check.sh [repo root]            (default: the repo this script lives in)
# Needs:  clang (with the aarch64 target), llvm-nm, perl, git. On Debian/Ubuntu as root:  apt-get install -y clang lld llvm
#         Theos and one SDK; the defaults below are where a throwaway container keeps them. Override with THEOS=... SDK=...
#           git clone --depth 1 --recurse-submodules --shallow-submodules https://github.com/theos/theos /tmp/theos
#           git clone --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks /tmp/sdks
#           git -C /tmp/sdks sparse-checkout set iPhoneOS16.5.sdk
#         On the Arch PC set THEOS=$THEOS and SDK=$THEOS/sdks/iPhoneOS16.5.sdk (or whichever SDK is installed).
set -u
ROOT=$(cd "${1:-$(dirname "$0")/..}" && pwd)
THEOS=${THEOS:-/tmp/theos}
SDK=${SDK:-/tmp/sdks/iPhoneOS16.5.sdk}
LLVM_NM=${LLVM_NM:-$(command -v llvm-nm-18 || command -v llvm-nm)}
OUT=$(mktemp -d)
SHIM=$OUT/shim/CydiaSubstrate; mkdir -p "$SHIM"
cp "$THEOS/vendor/lib/CydiaSubstrate.framework/Headers/CydiaSubstrate.h" "$SHIM/" 2>/dev/null
COMMON=(-x objective-c -std=gnu11 -target arm64-apple-ios16.0 -isysroot "$SDK" -fobjc-arc -Wno-everything -ferror-limit=100
        -I. -I"$ROOT/OITCore/include" -I"$OUT/shim" -I"$THEOS/include" -I"$THEOS/vendor/include"
        -I"$THEOS/vendor/lib/CydiaSubstrate.framework/Headers" -I"$THEOS/vendor/orion/Sources" -include "$THEOS/Prefix.pch")
fail=0

echo "== tweak sources (Logos + clang -fsyntax-only)"
cd "$ROOT/OITI"
FILES=$(grep -E '^OITI_FILES' Makefile | sed -E 's/OITI_FILES *\+?= *//' | tr '\n' ' ')
for f in $FILES; do
  b=$(echo "$f" | tr '/' '_'); mm="$OUT/$b.mm"
  if ! perl "$THEOS/vendor/logos/bin/logos.pl" "$f" > "$mm" 2> "$mm.err"; then echo "LOGOS FAIL $f"; head -3 "$mm.err"; fail=1; continue; fi
  clang "${COMMON[@]}" -I"$(dirname "$f")" -fsyntax-only "$mm" 2> "$mm.cc"
  n=$(grep -c 'error:' "$mm.cc"); echo "  $f errors=$n"
  [ "$n" -gt 0 ] && { grep 'error:' "$mm.cc" | head -4; fail=1; }
  clang "${COMMON[@]}" -I"$(dirname "$f")" -c "$mm" -o "$OUT/$b.o" 2>/dev/null || { echo "  OBJECT FAIL $f"; fail=1; }
done

echo "== link closure (OITI-owned symbols defined somewhere)"
"$LLVM_NM" --defined-only "$OUT"/*.o 2>/dev/null | awk 'NF==3 && $2 ~ /[TDBSsdbt]/ {print $3}' | sort -u > "$OUT/defined.txt"
"$LLVM_NM" --undefined-only "$OUT"/*.o 2>/dev/null | awk 'NF>=1 {print $NF}' | sort -u > "$OUT/undefined.txt"
missing=$(comm -13 "$OUT/defined.txt" "$OUT/undefined.txt" | grep -E '^_(s[A-Z]|OITI|kOITI)' | grep -v '^_posix_spawn')
if [ -n "$missing" ]; then echo "UNDEFINED: $missing"; fail=1; else echo "  none missing"; fi

echo "== Settings bundle (clang -fsyntax-only)"
cd "$ROOT/OITI/OITIPrefs"
for f in *.m; do
  clang -x objective-c -std=gnu11 -fsyntax-only -target arm64-apple-ios16.0 -isysroot "$SDK" -fobjc-arc -I. -I.. -I"$ROOT/OITCore/include" \
        -I"$THEOS/include" -I"$THEOS/vendor/include" -F"$SDK/System/Library/PrivateFrameworks" -Wno-everything -ferror-limit=50 "$f" 2> "$OUT/prefs_$f.err"
  n=$(grep -c 'error:' "$OUT/prefs_$f.err"); echo "  $f errors=$n"
  [ "$n" -gt 0 ] && { grep 'error:' "$OUT/prefs_$f.err" | head -3; fail=1; }
done

echo "== repo guards"
cd "$ROOT"
python3 tools/check_ctor_path.py || fail=1
python3 tools/check_settings.py || fail=1
echo
[ $fail -eq 0 ] && echo "OFFLINE CHECK: OK (compile + link closure only; not a Theos build, not a device test)" || echo "OFFLINE CHECK: FAILED"
exit $fail
