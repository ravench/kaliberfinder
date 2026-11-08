"""Unit tests for tools/crashes.py.

    python3 -m unittest discover -s tools -p 'test_crashes.py'
"""
import os
import unittest

import crashes

RESPONSE = {
    "data": [
        {"id": "abc12345-def", "type": "betaFeedbackCrashSubmissions",
         "attributes": {"createdDate": "2026-11-08T12:30:00Z", "comment": "Tele chosen", "deviceModel": "iPhone18,1",
                        "osVersion": "27.2", "appPlatform": "IOS"},
         "relationships": {"build": {"data": {"id": "b1", "type": "builds"}}}},
        {"id": "ffff", "type": "betaFeedbackCrashSubmissions", "attributes": {"createdDate": "2026-11-07T08:00:00Z"}},
    ],
    "included": [{"id": "b1", "type": "builds", "attributes": {"version": "1113"}}],
}


class LinesTests(unittest.TestCase):
    def test_one_line_per_submission_with_its_build(self):
        self.assertEqual(crashes.lines(RESPONSE), [
            "2026-11-08T12:30:00Z  build 1113  iPhone18,1  IOS 27.2  Tele chosen",
            "2026-11-07T08:00:00Z  build ?  ?   ?",
        ])

    def test_the_email_is_not_asked_for(self):
        self.assertNotIn("email", crashes.FIELDS)


class WorkflowTests(unittest.TestCase):
    def test_the_workflow_keeps_the_logs_in_an_artifact(self):
        with open(os.path.join(crashes.changelog.ROOT, ".github", "workflows", "crashes.yml")) as f:
            workflow = f.read()
        self.assertIn("workflow_dispatch", workflow)
        self.assertIn("tools/crashes.py", workflow)
        self.assertIn("upload-artifact", workflow)
        self.assertIn("retention-days: 1", workflow)


if __name__ == "__main__":
    unittest.main()
