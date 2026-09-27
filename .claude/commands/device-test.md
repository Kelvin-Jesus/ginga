Verify a change on the real Mac + Galaxy Tab S11 (read CLAUDE.md "Working on the device" first):

1. `adb devices` shows R52Y80EE15V; `adb shell dumpsys window | grep isKeyguardShowing` is false (else ask the user to unlock; never enter the PIN).
2. Build: `cd mac && scripts/build-app.sh` only if the user can answer a keychain prompt; `cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug && adb install -r app/build/outputs/apk/debug/app-debug.apk`.
3. Launch with a scratch copy of a checked-in example (never the user's config): `cp config/examples/galaxy-tab-s11.json "$TMPDIR/ginga-device-test.json"`, then `open mac/build/Ginga.app --args --background --config "$TMPDIR/ginga-device-test.json"`.
4. Evidence: `/usr/bin/log show --last 30s --info --predicate 'subsystem == "dev.ginga"'` (stream.report, stream.closed), `adb logcat | grep Ginga/`, `adb exec-out screencap -p`.
5. Pass only if: `stream.report` appears with the expected fps/size, no unexpected `stream.closed`, and the tablet shows the Mac screen (screencap). Anything else is a fail with the log excerpt.
6. If the change touches the video pipeline and the user is present: `scripts/check-power.sh`.
7. Record the result in docs/status.md with this block:

   ```
   Device test <YYYY-MM-DD> — <change>
   Build: mac <commit/dirty>, apk <commit/dirty>; config: <example file>
   Scenario: <what was done>
   Result: PASS|FAIL — <criterion that decided>
   Evidence: <1–3 log lines from dev.ginga / Ginga/>
   ```
