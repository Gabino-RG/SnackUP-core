"""Meaningful stdlib tests for fail-fast behavior and status provenance."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from engine import (PipelineRunner, StagePlan, empty_state, github_stage_status,
                    local_pipeline, normalize_github_run, package_web)


class PipelineTests(unittest.TestCase):
    def test_real_child_failure_blocks_later_child(self):
        with tempfile.TemporaryDirectory() as folder:
            cwd = Path(folder)
            plans = [
                StagePlan("pass", "Primera", "", [[sys.executable, "-c", "print('started')"]], cwd),
                StagePlan("fail", "Falla", "", [[sys.executable, "-c", "raise SystemExit(7)"]], cwd),
                StagePlan("later", "No ejecutar", "", [[sys.executable, "-c", "from pathlib import Path; Path('marker').write_text('bad')"]], cwd),
            ]
            state = PipelineRunner("local").start(plans, empty_state("local", "Test"), background=False)
            self.assertEqual([s["status"] for s in state["stages"]], ["success", "failure", "blocked"])
            self.assertEqual(state["conclusion"], "failure")
            self.assertFalse((cwd / "marker").exists())
            self.assertIn("Código de salida: 7", state["stages"][1]["logs"])

    def test_skipped_cancelled_neutral_unknown_never_pass(self):
        self.assertEqual(github_stage_status("completed", "skipped"), "skipped")
        self.assertEqual(github_stage_status("completed", "cancelled"), "cancelled")
        self.assertEqual(github_stage_status("completed", "neutral"), "skipped")
        self.assertEqual(github_stage_status("completed", "unrecognized"), "blocked")
        self.assertEqual(github_stage_status("in_progress", None), "running")
        self.assertEqual(github_stage_status("queued", None), "pending")

    def test_normalization_keeps_unknown_project_steps_and_omitted_tests(self):
        run = {"id": 1, "name": "Flutter CI", "status": "completed", "conclusion": "failure"}
        jobs = [{"id": 2, "name": "build", "steps": [
            {"number": 1, "name": "Validación específica propia", "status": "completed", "conclusion": "success"},
            {"number": 2, "name": "Build", "status": "completed", "conclusion": "failure"},
            {"number": 3, "name": "Integration tests", "status": "completed", "conclusion": "skipped"},
            {"number": 4, "name": "Post Checkout code", "status": "completed", "conclusion": "success"},
        ]}]
        state = normalize_github_run(run, jobs, "Gabino-RG/SnackUP-core")
        self.assertEqual(len(state["stages"]), 3)
        self.assertEqual(state["stages"][0]["name"], "Validación específica propia")
        self.assertEqual(state["stages"][2]["status"], "skipped")
        self.assertTrue(any("Fail Fast" in decision["title"] for decision in state["decisions"]))

    def test_missing_integration_suite_is_explicit_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "app").mkdir()
            (root / "app" / "pubspec.yaml").write_text("name: snackup\n", encoding="utf-8")
            plans, state = local_pipeline(folder)
            integration = next(plan for plan in plans if plan.identifier == "integration")
            runner = PipelineRunner("local")
            result = runner.start([integration], state, background=False)
            self.assertEqual(result["conclusion"], "failure")
            self.assertIn("No se ejecutaron pruebas de integración", " ".join(result["stages"][0]["logs"]))

    def test_packaging_has_content_hash_manifest(self):
        import zipfile
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            web = root / "app" / "build" / "web"
            web.mkdir(parents=True)
            (web / "index.html").write_text("SnackUP", encoding="utf-8")
            _, artifact = package_web(root / "app", root / ".snackup-ci", "abc123")
            with zipfile.ZipFile(artifact["path"]) as archive:
                manifest = json.loads(archive.read("ci-manifest.json"))
                self.assertEqual(manifest["files"][0]["path"], "index.html")
                self.assertEqual(manifest["sha"], "abc123")
            self.assertEqual(len(artifact["sha256"]), 64)


if __name__ == "__main__":
    unittest.main()
