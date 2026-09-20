# FlowDo

One intention at a time. A local-first macOS menu-bar app that gently rewards
sustained engagement. The original Milestone 0–1 native build passed all 16 tests
on the user’s Mac. The idle/pulse revision requires a fresh Mac build. Music is reserved for Milestone 2.

## Repository

- `macos/`: native SwiftUI/AppKit app, deterministic engagement core, local task storage, XCTest suite.
- `server/`: independent Flask application factory, domain Blueprints, SQLAlchemy, Flask-Migrate, health endpoint and tests.
- `docs/`: ownership, privacy, engagement behavior, future API contract, and verification checklist.
- `references/microblog/`: ignored, read-only architectural reference, never part of FlowDo changes.

The Mac app has no server or account dependency. It makes no network requests.
Accounts, sync, music, and task backlogs are not implemented. Local activity
logging is optional and off by default.

## Build and run on macOS

Requires macOS 13+ and Xcode 15+ with its command-line tools selected. Run these
commands in the host-side `FlowDo` repository directory (the directory mounted as
`/workspace/FlowDo` in this container):

```sh
## BUILD & TEST FIRST
open macos/FlowDo.xcodeproj
xcodebuild -project macos/FlowDo.xcodeproj -scheme FlowDo \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath macos/DerivedData CODE_SIGNING_ALLOWED=NO build test

## RUN
open macos/DerivedData/Build/Products/Debug/FlowDo.app
```

The shared scheme builds the application and runs standalone core/persistence
XCTest tests. In Xcode, select the **FlowDo** scheme and **My Mac**, then Run.
For normal signed development/distribution, select your team in Signing &
Capabilities. The unsigned command above is intended for a local build only.

To run just the portable core tests with Swift Package Manager:

```sh
cd macos
swift test
```

FlowDo appears only in the menu bar. Click its orb to enter a task. **Change**
edits the current intention without changing its ID or start time. **Task Complete!** marks
it complete and returns to the empty entry view. **Pause FlowDo** suspends sensing;
resume starts gently. Preferences includes fast thresholds for development.
The app starts at idle after restart, preserving the task.

The orb progresses **red → yellow → green**. Reengagement begins with a three-second
red/yellow whirlpool; reaching green uses the same yellow/green swirl. Reduce
Motion disables the swirl. A brief pink halo follows the green transition and marks
reaching green and recurring engagement checkpoints. Preferences provides a number
field with **Seconds / Minutes** radio buttons (default every 20 minutes). Blank
or 0 disables checkpoints. Saving starts a new session, preserving total time.

The **Show/Hide task badge** button sits below the current task title and above
its state. The 50%-opacity badge includes a copy of the status orb, task name, and
**Session Time / Total Time on Task**, formatted as HH:MM:SS. Preferences offers
Top-left, Top-right, Bottom-left, and Bottom-right positions on the primary display
(default Bottom-right; existing saved positions are preserved),
plus a show/hide toggle. Dismiss with ×; dismissal persists for that task across
restart. A new task shows a fresh badge; completion hides it.

Session time counts engagement, including the configurable **Idle grace** (60
seconds by default). At grace expiry both timers freeze and the orb steps back
once: green → yellow or yellow → red, using a three-second whirlpool. It holds
there during continued idle. Activity resumes the frozen counters and the eligible
color. Explicit Pause, settings resets, sleep, and normal quit end the session;
restart preserves total, not session. Total time is saved periodically and at
boundaries.

**Pulse** smoothly lifts the current indicator color to white at 70 BPM by default.
Preferences accepts 30–180 BPM, or **Collect Pulse**: “Tap the spacebar in time with
your pulse at least 5 times”. The estimate averages the four intervals between the
last five presses; continue tapping to refine it and choose **Use collected BPM**.
Holding Space does not add repeat taps. Tap timestamps stay in the collection
control only; no pulse samples are saved or logged. Both orb copies share a pulse
clock. Pulse stops with Pause, an empty task, hidden badge, or Reduce Motion.

Local task file: `~/Library/Application Support/FlowDo/current-task.json`.
The last completed task occupies that single slot until replaced. A malformed
file is preserved and reported rather than silently overwritten. UserDefaults
stores settings, badge position/dismissal, and one current-task time aggregate.

**Log activity locally** in Preferences is off by default. When enabled, task and
engagement start/stop boundaries, credited durations, renames, and achievements
are appended to `~/Library/Application Support/FlowDo/Logs/activity.jsonl`.
**Open log folder** reveals it. No raw input is logged. Turning logging off stops
new records after closing the current spans; it retains existing files.

See [timing and logging details](docs/logging.md). For a readable table of paired
start/stop values on your Mac:

```sh
python3 scripts/activity_report.py
```

No music/volume or launch-at-login controls are exposed in M1.

Completing a successfully saved task shows a restrained heart-and-flame flourish
in the menu bar and task-entry panel: green → pink → dark ember red, then a dim
idle circle after about five seconds. The circle stays dim until the next task.
Entering a new task clears the flourish immediately. Reduce Motion shows a static
ember heart instead. Completion does not change an explicit Pause setting.

## Server in Docker

No PostgreSQL or Redis service is required. With Docker Compose available:

```sh
docker compose build server
docker compose run --rm server python -m unittest discover -s tests -v
docker compose run --rm server flask --app flowdo db upgrade
docker compose up server
```

In another terminal:

```sh
curl http://localhost:5000/health
```

Expected: `{"service":"flowdo","status":"ok"}`.

For Python development (also works inside a Linux container):

```sh
python3 -m venv .venv
.venv/bin/pip install -r server/requirements.txt
cd server
../.venv/bin/python -m unittest discover -s tests -v
../.venv/bin/flask --app flowdo db upgrade
../.venv/bin/flask --app flowdo run --host 0.0.0.0
```

Copy `.env.example` to `.env` if configuration is needed. No secret is necessary
for this health-only scaffold; set a strong SECRET_KEY before implementing
browser sessions. DATABASE_URL defaults to SQLite. PostgreSQL URLs are normalized
to SQLAlchemy's psycopg driver; PostgreSQL runtime behavior is not yet tested.

The migration directory is already initialized; do not run `flask db init` again.
When the accounts milestone adds models, run `flask --app flowdo db migrate -m
"describe change"`, review the revision, then `flask --app flowdo db upgrade`.
There are intentionally no application tables or schema revisions yet.

## Verification status

Executed in the supplied Linux Docker container:

- Six server unittests passed using `create_app(TestConfig)` and in-memory SQLite.
- `flask --app flowdo db upgrade` and `db check` passed.
- `pip check` passed.
- Xcode project syntax, source/object references, and shared-scheme XML passed static validation (not compilation).
- Microblog clone exists, is ignored, has no local modifications, and is absent from FlowDo changes.

The original 16 native tests passed on the user’s Mac on 2026-09-19. The suite now
contains 40 native tests, including recurring intervals, time aggregation, logging
consent, paired spans, file failure/recovery, exact idle grace/frozen timers,
pulse averaging/phase, and fixed three-second swirl endpoints. Four Python activity-report
tests passed in Linux. This revision has not
been compiled or run here: neither
Swift nor Xcode is installed. Docker Compose is not available in this container,
so the supplied Compose image itself has not been built. See
[the Mac acceptance checklist](docs/verification.md) before considering M1 verified.

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
