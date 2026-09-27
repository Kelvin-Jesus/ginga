# Ginga wiki: what every agent should know

The shared memory of the agents (and people) who work on Ginga: the lessons that cost real time and are not visible in the code. Read it after [CLAUDE.md](../CLAUDE.md), before your first change.

| Page | Read it when |
|---|---|
| [Working with the maintainer](working-with-the-maintainer.md) | always: language, autonomy, what needs a "yes" first |
| [Parallel agents](parallel-agents.md) | always: another session is often editing the same checkout |
| [Dev environment](dev-environment.md) | building or testing on the Mac (toolchain quirks, logs, signing) |
| [Device testing](device-testing.md) | anything on a real tablet or phone |
| [Power](power.md) | touching capture, encode, transport, rendering or defaults |
| [Displays](displays.md) | anything that creates or configures displays |
| [Releases](releases.md) | publishing a version or updating someone's device |
| [Site](site.md) | the website, the 404, GitHub Pages |
| [Design and brand](design-and-brand.md) | UI, logos, the design system |

How this relates to the rest:

- `CLAUDE.md` holds the commands, the map, the invariants and the "never do" list. This wiki does not repeat them; it explains the why behind some and adds what doesn't fit there.
- `docs/` is the product documentation (architecture, status, known issues, performance). A bug and its rule go to `docs/known-issues.md`; a working habit or a trap in the tooling goes here.

Keep it alive:

- Learned something non-obvious that the next agent will trip over? Add it to the page it belongs to, in the same change as the code. One fact once, where it will be looked for; link instead of copying.
- Correct or delete what turns out to be wrong. Date statements that can go stale ("measured 2026‑09‑26").
- This repository is public: no serial numbers, personal names, e-mail addresses, key paths or passwords.
