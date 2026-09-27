# Ginga brand

Ginga is the product's name and the code's: modules, the `ginga` command-line tool, logs and the bundle id (`dev.ginga.Ginga`).
*Ginga* means galaxy in Japanese (銀河) and the sway of capoeira in Brazilian Portuguese: a Galaxy tablet that gives the Mac some swing.

Every mark shares one idea: the tablet sits tilted, off-axis, next to the Mac screen.

## The three marks and where each one goes

| Mark | File | Use |
|---|---|---|
| **A · Órbita**: screen outline, tilted tablet, star | `ginga-app-icon.svg` (tile), `ginga-orbit.svg`, `ginga-orbit-dark.svg` | **App icon** on both apps (`mac/Resources/AppIcon.icns`, Android adaptive icon), site favicon, store listings |
| **B · Monograma “g”**: screen-shaped bowl, S Pen tail | `ginga-monogram.svg`, `ginga-monogram-dark.svg` | **Site details**: section markers, bullets, loading state, social avatars, stickers. Not an app icon |
| **C · Logotipo**: “ginga” in Unbounded ExtraBold, tablet as the dot of the i | `ginga-wordmark.svg`, `ginga-wordmark-dark.svg` | **The brand on the site**: header, footer, hero, press kit |
| **A + C · Assinatura**: the app icon followed by the wordmark, aligned by eye, not by bounding box: the icon is centred on the lowercase letters and a little taller than them, so the i's tablet dot and the g's tail stick out as in type; the frame is trimmed to the drawing | `ginga-lockup.svg`, `ginga-lockup-dark.svg` (composed from the two, not redrawn) | **The repository**: README header, GitHub social preview, docs |

Use the `-dark` files on backgrounds darker than `#6F82FF`. PNG exports are in `png/`.

## Colours

| Name | Hex | Role |
|---|---|---|
| Cobalto | `#2E47F5` | Primary; the app-icon tile; the tablet on light backgrounds |
| Noite | `#141830` | Ink: outlines and wordmark on light backgrounds; dark backgrounds |
| Estrela | `#F2A900` (light) / `#FFC43D` (on cobalt or dark) | The star only, never text or large areas |
| Névoa | `#F2F3F8` | Light background |
| Cobalto noturno | `#6F82FF` | The tablet and accents on dark backgrounds |

Stay away from Samsung's blue (`#1428A0`) and from Apple's gradients: the brand must not look affiliated with either.

## Type

- Display and wordmark: **Unbounded** (SIL OFL 1.1), ExtraBold for the wordmark, SemiBold for headings.
- Body: **Figtree**. Numbers and specs: **IBM Plex Mono**.

## Rules

- Clear space around A and B: at least the star's width on every side. Around C: the height of the tablet dot.
- Minimum size: A 16 px (the favicon drops the star below 20 px if it muddies), B 20 px, C 80 px wide.
- Don't straighten the tablet, recolour the star, add shadows or gradients, or set “ginga” in another face.
- In copy, “Galaxy”, “Samsung”, “Mac” and “Sidecar” are third-party marks: descriptive use only (“for Mac”, “works with Galaxy Tab”), never inside the name or logo.

## Regenerating

```sh
python3 -m venv /tmp/v && /tmp/v/bin/pip install fonttools resvg_py
curl -L -o /tmp/Unbounded.ttf "https://github.com/google/fonts/raw/main/ofl/unbounded/Unbounded%5Bwght%5D.ttf"
/tmp/v/bin/python brand/tools/wordmark.py /tmp/Unbounded.ttf   # outlines the wordmark SVGs
/tmp/v/bin/python brand/tools/export.py                        # png/ and mac/Resources/AppIcon.icns
```

The Android launcher icon is a hand-written vector copy of mark A (`android/app/src/main/res/drawable/ic_launcher_foreground.xml`, `ic_launcher_monochrome.xml`); change it together with `ginga-app-icon.svg`.
