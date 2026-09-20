#!/usr/bin/env python3
"""Stream FlowDo's boundary log as one tab-separated row per task/session span."""
import argparse
import csv
import json
from pathlib import Path
import sys


def intervals(lines, warn=lambda message: None):
    pending = {}
    for number, line in enumerate(lines, 1):
        try:
            event = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            warn(f"Skipped malformed line {number} (possibly an interrupted write).")
            continue
        if not isinstance(event, dict):
            continue
        kind = event.get("event")
        span = event.get("spanID")
        if kind not in {"task_start", "task_stop", "engagement_start", "engagement_stop"}:
            continue
        if not isinstance(span, str):
            warn(f"Skipped boundary without a span ID at line {number}.")
            continue
        if kind.endswith("_start"):
            pending[span] = event
        else:
            start = pending.pop(span, {})
            yield row(start, event)
    for start in pending.values():
        yield row(start, None)


def row(start, stop):
    event = stop or start
    return {
        "task": event.get("taskName", ""),
        "kind": "engagement" if event.get("event", "").startswith("engagement_") else "task",
        "start": start.get("timestamp", "unknown"),
        "stop": stop.get("timestamp", "unknown") if stop else "open / interrupted",
        "active_seconds": stop.get("durationSeconds", "") if stop else "",
        "reason": event.get("reason", ""),
    }


def printable(value):
    return "".join(character if character.isprintable() else " " for character in str(value))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", nargs="?", type=Path,
                        default=Path.home() / "Library/Application Support/FlowDo/Logs/activity.jsonl")
    args = parser.parse_args()
    try:
        with args.file.open(encoding="utf-8", errors="replace") as source:
            writer = csv.writer(sys.stdout, delimiter="\t", lineterminator="\n")
            writer.writerow(["Task", "Kind", "Start (UTC)", "Stop (UTC)", "Active seconds", "Reason"])
            for item in intervals(source, warn=lambda message: print(message, file=sys.stderr)):
                writer.writerow(printable(item[key]) for key in
                                ["task", "kind", "start", "stop", "active_seconds", "reason"])
    except OSError as error:
        parser.exit(1, f"Cannot read the activity log: {error}\n")


if __name__ == "__main__":
    main()
