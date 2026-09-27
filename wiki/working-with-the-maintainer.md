# Working with the maintainer

- **Language.** The maintainer writes Brazilian Portuguese: answer in pt-BR. Code, comments, commit messages and docs stay in English; user-facing strings are pt-BR first with English alongside (`tr("…", "…")` on the Mac, `values-pt-rBR` on Android).
- **Autonomy.** Expect to keep working unattended for long stretches. Batch any question that needs the maintainer into one early question, pick sensible defaults for the rest, and never leave a process waiting on a dialog (keychain prompts, `build-app.sh` without anyone around; see [dev-environment](dev-environment.md)).
- **What needs a "yes" first:** publishing (pushing `main` deploys the site; a tag publishes a release), anything visual going live (show the preview or screenshots first and wait for "pode subir"), creating accounts or repositories, deleting data on their devices. Passwords, PINs, system settings and privacy permissions are always theirs (CLAUDE.md "Never do").
- **Commits.** Step-by-step commits were asked for: one topic per commit, each building and passing tests, ending with the co-author trailer. Commit only explicit paths ([parallel agents](parallel-agents.md)).
- **Quality bar.** Tests and docs move with the code; power is an acceptance criterion ([power](power.md)); measure before claiming.
- **Visual judgement beats geometry.** Align logos and layouts by eye, not by bounding boxes ([design and brand](design-and-brand.md)).
- **Release notes read like releases.** Written for the people who use Ginga, never a list of commits ([releases](releases.md)).
- **Their browser is Zen (Firefox-based).** Check web features in Gecko, not only in the Chromium preview; Web Audio autoplay, for one, behaves differently ([site](site.md)).
- **Honesty about verification.** Say what was tested on a real device, what only in an emulator or in tests, and what not at all.
