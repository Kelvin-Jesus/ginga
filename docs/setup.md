# Setup: Mac + Galaxy Tab S11

This guide gets you from nothing to the tablet showing a second Mac display. **Direct USB (3b)
is the recommended link**: no developer mode, and the steadiest stream (at 120 Hz: 120 fps with
no dropped frames, end-to-end 12–13 ms). USB through adb (sections 1–3) works too, but adb's relay
drops about 1.7 % of frames at 120 Hz. Wi‑Fi (3c) is for when there's no cable.

## 1. On the Mac

1. **Build or install Ginga.** From source:

   ```sh
   cd mac
   scripts/create-dev-signing-identity.sh   # once: a stable identity keeps permissions across rebuilds
   scripts/build-app.sh                     # → mac/build/Ginga.app and mac/build/ginga
   ```

2. **Install adb.** Ginga uses your adb and never bundles Google's:

   ```sh
   brew install android-platform-tools
   ```

3. **Open Ginga.** It lives in the menu bar and opens its control panel on first launch.
4. **Grant Screen & System Audio Recording** when asked, or use Control Panel › Status › Grant…. Ginga captures **only its own virtual display**. Quit and reopen the app after granting.
5. **Optional: grant Accessibility** for touch and S Pen control (Control Panel › Tablet › "Touch & S Pen control: Grant…"). Without it the tablet is display-only.

## 2. On the Tab S11

1. **Turn on USB debugging.**
   - Settings › About tablet › Software information › tap **Build number** 7 times.
   - Then Settings › Developer options › **USB debugging**.
   - Samsung *Auto Blocker* blocks USB commands. If it is on, turn it off for the setup (Settings › Security and privacy › Auto Blocker).
2. **Install the Ginga app.** Either build it yourself (`cd android && ./gradlew assembleDebug`, see [android/README.md](../android/README.md)) or use the APK you were given:

   ```sh
   adb install -r android/app/build/outputs/apk/debug/app-debug.apk
   ```

3. **Connect the USB‑C cable** and accept "Allow USB debugging?" on the tablet. Tick "Always allow from this computer".

## 3. Connect

1. In Ginga on the Mac, turn on **Accept the tablet over USB** (Control Panel › Tablet). It then keeps `adb reverse` in place automatically, including after replugging.
2. On the tablet, open **Ginga** and tap **Connect**.
3. A "Galaxy Tab S11" display appears on the Mac, and the tablet shows it. Drag windows onto it, or arrange it in System Settings › Displays.

When the tablet disconnects, the display disappears after 15 s and macOS moves its windows back, as with Sidecar. Reconnect within those 15 s and nothing moves.

## 3b. Direct USB, no developer mode (beta, M6)

With direct USB, the tablet needs neither USB debugging nor adb. Ginga asks Android to switch the USB connection into *accessory mode*, and Android opens Ginga by itself.

1. Control Panel › Tablet › **Direct USB — no developer mode** is on by default.
2. Your tablet appears in the list below it. Click **Use this tablet**. Only tablets you approve are ever switched.
3. On the tablet, Android asks *"Open Ginga when this USB accessory is connected?"*. Tick **Always** and tap OK. The display starts on its own.

From then on, plugging in the tablet is enough. To leave accessory mode, unplug the cable. `mac/build/ginga usb` lists Android devices and whether they support accessory mode, without changing anything.

## 3c. Wi‑Fi (beta, M7)

1. Control Panel › Tablet (Wi‑Fi, beta) › turn on **Accept paired tablets over Wi‑Fi**. macOS asks once for Local Network access; allow it.
2. On the tablet, in Ginga's Wi‑Fi list, pick the Mac (both on the same network) and tap **Connect**.
3. The first time, both screens show a 6-digit code. Check that they match, then confirm on both. Ginga never asks you to type a code, and a code that differs means something is between the devices: decline.

Paired tablets are listed in the control panel; **Forget** ends a tablet's session and makes it pair again. The stream is encrypted (TLS 1.3), and each side pins the other's certificate.

