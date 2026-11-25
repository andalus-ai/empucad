#!/usr/bin/env bash
# One-time setup of the Rust <-> Flutter glue. Needs: Flutter >= 3.47, Rust >= 1.88, cmake, a C++
# compiler (the Manifold kernel is built from source), and network access.
#
# It takes the cargokit platform glue from flutter_rust_bridge's own plugin template (so it always
# matches your codegen version), keeps our hand-written Rust crates and Dart entry point, pins the
# bridge version, and generates the Dart bindings.
set -euo pipefail
cd "$(dirname "$0")/.."
ENGINE=../packages/empucad_engine

command -v flutter >/dev/null || { echo "flutter not found"; exit 1; }
command -v cargo   >/dev/null || { echo "cargo not found";   exit 1; }
cargo install flutter_rust_bridge_codegen --locked
FRB_VERSION="$(flutter_rust_bridge_codegen --version | awk '{print $NF}')"
echo "flutter_rust_bridge $FRB_VERSION"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
flutter_rust_bridge_codegen create "$TMP/empucad_engine" --template plugin \
  --platforms android,ios,linux,macos,windows \
  --rust-crate-dir rust --rust-crate-name empucad_engine

# Platform glue only; never overwrite our own rust/ crates, pubspec or Dart entry point.
for PLATFORM in android ios linux macos windows cargokit; do
  cp -R "$TMP/empucad_engine/$PLATFORM" "$ENGINE/"
done

# The Rust engine statically links Manifold, which requires the Apple C++ runtime.
for PLATFORM in ios macos; do
  PODSPEC="$ENGINE/$PLATFORM/empucad_engine.podspec"
  sed -i.bak "/^  s\\.dependency /a\\
  s.libraries = 'c++'
" "$PODSPEC"
  rm -f "$PODSPEC.bak"
done

# pin the Rust and Dart sides to the same bridge version (codegen refuses mismatches)
sed -i.bak "s|^flutter_rust_bridge = .*|flutter_rust_bridge = \"=$FRB_VERSION\"|" "$ENGINE/rust/Cargo.toml"
sed -i.bak "s|^  flutter_rust_bridge: .*|  flutter_rust_bridge: $FRB_VERSION|" "$ENGINE/pubspec.yaml"
rm -f "$ENGINE"/rust/Cargo.toml.bak "$ENGINE"/pubspec.yaml.bak

flutter pub get
( cd "$ENGINE" && flutter pub get && flutter_rust_bridge_codegen generate )
echo "done. Now: flutter run --enable-flutter-gpu   (or --dart-define=EMPUCAD_RENDERER=canvas)"
