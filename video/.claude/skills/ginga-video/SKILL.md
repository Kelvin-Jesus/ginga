---
name: ginga-video
description: Make, change or render the Ginga demo videos in video/ (Remotion) and the teaser on the site. Use for GingaHero, GingaVertical, GingaLoop, GingaTeaser, GingaKeynote (3D), their sound, renders, web encodes and the black-hole teaser on the site top. Covers the brand rules, the frame-driven architecture, commands and the traps we already hit.
---

# Ginga videos (Remotion)

Read `video/README.md` first, then the design system in `design/ginga-design/` (`brand-book.md`, `tokens.json`, `components/DitherSpace.md`). For general Remotion practice, install the official skills with `npm run skills` in `video/` (they come from `remotion-dev/skills`, pinned in `skills-lock.json`; not vendored because that repo has no license). The rules that matter most: `remotion-markup` (3d.md, motion-blur.md, effects.md, sfx.md) and `remotion-render`.

## Brand rules (non-negotiable)

- Colours only from `tokens.json`: cosmos `#0A0C1C` (never pure `#000` in videos), Noite `#141830`, Cobalto `#2E47F5`, Cobalto noturno `#6F82FF`, Estrela `#FFC43D`, Névoa `#F2F3F8`. No purple gradients, no Samsung blue `#1428A0`.
- Type: Unbounded 600/800 (titles), Figtree (text), IBM Plex Mono (numbers, specs). Loaded with `@remotion/google-fonts` in `src/fonts.ts`.
- Logos from `public/logos/*-dark.png` on dark backgrounds. Never straighten the tablet of the logo, recolour the star or put anything over the logo.
- "Mac", "Galaxy Tab", "Samsung" only as descriptive text. Devices are generic (CSS or rounded boxes), no Apple/Samsung shapes or logos.
- Motion: calm, overshoot-and-settle (`ease-ginga` = `cubic-bezier(0.34,1.36,0.64,1)`), no shake/glitch/flash in the 2D videos. All on-screen text comes from `src/i18n.ts` (pt and en).

## Architecture

- Everything is a pure function of the frame. No `Math.random()` at render time (use `random(seed)` or `src/lib/rng.ts`), nothing accumulates between frames, no `useFrame` clock in three.js. Remotion renders frames in parallel and out of order.
- `src/timeline.ts` + `src/World.tsx`: Hero and Vertical are the same `World` with different timelines/layouts. Tweak timing there.
- `src/components/DitherBlackHole.tsx`: port of `Ginga.blackHole()` (DitherSpace). `drawBlackHole()` is reusable as a canvas texture. Loops use `cycle` + integer turns so the last frame joins the first.
- `src/keynote/`: GingaKeynote (3D). `poses.ts` (camera keys and device poses), `timing.ts` (shots, hits), `Shots.tsx` (the six shots), `PostFX.tsx` (the post chain), `GingaKeynote.tsx` (`SFX` list, motion-blur windows `FAST`).

## Commands (in `video/`)

```sh
npm run studio                 # preview
npm run render:keynote:proxy   # 1280×720, iterate here first
npm run render:keynote         # ProRes 4444 masters, then H.264 CRF 16 from the master
npm run sfx                    # re-synthesize public/sfx/*.wav
npx remotion render GingaKeynoteAudio out/keynote-audio.wav --codec=wav   # sound only, ~5 s
npx remotion still src/index.ts GingaKeynote-pt out/x.png --frame=250 --scale=0.5   # a 1080p still
```

Swap only the sound of an already rendered video (no 3D re-render): render `GingaKeynoteAudio`, then `npx remotion ffmpeg -i video.mp4 -i out/keynote-audio.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k -shortest out.mp4`.

Web version for the site: `-vf scale=1920:1080:flags=lanczos -c:v libx264 -preset slow -crf 26 -maxrate 9M -bufsize 18M -c:a aac -b:a 160k -movflags +faststart` from the master, copy to `site/public/assets/ginga-keynote-{pt,en}.mp4`, and bump `VIDEO_VERSION` in `site/src/components/KeynoteTeaser.jsx`.

## Traps we already hit

- **`@react-three/postprocessing`'s `EffectComposer` renders blank (white) headless.** `PostFX.tsx` builds the `postprocessing` composer by hand and calls `composer.setSize(w, h)` explicitly. Keep it that way.
- **WebGL needs `Config.setChromiumOpenGlRenderer("angle")`** (already in `remotion.config.ts`).
- **`CameraMotionBlur` mounts 6 WebGL canvases per frame**: renders time out at the 30 s default. Keep `--timeout=180000` and keep the `FAST` windows short. Motion blur must not straddle a camera jump (it averages sub-frames of both poses).
- **drei `RenderTexture` renders 3D only, not HTML.** Device screens and titles are drawn in canvas 2D (`screens.ts`, `HeadlineReveal.tsx`) and uploaded as `CanvasTexture`. Titles live in an overlay scene rendered after the depth of field, so they stay sharp while the devices rack-focus behind them.
- **Images for a canvas texture**: use drei `useTexture` (it suspends, and `ThreeCanvas` waits). A manual `new Image()` with `delayRender` drew before load.
- **`useLayoutEffect` in a component that returns `null`** still runs: guard refs.
- **The remotion ffmpeg build has no `volumedetect`/`xstack`.** Measure with `node scripts/loudness.mjs out/keynote-audio.wav 0:10 3.6:4.3`. The mix has a `MASTER` gain; keep peaks below about −2 dB.
- **An audio-only render of the 3D composition still renders frames.** Use the light `GingaKeynoteAudio` composition.

## The site teaser

`site/src/components/KeynoteTeaser.jsx` + `site/src/styles/teaser.css` (see `site/README.md` › Teaser). `GingaSite.jsx` is generated by `npm run regen` from `site/design/*.dc.html` through `tools/prod_patch.py`: never edit the generated `.jsx`. Put production changes in `prod_patch.py` (and write the output only after all `rep()` calls). The 404 (`NotFound.jsx`, `design/404.dc.html`) belongs to its own work; don't restore or regenerate it blindly.

## Publishing

Commit with explicit paths (`git commit -- <paths>`), end messages with the Co-Authored-By trailer, and don't commit `video/out/` (ignored), `.agents/` or the `remotion-*` skill links (installed by `npm run skills`). Pushing `main` publishes the site through `.github/workflows/site.yml`.
