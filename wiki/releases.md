# Releases

The mechanics are in `docs/development.md` › Releases; this is how to do it right.

## Publishing a version

1. Write `docs/releases/vX.Y.Z.md`: **what's new for the people who use Ginga**, pt-BR first with an English `<details>` block, plus a "Bom saber" list of limits that are still true. Never a list of commits, never internal jargon. Say what was tested on real devices and what only in an emulator.
2. Commit it, push `main`, then push the tag `vX.Y.Z`. `.github/workflows/release.yml` checks the notes exist, builds the release-signed APK and the universal (arm64 + x86_64) `Ginga.app` in a `.dmg`, and publishes both with `SHA256SUMS` and the install steps from `.github/release-notes.md`.
3. Download what was published and check it: `shasum -a 256 -c SHA256SUMS`, `lipo -archs`, `codesign -dvv` (Authority "Ginga Release"), `aapt dump badging` for the version.

Rules:

- Publishing needs the maintainer's go-ahead ([working with the maintainer](working-with-the-maintainer.md)).
- **A pushed tag is final.** Deleting or moving tags is a destructive operation the harness refuses. If a release fails on a tagged commit, fix it and ship the next patch version (that's why `v0.1.0` has no release).
- CI runners are slower than the dev Mac: timing-dependent tests that pass locally can fail there. Make them deterministic (count events instead of racing a clock) rather than raising timeouts.
- Versions come from the tag: `versionCode`/`CFBundleVersion` = X·10000 + Y·100 + Z.

## Signing

- Android: one release key for the life of the app. An APK signed with another key cannot update an installed copy; losing the key means everyone has to uninstall. The Mac: a self-signed "Ginga Release" identity (no Developer ID, not notarized), so Gatekeeper asks once but privacy grants survive updates.
- Both keys and their password are the maintainer's, stored outside the repo and in GitHub secrets (set by `scripts/setup-release-signing.sh`, which they run themselves). Agents never see or handle the password, so **only CI can produce release-signed builds**.

## Updating someone's device

- Install the published APK over the old one (`adb install -r`), or have them open the latest release on the device and tap Update. Data is kept.
- Don't install a debug build over a release build: it needs an uninstall (data lost) and blocks the next release update.
- A phone in direct-USB (AOA) mode may not show up in adb at all ([device testing](device-testing.md)).
