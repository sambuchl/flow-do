# Architecture and ownership

## Local client

The native app owns the Current Task, local persistence, activity sensing,
engagement inference and orb. SwiftUI views observe a main-actor FlowDoModel;
AppKit owns the status item and transient popover. LSUIElement keeps the app out
of the Dock. No networking code runs and no credentials are needed.

TaskStore is the async seam; LocalTaskStore is an actor that atomically replaces
one JSON task. CurrentTask has UUID, title, startedAt, completedAt and updatedAt.
Changing a title preserves identity; completing persists a timestamp and load
returns nil. Failure to load disables task mutation until storage is recovered.
Writes report failure without claiming the operation succeeded.

The Foundation-only engine accepts an injectable monotonic clock. The app polls
once a second, only while a task exists and FlowDo is unpaused. It asks
[CGEventSource](https://developer.apple.com/documentation/coregraphics/cgeventsource)
for elapsed time since input in the current login session. It never installs a
key event tap, examines key codes, or receives typed text. This measures activity,
not relevance to the task; synthetic input can count as activity too. Actual
sensor behavior must be checked on the target Mac.

No characters, clipboard, URLs, screenshots, document contents, filenames,
application contents or microphone audio are collected. Input age is ephemeral;
no raw input history or network telemetry exists. Task persistence and one
current-task time aggregate are always local. Optional logging, off by default,
adds task names and summarized lifecycle/engagement timestamps; see
[logging.md](logging.md).

## Engagement rules

Production reaches green after 240 credited seconds; debug reaches green after
20. Both use the user's idle grace, default 60 seconds (Preferences accepts 1–3600).
States remain idle (red), returning (yellow), and engaged (green). These are product
heuristics, not scientific measurements.

- Input after explicit session start enters returning.
- Time accrues throughout the grace window after input.
- At grace expiry, counters freeze and the state retreats exactly once: green to
  yellow, or yellow to red. Continued idle holds the reduced state.
- Activity resumes the counters and eligible state. Automatic idle ends one
  logged engagement instance; the next starts with a baseline at the frozen count.
- Explicit Pause/resume, completion, new task, settings changes, sleep/session
  deactivation, and quit reset the session counter while preserving task total.
- Sampling gaps earn no unobserved duration. Inference and rendering use monotonic
  clocks; wall-clock changes cannot advance the engine or change pulse phase.

OrbTransition captures immutable source, destination and monotonic start time.
Every whirlpool lasts exactly three seconds. Rendering after its end uses its
explicit destination, never an old source inferred from unrelated timestamps.
Implicit state-color crossfades were removed. This prevents the previous potential
red-source fallback after a yellow-to-green swirl. Pink achievements use an outer
halo so the green center is not replaced by a reddish dot.

Pink is a transient achievement overlay, not a fourth engagement state. The engine
emits a one-tick signal when duration crosses green or a multiple of the configured
checkpoint interval. The user enters a whole number and selects seconds/minutes;
default is every 20 minutes, with blank/0 disabling checkpoints. Crossings on one
sample are coalesced into one achievement. Saving settings ends the current
session but preserves total task time. Explicit session resets allow checkpoints to repeat; automatic idle preserves
checkpoint progress. Regaining green can still earn the green achievement.
Both orb views use the same monotonic model timestamps so showing the badge does not replay
old effects. Achievement pink is deferred until a color whirlpool finishes. Very short intervals shorten the pink glow to leave time between it.

The engine exposes a session UUID and credited duration for each tick. FlowDoModel
sums these credits for Total Time on Task and uses current session duration for
Session Time. TaskTimeStore keeps one task UUID/total snapshot in UserDefaults.
Changed totals are saved at 15-second intervals and lifecycle boundaries. No
per-tick file log or accumulated list of sessions is needed for these timers.

A nonactivating NSPanel displays the badge at 50% opacity in the selected corner
of the primary screen's visible area (bottom-right by default, unless a position was
already saved). It contains the same OrbView beside the task
name and the two timers below. Dismissal is remembered per task UUID. Preferences
stores all four position choices and provides show/hide; the task menu also offers
show/hide directly between title and state. Screen changes reposition the panel.

