"""Regression tests for the standalone lesson content boundary."""

from pathlib import Path
import tempfile
import unittest

from content_loader import ContentValidationError, load_lesson
from content_runtime import build_runtime_content


ADMIN_APP_DIR = Path(__file__).resolve().parents[1]
MANIFEST = ADMIN_APP_DIR / "content" / "deep_data_security" / "lab.yaml"


class ContentLoaderTests(unittest.TestCase):
    def test_deep_sec_manifest_loads_with_complete_shape(self) -> None:
        lesson = load_lesson(MANIFEST)
        self.assertEqual(lesson.id, "deep_data_security")
        self.assertEqual(len(lesson.pages), 8)
        self.assertEqual(len(lesson.steps), 34)
        self.assertEqual(len(lesson.actions), 35)
        self.assertEqual(len(lesson.overview["stages"]), 6)
        self.assertEqual(lesson.overview["start_path"], "/db-setup")
        self.assertEqual(len(lesson.tour), 8)
        self.assertEqual(lesson.tour[0]["title"], "DB Setup")
        self.assertEqual(
            sum(len(action.scripts) for action in lesson.actions.values()),
            33,
        )
        self.assertEqual(
            lesson.actions["customize_manager_grant"].handler,
            "data_grant",
        )
        self.assertFalse(lesson.actions["customize_manager_grant"].confirm_apply)
        self.assertEqual(lesson.pages[-2].id, "exercises")
        self.assertNotIn("vibe-coding", {page.id for page in lesson.pages})
        self.assertEqual(lesson.actions["exercise_reset"].completion, "mark_viewed")

    def test_runtime_content_preserves_configured_pages_and_wizards(self) -> None:
        lesson = load_lesson(MANIFEST)
        actions, steps, pages = build_runtime_content(lesson)
        self.assertEqual(actions["customize_employee_grant"]["type"], "wizard")
        self.assertEqual(actions["extend_manager_context"]["grant_wizard"]["style"], "all_except")
        self.assertEqual(pages[-2]["key"], "exercises")
        self.assertEqual(len(pages[-2]["step_keys"]), 5)
        self.assertFalse(pages[-1]["ordered"])
        self.assertEqual(len(steps), 34)

    def test_unknown_action_reference_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "lab.yaml").write_text(
                """
schema_version: 1
id: example
title: Example
script_root: database
actions:
  one:
    type: mark_viewed
    title: One
    description: One
steps:
  - id: first
    badge: "1"
    label: First
    title: First
    action_ids: [missing]
pages:
  - id: page
    path: /page
    label: Page
    step_ids: [first]
""",
                encoding="utf-8",
            )
            (root / "database").mkdir()
            with self.assertRaisesRegex(ContentValidationError, "unknown action 'missing'"):
                load_lesson(root / "lab.yaml")

    def test_dependency_cycle_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "database").mkdir()
            (root / "database" / "one.sql").write_text("select 1 from dual;\n", encoding="utf-8")
            (root / "lab.yaml").write_text(
                """
schema_version: 1
id: example
title: Example
script_root: database
actions:
  one:
    type: sql
    title: One
    description: One
    scripts: [one.sql]
    requires: [two]
  two:
    type: mark_viewed
    title: Two
    description: Two
    requires: [one]
steps:
  - id: first
    badge: "1"
    label: First
    title: First
    action_ids: [one]
pages:
  - id: page
    path: /page
    label: Page
    step_ids: [first]
""",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ContentValidationError, "action dependency cycle"):
                load_lesson(root / "lab.yaml")


if __name__ == "__main__":
    unittest.main()
