# Native UI film

The 30-second README video uses the actual `DeckView` and `DeckSettingsView` from this repository. OpenDesign MCP / HyperFrames composes the native capture into a warm editorial film with a separate illustrated Option key and camera moves timed to the real UI. There are no added captions or subtitles; Korean text belongs to the app itself.

The capture runs offscreen in a separate process. It uses scripted preview values for brightness and volume and the editor's real insertion, resize, removal and Rust layout functions. It does not activate windows, send global mouse/keyboard events, change device settings, start playback, or save personal preferences. This is a native UI preview, rather than a recording of physical trackpad input. Personal settings are replaced with the public defaults only in temporary capture sources.

## Recreate the native capture

From the repository root on macOS, after installing the build prerequisites:

```sh
zsh scripts/build.sh
python3 scripts/motion/capture_native.py
swiftc -parse-as-library -O scripts/motion/encode_native.swift \
  -o .build/native-ui/encode-native
.build/native-ui/encode-native .build/native-ui/frames .build/native-ui/native-ui.mp4
```

The capture script compiles temporary copies under `.build/native-ui/`; it does not edit production app sources. A restricted execution sandbox may prevent macOS app discovery and native video codecs from working; run the capture/encoder in a normal local terminal. The encoder expects a new output path. Delete or rename an earlier local output before re-encoding.

The intermediate recording is 2000 × 1480, 15 fps, exactly 30 seconds. It preserves the native source cadence. `capture.json` records the sequence. Only generic Finder menu commands are retained; no document/window titles, personal paths or music metadata are recorded.

## Edit with OpenDesign

The editable HyperFrames project is in [`composition/`](composition/). Import `scripts/motion/composition/` and `docs/assets/quickstart-poster.png` into an OpenDesign project at those same relative paths. Keep the composition’s local media and runtime files together. The final export is 1920 × 1080 at 30 fps. Its source includes deterministic seeking and a static preview for reduced-motion preferences.

Use OpenDesign's local renderer from its provided project environment, adapting the composition directory to the imported location:

```sh
"$OD_NODE_BIN" "$OD_BIN" media generate \
  --project "$OD_PROJECT_ID" \
  --surface video --model hyperframes-html \
  --composition-dir "scripts/motion/composition" \
  --output "docs/assets/quickstart.mp4"
```

Follow the `media wait` command if the renderer returns an asynchronous task. Review the exported movie before replacing [`quickstart.mp4`](../../docs/assets/quickstart.mp4), and derive the [GIF](../../docs/assets/quickstart.gif) and [poster](../../docs/assets/quickstart-poster.png) from the same export.

No cloud media-generation API, personal desktop footage, credentials or remote fonts are needed. Bundled third-party runtimes retain their original copyright and license notices.
