import json
import unittest
from activity_report import intervals, printable


class ActivityReportTests(unittest.TestCase):
    def test_interleaved_spans_pair_by_id(self):
        records = [
            dict(event="task_start", spanID="t", taskName="Before", timestamp="T0"),
            dict(event="engagement_start", spanID="s", taskName="Before", timestamp="T1"),
            dict(event="task_renamed", taskName="After"),
            dict(event="engagement_stop", spanID="s", taskName="After", timestamp="T2", durationSeconds=15, reason="idle"),
            dict(event="task_stop", spanID="t", taskName="After", timestamp="T3", durationSeconds=15, reason="completed"),
        ]
        rows = list(intervals(map(json.dumps, records)))
        self.assertEqual([r["start"] for r in rows], ["T1", "T0"])
        self.assertEqual([r["stop"] for r in rows], ["T2", "T3"])
        self.assertEqual(rows[0]["active_seconds"], 15)
        self.assertEqual(rows[1]["task"], "After")

    def test_interrupted_span_is_not_given_a_fake_stop(self):
        rows = list(intervals([json.dumps(dict(event="engagement_start", spanID="s", timestamp="T0"))]))
        self.assertEqual(rows[0]["stop"], "open / interrupted")
        self.assertEqual(rows[0]["active_seconds"], "")

    def test_missing_start_and_malformed_tail_are_tolerated(self):
        warnings = []
        rows = list(intervals([json.dumps(dict(event="task_stop", spanID="t", timestamp="T1")), '{"partial":'], warnings.append))
        self.assertEqual(rows[0]["start"], "unknown")
        self.assertEqual(len(warnings), 1)

    def test_control_characters_cannot_change_terminal_output(self):
        self.assertEqual(printable("Title\nnext\tpart\x1b"), "Title next part ")


if __name__ == "__main__":
    unittest.main()
