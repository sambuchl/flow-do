# Verification

## Executed in Linux Docker

The six Python unittests cover the health response, factory/extension boundaries,
isolated test engines, missing browser/API routes, method headers and sanitized
500 errors. In-memory TestConfig does not use the production database.

Flask-Migrate init, upgrade and schema check succeeded on development SQLite.
Dependency consistency passed with pip check. Xcode project syntax was parsed
and all source/object and scheme target references were checked, without
compiling Swift. These commands ran inside the
provided container; a separate Docker Compose build was not possible because no
Docker CLI/daemon is provided.

## Native verification

The user supplied a successful Xcode test run on 2026-09-19: all original 16 tests
passed, and reported that the original app worked. The new idle/pulse revision
has not been compiled or tested on a Mac yet.

Twenty fake-clock engagement tests now cover initial idle, ignoring old activity,
returning/engaged progression and exact thresholds, short and
reading pauses, long inactivity and returning, sleep, explicit reset, debug
thresholds, invalid sensor values, single-fire pink at green, custom checkpoint
crossings/reset, disabled checkpoints, no missed achievements after sleep,
recurring intervals, invalid intervals, and summed credits across idle sessions.

Six async local-storage tests cover fresh launch, restart restoration, task
change identity, completion and next task, corrupt-file preservation and empty
title validation. The shared Xcode scheme includes these tests; Swift Package
Manager can also run the same core/storage tests without the UI.

Eight logging/time tests cover default-off behavior, paired task/session spans,
mid-session opt-in offsets, renames, ordered/lazy JSONL writing, partial-write
recovery, file errors and aggregate restoration. The native suite now has 40
tests; this revision still requires Xcode compilation and execution.

Four Python report tests ran successfully in Linux:
`python3 -m unittest discover -s scripts -p 'test_*.py' -v`.
These cover paired/interleaved spans, interrupted sessions, malformed records,
and terminal-safe task text. They do not substitute for the native tests.

## Required Mac acceptance

1. Build and test using the README commands. Verify the orb appears without a Dock icon.
2. Click the orb; start “Prepare TAC slides”. Quit/relaunch and verify restoration and idle state.
3. Change its title, then Task Complete!; relaunch and verify there is no current task. Start another.
4. Enable fast thresholds. Work in another app with keyboard, mouse movement,
   clicks and scrolling; verify a three-second red/yellow swirl, yellow, then a brief
   yellow/green swirl at green (~20s), with no pink/red outline afterward.
   Continued activity stays green.
   Set a checkpoint every 1 minute and keep working; verify pink each minute, then green again.
   Try every 10 seconds using the radio buttons. Test 0/blank, invalid input, and
   settings persistence. Reengagement after idle can earn milestones anew.
5. With default idle grace, verify 59 seconds of inactivity still counts. At 60
   seconds, both timers freeze and green swirls to yellow (or yellow to red) over
   three seconds. From green, 120 seconds of idle reaches red and 180 seconds
   reaches dim yellow break. Resume input: counters continue
   from frozen values. Repeat with a short custom grace and check its exact cutoff.
6. Pause: no state progression. Resume: fresh returning after activity. Lock,
   switch session, and sleep/wake: no accumulated inactive time.
7. Check light/dark menu bars, Reduce Motion, keyboard focus, Return to save,
   accessibility labels, long titles, and popover dismissal/reopening.
8. Make the task file malformed in a test profile; verify a clear error and no
   overwrite. Restore the file and Retry loading. Test a read-only storage failure.
9. Disconnect the network; all features must still work. No permissions prompt
   for screen recording or content monitoring should exist. Verify system input
   idle-time polling works on the target macOS version; investigate if it does not.
10. Verify all four badge corners at 50% opacity, the shared orb and session/total timers.
    Dismiss with ×, restore via Show task badge, change the task title, complete it,
    and start another. Dismissal should survive restart for the same task. Check
    multiple displays, Spaces/fullscreen, and that clicking × does not steal focus.
11. Verify Session Time freezes at automatic idle, resumes on activity, and resets
    with explicit Pause. Total Time survives all boundaries and app relaunch. A task rename preserves total; a new task starts at zero.
