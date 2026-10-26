#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export PATH="$HOME/.cargo/bin:$PATH"
cargo build --manifest-path engine/Cargo.toml --release --locked
# Include the static library digest in SwiftPM build inputs so Rust-only edits relink.
engine_hash="$(shasum -a 256 engine/target/release/libdeck_engine.a | cut -c 1-16)"
engine_flags=(-Xcc "-DOPTIONDECK_ENGINE_BUILD=0x$engine_hash")
swift build -c release "${engine_flags[@]}"
app="dist/OptionDeck.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/OptionDeck "$app/Contents/MacOS/OptionDeck"
cp Resources/Info.plist "$app/Contents/Info.plist"
.build/release/OptionDeck --icon "$PWD/.build/OptionDeck.iconset"
iconutil --convert icns --output "$app/Contents/Resources/AppIcon.icns" .build/OptionDeck.iconset
codesign --force --sign - --identifier io.github.a1paka12.OptionDeck "$app"
codesign --verify --strict "$app"
print "Built: $PWD/$app"
