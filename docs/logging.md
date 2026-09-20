# Local timing and optional activity logs

## Badge timers

Session Time is credited engagement in the current engagement session, beginning
with yellow after input resumes. Total Time on Task sums credited time across
sessions for the same task UUID. Both use the deterministic engine's monotonic
clock, not elapsed wall time since task creation.

Thinking/reading pauses count throughout the configured idle grace (default 60
seconds, shared by production/debug modes). At grace expiry, both counters freeze
and the orb retreats one step, holding there. Activity resumes the same counters;
the log closes and reopens engagement instances using counter baselines, so those
instances do not double-count previously credited time.

Explicit Pause, sleep/session deactivation, settings resets, or quitting end and
reset the session counter. The task total remains. Renaming preserves total; a new
task starts at zero. A pre-existing task starts accumulating at this update; past
time is not inferred. All indicator whirlpools last three seconds.

The current task's total is stored as one aggregate in UserDefaults independently
of logging, every 15 seconds and at session boundaries/normal quit. There is no
per-second activity history. A crash can lose the latest unsaved aggregate time;
UserDefaults also depends on OS persistence. Restart restores total, not session.

## Enable and inspect logs

Preferences → **Log activity locally**. Default is off. Enabling midway starts a
new observation window, with the existing session/total counters recorded as
baselines. It does not backfill past activity. Disabling closes the observed spans
and drains pending writes, without deleting old records. Turning logging off does
not disable the badge timers.

Preferences → **Open log folder** opens:

`~/Library/Application Support/FlowDo/Logs/`

The file is `activity.jsonl`: UTF-8 JSON Lines, one compact JSON object per boundary
or achievement. Writes are serialized on a utility queue; no writes occur per
input event or timer tick. New log directories/files use permissions 0700/0600.
The logger creates no file while logging is off. The explicit Open log folder
button can create an empty folder.

For an easily scanned report, run from the repository root on your Mac:

```sh
python3 scripts/activity_report.py
```

It produces tab-separated columns: Task, Kind, Start (UTC), Stop (UTC), Active
seconds, Reason. One row represents each task observation span or engagement
instance. It streams the file and pairs boundaries by UUID, retaining only open
spans in memory. To save a spreadsheet-friendly copy:

```sh
python3 scripts/activity_report.py > flowdo-activity.tsv
```

Keep exported task names private if appropriate. Generated activity exports are
ignored by the repository's Git configuration.

## Record meanings

| Event | Meaning |
| --- | --- |
| `task_start` | Task created, restored at launch, or logging enabled for an existing task |
| `task_stop` | Completed, normal app quit, or logging disabled |
| `task_renamed` | Same task ID, new declared name |
| `engagement_start` | New engagement instance, or logging enabled during one |
| `engagement_stop` | Idle, pause, sleep/session switch, settings change, completion, quit, or logging disabled |
| `achievement` | Green reached, recurring checkpoint crossed, or both on the same sample |

Every event carries `taskID`, `taskName`, original `taskStartedAt`, event
`timestamp` (UTC ISO-8601), `reason`, `sessionSeconds`, and `totalSeconds`. Starts
and stops share a `spanID`; stops add `durationSeconds`, the credited engagement
since that observed span began. Task and engagement spans overlap: do not sum
both kinds to get a total. Task stop with reason `completed` records the
accomplishment; other task stops do not mean the intention was completed.

Start/stop timestamps describe observed lifecycle boundaries. An idle stop is
recorded when the idle timeout is detected, whereas credited duration excludes
time beyond the configured grace. Wall-clock elapsed time can therefore exceed active time.
Mid-session opt-in subtracts the recorded baseline from stop duration.

A crash/force quit may leave an unmatched start. The report labels it
`open / interrupted`; it never fabricates a stop time or duration. A partial final
JSON line is skipped with a warning. The next app append separates that damaged
line before writing another valid record. Write failures are shown in Preferences;
the app continues locally, but the log may be incomplete until storage is fixed.

No keystrokes, input event lists, app/window contents, screenshots, or network
uploads are recorded. Names and summary timestamps are stored only after opt-in.
Files are retained until you delete them; turn logging off before deleting them
in Finder. There is no automatic upload, rotation, or history database.

Pulse collection is independent of this journal. Spacebar press timestamps are
kept only in a five-element, in-memory window while the local collection control
is active. They are never written to the activity log. Only the chosen BPM and
pulse-enabled preference persist.
