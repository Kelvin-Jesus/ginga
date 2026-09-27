Run the full check for this repository and fix what fails:

1. `scripts/check-all.sh` (Swift tests, golden-vector freshness, private-API containment, release build, Android tests + `assembleDebug` with JAVA_HOME=/opt/homebrew/opt/openjdk@17). It mirrors CI, which never runs while the repo has no remote.
2. If vectors are stale after a protocol change: `mac/.build/debug/t2m protocol-vectors --out protocol/test-vectors`, then rerun.
3. Report the test counts of both suites and anything you had to change.
