#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export PATH="$HOME/.cargo/bin:$PATH"
cargo build --manifest-path engine/Cargo.toml --release --locked
# Include the static library digest in SwiftPM build inputs so Rust-only edits relink.
engine_hash="$(shasum -a 256 engine/target/release/libdeck_engine.a | cut -c 1-16)"
engine_flags=(-Xcc "-DOPTIONDECK_ENGINE_BUILD=0x$engine_hash")
cargo test --manifest-path engine/Cargo.toml --locked
developer_path="$(xcode-select -p)"
if [[ -d "$developer_path/Library/Developer/Frameworks/Testing.framework" ]]; then
    # Some Command Line Tools releases omit these search paths from SwiftPM.
    swift test "${engine_flags[@]}" --disable-xctest --enable-swift-testing \
        -Xswiftc -F -Xswiftc "$developer_path/Library/Developer/Frameworks" \
        -Xlinker -rpath -Xlinker "$developer_path/Library/Developer/Frameworks" \
        -Xlinker -rpath -Xlinker "$developer_path/Library/Developer/usr/lib"
else
    swift test "${engine_flags[@]}"
fi
