# Parallel agents

Several Claude sessions often work on the same checkout at once: one on `mac/` + `protocol/`, one on `android/`, one on the site and the demo video (`site/`, `video/`, the README, releases). CLAUDE.md "Two agents" covers the protocol hand-over; these are the habits that keep the others' work intact.

- **Look before you commit.** `git status` and `git log -3` before and after; the tree changes underneath you. Files you did not touch are someone else's work in progress.
- **Commit explicit paths only:** `git add <new files>` then `git commit -- <paths>`. Never `git add -A`, never `git commit -a`, never `git commit -- site` when someone else is editing inside `site/`. A swept-in half-finished change goes live the moment `main` is pushed.
- **Never restore or check out files you didn't create** (`git checkout -- f`, `git restore`, `git stash`). One session once "cleaned" its diff that way and silently dropped another's feature.
- **Regenerated files are shared.** `site/src/components/*.jsx` come from `site/design/*.dc.html` through `npm run regen`, which rewrites every generated file. If you only changed the 404, generate only `NotFound.jsx` (`python3 site/tools/prod_patch.py … && python3 site/tools/dc2jsx.py tools/work/NotFound.prod.dc.html …`) so you don't commit someone's half-done home page.
- **Say what you're doing.** Use SendMessage (ListAgents shows the peers) when your work lands, overlaps theirs, or when you spot a problem in their area; don't fix their files yourself. Include file paths and the exact symptom.
- **Delegating.** A background sub-agent gets a self-contained brief: goal, files it may and may not touch (name the ones another agent owns), how to verify, "don't commit". Review its report and screenshots, run `scripts/check-all.sh`, then commit its files yourself.
- **Shared resources.** The Android emulator, adb and Gradle daemons are shared: always pass `adb -s <serial>`, and don't kill processes you didn't start (the demo video's headless Chrome, someone's emulator).
