Verify a change on the real Mac + Galaxy Tab S11 (read CLAUDE.md "Working on the device" first):

1. `adb devices` shows R52Y80EE15V; `adb shell dumpsys window | grep isKeyguardShowing` is false (else ask the user to unlock; never enter the PIN).
2. Build: `cd mac && scripts/build-app.sh` only if the user can answer a keychain prompt; `cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug && adb install -r app/build/outputs/apk/debug/app-debug.apk`.
3. Launch with a scratch config (never the user's): `open mac/build/Tab2Mac.app --args --background --config <scratch>.json`.
4. Evidence: `/usr/bin/log show --last 30s --info --predicate 'subsystem == "dev.tab2mac"'` (stream.report, stream.closed), `adb logcat | grep T2M/`, `adb exec-out screencap -p`.
5. Record the result in docs/status.md (and performance.md for numbers).