12. Confirm logging is initially off. Enable midway through a session, pause/resume,
    rename, complete, and quit. Inspect paired IDs, reasons, duration offsets, and
    completion in the log/report. Disable and confirm no subsequent new records.
    Try an unwritable Logs path; Preferences must show a failure. Force quit and
    verify unmatched spans appear as open/interrupted, not fabricated stops.
13. Run for several hours and inspect Activity Monitor CPU/energy/memory. Check
    task/pause cycles and popover opening do not accumulate timers or observers.

Layered music, synchronization, launch-at-login and accounts belong to later work. This
checklist is not claimed to have passed inside Linux.

## Completion and transition revision

The Task Complete! button should trigger the heart only after local completion
succeeds. Verify green-to-pink flames, dark-red glowing heart, then dim idle circle
in about five seconds. The task-entry panel shows a larger copy for legibility.
Start a new task during the effect: it must cancel cleanly. Try completion while
paused and with Reduce Motion enabled; a manually paused app should stay paused.
Verify yellow-to-green swirl in both menu-bar and badge orbs; no pink/red outline
follows the swirl. Short checkpoint intervals should not
hide either swirl. These visual changes still require a Mac build/manual check.

## Idle, pulse and badge revision

Six new portable tests cover the default pulse phase, five-tap/four-interval
estimation, rolling-window averaging, ignored invalid timestamps, restarting after
a long tap gap, and immutable three-second transition endpoints. Three additional
engine tests cover custom grace, renewed input resetting the grace countdown, and
a one-second grace. Existing engine assertions now cover frozen counters and one-step
retreat. There are 40 native tests written; they have not run in Linux.

On a Mac verify:

- Every red/yellow, yellow/green and idle retreat swirl lasts three seconds. Green
  stays green afterward with no pink/red outline. Standalone checkpoints retain their halo.
- Default Pulse is 70 BPM and both orb copies match. Try a manual BPM, Pause,
  Reduce Motion, and hiding/showing the badge.
- Collect Pulse focuses the local capture control. Tap Space five times, then
  more; only the latest five presses affect the estimate. Holding Space counts
  once. Cancel/close Preferences and verify normal typing is unaffected elsewhere.
- **Save checkpoint interval** has its new label. A profile with no saved badge
  position defaults to bottom-right. Saved positions remain intact. The task title
  is vertically centered next to the dot, including two-line titles.

For this revision, all 24 Swift files passed tree-sitter grammar parsing and the
Xcode project/source/scheme references passed static checks in Linux. Grammar
parsing is not Swift type checking, compilation, or execution of the 40 native
tests. The pulse/idle/badge behavior and energy impact still need Mac verification.

## Local MP3 playback (Mac verification required)

Badge layout check: the default width is 180 pixels (previously 360). Drag the
top handle across the desktop, then resize using the lower-right grip or edges.
Try a long task title at narrow and wide sizes: text wraps, timers remain readable,
and overflow scrolls. Hide/show and rename the task: the moved position and size
must remain. Selecting another corner must reposition it. Check × still dismisses
the badge without completing the task. These window interactions require macOS.

- In Preferences, choose a short MP3. Hear it repeat beyond its end; verify volume
  and Play music controls. Silence encoded at the file boundaries remains audible.
- Change orb states and complete/start tasks: music must continue without restarting.
- Pause/resume FlowDo and sleep/wake the Mac: playback pauses and resumes in place.
- Cancel the file picker: the existing track and settings remain unchanged.
- Import an invalid file named `.mp3`: an error appears and the previous track remains.
- Import a replacement: only the new track plays. Remove MP3 stops playback.
- Move the original file, quit, and relaunch: the imported copy still plays, with
  the saved volume and enabled setting. Disabled music stays disabled on relaunch.
- Try a large file: the menu and engagement timers remain responsive while copying.

The audio player uses Apple's [continuous looping support](https://developer.apple.com/documentation/avfaudio/avaudioplayer/numberofloops).
Linux static checks cannot validate audio decoding, playback, or the native picker.
