# Quickstart motion graphic

A 30-second illustrated walkthrough, generated without reading the desktop, user settings, browser content, or app menus. English headings and Korean captions are baked into the media. The README uses a static poster for reduced-motion preferences.

Scene timing:

| Time | Explanation |
| --- | --- |
| 0–5s | Clone, build, open |
| 5–10s | Grant Accessibility |
| 10–15s | Hold Option and adjust with the trackpad |
| 15–20s | Swipe pages and read live app-menu shortcuts |
| 20–25s | Insert, resize, remove a feature |
| 25–30s | Choose music, Chrome-installed YouTube Music, release Option |

Regenerate on macOS with Python 3 + Pillow and the Swift toolchain:

```sh
python3 scripts/motion/render_quickstart.py
swiftc -parse-as-library scripts/motion/encode_video.swift -o .build/encode-quickstart
.build/encode-quickstart
```

The Python renderer writes temporary PNG frames beneath `.build/` and a 30-second GIF plus poster into `docs/assets/`. The Swift encoder uses AVFoundation to produce an H.264 MP4. System fonts are read locally; their font files are not redistributed. Generated assets contain no personal screenshots. The GIF and MP4 demonstrate the workflow; they are not performance benchmarks.
