# FlowDo

A small macOS menu-bar app for one question: **What are you doing now?**
Set one task, work normally, and watch the orb move from red to yellow to green.
FlowDo works locally without an account, server, or internet connection after setup.

## Get ready

You need a Mac running **macOS 13 or later** and **Xcode 15 or later**.
Install the full Xcode app from the Mac App Store, open it once, and finish any
first-launch setup. Command Line Tools alone cannot build the app.

## Clone, build, and test

Open Terminal and paste:

```sh
git clone https://github.com/sambuchl/flow-do.git FlowDo
cd FlowDo
xcodebuild -project macos/FlowDo.xcodeproj -scheme FlowDo \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath macos/DerivedData CODE_SIGNING_ALLOWED=NO build test
```

Wait for **TEST SUCCEEDED**. This builds FlowDo and runs its tests.
These local build commands do not require a paid Apple Developer account.

If Terminal says Xcode is not selected, run this and retry the build:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

If you installed Xcode elsewhere, substitute its actual path.

## Run

From the same Terminal, still inside the `FlowDo` folder:

```sh
open macos/DerivedData/Build/Products/Debug/FlowDo.app
```

Look for the small orb in your **menu bar**. FlowDo does not open a regular
app window or appear in the Dock.

Prefer Xcode? Run `open macos/FlowDo.xcodeproj`, select the **FlowDo** scheme
and **My Mac**, then use **⌘U** to test or **⌘R** to build and run.
Open the project, not `Package.swift`. See the
[Xcode guide](docs/xcode_overview.md) for more detail.

## Try it out

1. Click the orb, enter a task, and start working.
2. Open **Preferences** and enable **Fast thresholds for testing** to reach green
   after about 20 seconds of activity.
3. Try the task badge: drag the top handle to move it, drag the lower-right grip
   to resize it, or dismiss it with × and restore it from the menu.
4. Try **Background music → Choose MP3…** to loop a local track.
5. Stop interacting for a while. Each idle interval moves the orb back through
   yellow, red, and a dimmed break state. Timers freeze after the first interval.
6. Try **Pause FlowDo**, resume, and **Task Complete!**.

Turn off fast thresholds when you want to use FlowDo normally. Local activity
logging is optional and off by default.

## Update or report a problem

Quit FlowDo from its menu before testing a new build. From the `FlowDo` folder,
run `git pull --ff-only`, then repeat the build/test and run commands above.

If something fails, [open an issue](https://github.com/sambuchl/flow-do/issues)
with your macOS and Xcode versions, what you tried, and what happened.
For build failures, include the first error shown in Terminal. Avoid posting
private task names or activity logs.

The latest UI and audio changes still need testing on Macs. Development details,
feature behavior, server setup, and verification history are in
[project-state.md](project-state.md). A fuller
[manual testing checklist](docs/verification.md) is also available.

## License

FlowDo is **source-available for noncommercial use** under the [PolyForm
Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0).

You may use, study, modify, fork, and distribute FlowDo for noncommercial
purposes subject to the terms in the [`LICENSE`](LICENSE) file.

**Commercial use requires a separate license.** If you'd like to use FlowDo
commercially, please contact **Sam Buchl on GitHub**.

Contributions are welcome. For substantial contributions, FlowDo may require a
Contributor License Agreement (CLA) so the project can continue to be offered
under both noncommercial and commercial licenses.

Copyright © 2026 Samuel C. Buchl.
