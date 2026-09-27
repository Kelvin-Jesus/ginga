# Site

`site/` is an Astro site (pt/en) published by `.github/workflows/site.yml` to GitHub Pages at `/ginga/`, together with the design system page (`/design-system/`, see [design and brand](design-and-brand.md)). `site/README.md` has the commands.

## Publishing

- **Pushing `main` deploys.** Any commit under `site/` that reaches `main` is live a minute later. Show the maintainer a local preview or screenshots first and wait for their go-ahead ([working with the maintainer](working-with-the-maintainer.md)).
- Build with the Pages settings to catch path bugs: `BASE_PATH=/ginga/ SITE_URL=https://kelvin-jesus.github.io PUBLIC_REPO_URL=https://github.com/Kelvin-Jesus/ginga npm run build`, then `npx astro preview`.
- Sections reveal on scroll: in a hidden browser pane they screenshot blank. Read the text (`innerText`) or scroll them into view with the pane visible.

## Generated code

- The source of truth is `site/design/Main.dc.html` and `404.dc.html` (design-editor prototypes). `npm run regen` turns them into `src/components/*.jsx` and `src/styles/*.css`; `tools/prod_patch.py` applies the production differences. Never edit the generated `.jsx` by hand.
- Assets are referenced as `/_blob/<md5>` in the prototypes and mapped to files in `public/assets/` by `tools/blobs.json`; a `"/_blob/<id>"` literal in the logic becomes `base + "assets/<file>"`.
- Regen rewrites every generated file: mind [parallel agents](parallel-agents.md).

## Browser behaviour that bit us

- **Audio needs a gesture.** No browser lets a page make sound before the visitor clicks, taps or presses a key on it (a reload doesn't count). On touch screens only the end of a tap counts (`pointerup`, `touchend`, `click`), not `pointerdown`.
- **Firefox/Zen start a Web Audio context "suspended"** and move it to "running" a moment later, even when allowed. Create one context and `resume()` it inside the gesture; don't close and recreate a suspended one (you can kill one that was about to play).
- The 404's sound is synthesized live from the animation's state (no files), so it stays in sync on any screen size and can join late; it stops when the animation stops and the context is suspended afterwards ([power](power.md)).
- The astronaut cursor's click point is its helmet visor, the middle of the body, not a corner of the sprite.