ActivityJournal is a boundary-only coordinator behind ActivityLogSink. The optional
LocalActivityLog appends JSON Lines on a dedicated serial utility queue. Separate
span UUIDs pair task and engagement starts/stops. Stop duration subtracts the opt-in
baseline, so enabling midway does not fabricate earlier observed activity. Logging
errors are surfaced without interrupting task operation. Normal quit waits for any
in-flight task save, ends spans, saves totals, and drains log writes. Force quit can
leave open spans, explicitly labeled by the streaming report. No upload occurs.

Engagement state is constant-sized and the polling timer has tolerance for power efficiency.
No long-duration CPU/energy claims have been verified yet.

## Flask service

The application factory constructs independent apps from configuration objects.
SQLAlchemy and Migrate are module-level extension objects initialized per app.
Blueprints: main (health), auth (future browser sessions), api (future token API),
errors (central JSON HTTP errors). HTTP errors preserve protocol headers; 500s
rollback the session and return no exception details.

No User, login extension, authentication route, or server CurrentTask is needed
yet. Those will be introduced together in the accounts milestone. Future browser
auth uses session/CSRF protections; native clients use revocable tokens and
Keychain storage. Authentication concerns must remain separated.

SQLite works without external services; psycopg enables PostgreSQL configuration.
Schema changes use Alembic revisions, never startup create_all or database deletion.
The initial migration environment has no application schema to migrate.

## Microblog reference audit

Cloned from https://github.com/miguelgrinberg/microblog on 2026-09-19 at
`a975ef64864354867c88e0ed3a17ba7d17dca752` into `references/microblog/` after
adding its ignore rule. Inspected app/__init__.py, config.py, app/models.py,
auth and API Blueprint organization, API auth/tokens, errors/handlers.py,
tests.py and migrations/env.py before scaffolding the server. Also reviewed
browser auth routes, API ownership checks and a token migration.

Adopted the separation of factory/extensions, configuration, models, Blueprints,
migrations and test app configuration. No social features or infrastructure were
copied. The reference remains unmodified, ignored and disposable.

## Future synchronization

Server ownership: users, auth, canonical cross-device intention, web experience.
Client ownership: local task availability, sensing, engagement, orb, future audio.
SyncedTaskStore can later wrap LocalTaskStore and an API client. It must never
block local actions on network availability.

Future server tasks should enforce at most one incomplete task per user using a
database constraint and transaction, including concurrent requests. Model task
UUIDs and UTC updated_at. A simple last-write-wins policy can compare updated_at
and use a fixed lexicographic mutation UUID as a tie-breaker. Completion/deletion
needs a versioned tombstone to prevent old offline state resurrecting a task.
Clock skew is an explicit limitation of timestamp LWW; define accepted clock and
server timestamp behavior before implementation. None of this sync machinery is
implemented in M1. Raw activity must never be uploaded.

## Completion presentation

A successful Task Complete! action clears the task and sets a transient completion
timestamp after the local store succeeds. OrbView renders authored SwiftUI heart
and flame shapes, evolving from green to pink to a dark-red ember, then dissolving
to the dim idle circle. A larger copy appears briefly in the empty-task panel.
All render timelines are removed after their effect duration. New-task creation
and explicit resets clear the effect; Reduce Motion uses a static ember heart.
This presentation does not set the user's manual pause preference and writes no
extra engagement or activity-log event beyond the existing completed task stop.

## Pulse

PulseRhythm computes a smooth sinusoidal blend from state color to white and back,
defaulting to 70 BPM (supported setting range 30–180). Orb copies share one monotonic
epoch. One 30fps-capped TimelineView per visible orb handles pulse and transient
effects. The schedule pauses when nothing needs animation; hidden badge animation
is explicitly disabled. Pause, empty-task state and Reduce Motion disable pulsing.

Collect Pulse uses a first-responder NSView inside Preferences, not a global key
monitor. It recognizes Space only while that control is focused, excludes autorepeat,
and discards the sample window on leaving collection. PulseTapSampler retains five
press timestamps, computing BPM as 60 divided by the mean of four intervals. New
presses slide the window; a gap above five seconds restarts collection. Saving the
chosen BPM changes only the pulse preference, not engagement state or task timers.
