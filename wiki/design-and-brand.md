# Design and brand

- **Sources.** The design system was made in Claude (claude.ai/design) and lives in `design/ginga-design/` (read `HANDOFF.md`): brand book, flows, `tokens.json`, component notes and their exact live previews. The brand assets (logos, app icon, fonts, colour rules) are in `design/brand/`. Use the tokens; don't invent colours, radii, spacing or durations.
- **One shareable page.** `design/ginga-design/ginga-design-system.html` is the whole system on one self-contained page (opens offline, served at `/design-system/`). After changing any source in that folder, run `python3 design/ginga-design/tools/export_html.py`. The claude.ai viewer's own UI is Anthropic's code and must not be copied into this public repo: the page has its own frame around the same content.
- **Generated theme code.** `mac/Sources/GingaApp/Design/GingaTheme.swift` is generated from `tokens.json`; don't edit it by hand. Android's tokens are in `res/values/ginga_*.xml`.
- **Themes.** Claro, Escuro and Black espacial (pure black areas, outlines and glow instead of grey surfaces; apps only, never the site). Every screen is checked in all three.
- **Phones and tablets.** The Android app is tablet-first; phone layouts come from resource qualifiers (`values-sw600dp`, `layout-w600dp` keep the tablet values), and the tablet must render pixel-identical after a phone change ([device testing](device-testing.md)).

## Align by eye, not by the box

The maintainer's rule: visual alignment matters more to the user than mathematical alignment.

- Centre an icon on the lowercase body of the text next to it, a little taller than the letters; let ascenders, descenders and the i's tablet dot stick out, as in type.
- Compensate visual weight: a solid tile on one side pulls a centred lockup toward it, so shift the composition partway (about half) toward its centre of mass, not all the way.
- Render a few candidates side by side, in light and dark, and pick the one that looks right. Record the rule next to the asset (`design/brand/README.md` describes the README lockup).
