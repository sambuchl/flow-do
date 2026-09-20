# FlowDo: quick test and run guide

This guide is for someone testing FlowDo on a Mac. It assumes the repository
folder is named `FlowDo` and that Xcode is installed.

## 1. Open the project

Open Terminal and enter the repository using paths relative to this file:

```sh
cd ../..
open macos/FlowDo.xcodeproj
```

If your Terminal is not currently in `FlowDo/docs`, use the full path to the
repository instead, for example `cd /path/to/FlowDo`.

In Xcode, choose:

- Scheme: **FlowDo**
- Destination: **My Mac**

Do not open `Package.swift` for the menu-bar app. The app is in
`macos/FlowDo.xcodeproj`.

## 2. Test the project

From the repository root (`FlowDo`), run:

```sh
xcodebuild -project macos/FlowDo.xcodeproj -scheme FlowDo \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath macos/DerivedData \
  CODE_SIGNING_ALLOWED=NO build test
```

Wait for `** TEST SUCCEEDED **`. This builds the app and runs the native tests;
it does not launch FlowDo.

The same action in Xcode is **Product → Test** or **⌘U**.

## 3. Run FlowDo

After the test succeeds, launch the built app:

```sh
open macos/DerivedData/Build/Products/Debug/FlowDo.app
```

The same action in Xcode is **Product → Run** or **⌘R**. FlowDo is a menu-bar
application, so look for its orb in the menu bar rather than a Dock window.

If the Run button is gray, select the **FlowDo** scheme and **My Mac** in the
Xcode toolbar. A successful build alone is not enough when a library or test
target is selected; Xcode must have the app scheme selected for Run.

## 4. Try the main features

Click the orb and start one task. Then check:

1. The orb progresses red → yellow → green while you work.
2. Reengagement and state changes use three-second whirlpool transitions.
3. After the idle grace period, timers pause and the orb steps back one color.
4. **Task Complete!** shows the heart-and-flame completion effect.
5. Preferences contains the badge position, idle grace, checkpoint interval,
   pulse, and optional local activity logging controls.
6. The task badge can be dismissed and restored from the menu.

For fast manual testing, enable **Fast thresholds for testing** in Preferences.

## Useful Xcode commands

| Action | Xcode | What it does |
| --- | --- | --- |
| Build | ⌘B | Compiles without launching |
| Test | ⌘U | Builds and runs the test suite |
| Run | ⌘R | Builds and launches FlowDo |
| Stop | ⌘. | Stops the app launched by Xcode |
| Clean build folder | ⇧⌘K | Removes compiled output for a fresh build |

For the shared core tests only, from the repository root:

```sh
cd macos
swift test
cd ..
```

This tests the portable core and persistence code; it does not launch the
menu-bar application.

## If something goes wrong

Quit any existing FlowDo copy before launching another one. If a build behaves
stale, use **Product → Clean Build Folder**, then run the `xcodebuild` command
again. The build products and test results are under `macos/DerivedData/`.

FlowDo does not need the Flask server, an account, or a network connection for
the native app and its tests.
