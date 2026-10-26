# OpenDesign motion film

The 30-second OptionDeck film was created through **OpenDesign MCP**, using its `video-hyperframes` workflow with motion-design guidance. The editable composition, vector artwork and locally synthesized soundtrack live in [`composition/`](composition/). No personal desktop footage, external media-generation service or API credentials are included.

## Deliverables

- [`../../docs/assets/quickstart.mp4`](../../docs/assets/quickstart.mp4): 1920 × 1080, 30 fps, exactly 30.000 seconds, with the original local soundtrack.
- [`../../docs/assets/quickstart.gif`](../../docs/assets/quickstart.gif): silent 960 × 540 README animation, exactly 30 seconds.
- [`../../docs/assets/quickstart-poster.png`](../../docs/assets/quickstart-poster.png): 1080p static preview used for reduced-motion preferences.

The English and Korean READMEs embed the same media.

## Preview and edit

Open `composition/index.html` in OpenDesign or a current browser. The stage scales to the window. The composition provides playback, pause, audio and seeking controls outside its exported frame.

- Append `?poster=1` for the static poster.
- Append `?t=18.65` to inspect the insertion beat.
- Use Space to pause/play and arrow keys to seek by one second.
- In the browser console, call `seek(10.9)` or `window.__timelines.main.seek(10.9)`.

Motion is authored on one deterministic GSAP timeline. `OptionDeckFilm.config` defines the duration, frame rate, dimensions and beat boundaries. The root CSS variables define typography and colors. The source honors reduced-motion preferences with a static preview.

| Time | Beat |
| --- | --- |
| 0–3s | Option key and product introduction |
| 3–7s | Build, open, allow Accessibility |
| 7–13s | Hold Option, find and adjust a slider |
| 13–17s | Two-finger swipe and live app-menu shortcuts |
| 17–24s | Insertion ghost, new tile, resize, remove and reflow |
| 24–28s | Grouped media, music-app choice, Chrome web-app requirement |
| 28–30s | Release Option and return to work |

## Re-export with OpenDesign

Import the contents of `composition/` into an OpenDesign project. Keep `index.html`, `gsap.min.js`, `hyperframes.json`, `meta.json`, and `assets/optiondeck-sound.wav` together. From the project environment provided by OpenDesign, run its local HyperFrames renderer, adapting the composition path to the imported folder:

```sh
"$OD_NODE_BIN" "$OD_BIN" media generate \
  --project "$OD_PROJECT_ID" \
  --surface video --model hyperframes-html \
  --composition-dir "composition" \
  --output "optiondeck.mp4"
```

If OpenDesign returns an asynchronous task, use the `media wait` command it prints. This renderer uses the authored HTML timeline rather than a generative video API. Replace `docs/assets/quickstart.mp4` only after reviewing the new export. The GIF and poster should be regenerated from that same movie so they stay consistent.

The illustrated seek track does not claim support for a particular player's private playback data. The film explicitly states that seeking requires an exposed accessibility slider and that YouTube Music must be installed as a Chrome web app. It is an illustrated product film, not an app latency benchmark.

## Third-party runtime

`composition/gsap.min.js` is GSAP 3.14.2, bundled by OpenDesign. Its original GreenSock copyright, author and [license notice](https://gsap.com/standard-license) are retained in the file. Fonts use system font stacks; font files are not redistributed.