## 3d. No router: hotel, train, no internet

The tablet creates its own Wi‑Fi network and the Mac joins it. **While connected this way, the Mac is off its usual Wi‑Fi network**, so it has no internet over Wi‑Fi unless it is also on Ethernet. It goes back to its previous network when you end, or when the tablet leaves.

1. Once, beforehand: connect the tablet by USB or Wi‑Fi. That hands it a key only these two devices share.
2. On the tablet: **Direct connection (no router)**. It creates the network and waits.
3. On the Mac: Control Panel › No router › **Connect directly to the tablet**. The first time, macOS asks for Bluetooth (to find the tablet and receive the network's password, encrypted) and Location (macOS requires it to see and join Wi‑Fi networks). Allow both.
4. The stream starts as over any Wi‑Fi: encrypted (TLS 1.3), with the pairing you already have. **End direct connection** takes the Mac back to its network.

Nothing to type: the password is new every session and never shown.

## 3e. Keyboard cover, other devices

- **A keyboard attached to the tablet** (Book Cover Keyboard, Bluetooth or USB) types on the Mac while the stream is in front, like an iPad keyboard with Sidecar. The Mac's keyboard layout applies (choose the one printed on the keyboard, e.g. Brazilian ABNT2). ⊞/Samsung is ⌘; Control Panel › Tablet can put ⌘ on Ctrl instead. The cover's **touchpad** moves the Mac pointer (Android's own arrow is hidden over the stream), taps click, and two fingers scroll, with inertia.
- **Fingers**: by default a finger is a mouse (tap clicks). "One finger: Only scrolls" makes it work like Sidecar, where fingers scroll and the pen points.
- **Other Samsung devices and phones** work the same way: the display takes the device's panel (a Tab S9 FE+ gets 2560×1600 up to 90 Hz, an S25 Ultra 3120×1440 up to 120 Hz). Direct USB needs no setup on any of them; the tablet app is the same APK.

## 4. Settings worth knowing

| Where | Setting | Default | Why |
|---|---|---|---|
| Control Panel › Display | Resolution | 1280×800 @2x (pixel-exact on the Tab S11) | "More space" options are downsampled for the tablet |
| Control Panel › Display | Refresh rate | **60 Hz** | Uses about a third of the power of 120 Hz. 120 Hz is smoother (120 fps, 2.7 ms display → decoded on the Mac) and costs about 0.8 W more on the Mac |
| Control Panel › Display | Use 60 Hz on battery (shown at 120 Hz) | On | 120 Hz on the power adapter, 60 Hz on battery. The switch happens live on the same display, and the tablet's panel follows |
| Control Panel › Power | Video encoder | Automatic | Lowest latency on the power adapter; about 40 % less encoder power on battery, for +6 ms |
| Tablet › Settings | Preferred refresh rate | Let the Mac decide | |
| Tablet › Settings | Faster decoding | Off | About 3 ms less decode latency, at some battery cost |

## 5. Cables

Any USB‑C cable with data works. A Thunderbolt 4 or USB 3 cable has far more bandwidth than the stream needs: 120 fps at 2560×1600 averages about 20–30 Mbit/s. The link's latency is the same either way, and the cable also charges the tablet from the Mac (see below). Plug the tablet straight into the Mac rather than through a hub or dock: some hubs block the vendor requests used by direct USB (AOA).

## 6. Battery tips

- **Over the cable, the tablet charges from the Mac.** That draws far more than Ginga itself. Samsung's "Protect battery" (charges to 80–85 %) limits it, or plug the Mac into power.
- **A still screen costs nothing.** Ginga sends frames only when something changes. When the tablet's app is in the background or its screen is off, the Mac stops capturing.
- **External monitors.** Adding the tablet's display can make macOS switch another external monitor to a different mode. macOS stores one configuration per set of displays; HiDPI modes of the other monitor may be unavailable while a HiDPI tablet display exists. Pick the mode you want in System Settings › Displays while the tablet is connected, and macOS remembers it for that combination.

Problems? See [troubleshooting.md](troubleshooting.md).
