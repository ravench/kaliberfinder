"""python3 -m unittest discover -s tools -p 'test_*.py'"""
import ast, glob, os, unittest

TOOLS = os.path.dirname(os.path.abspath(__file__))


class MainGuardTests(unittest.TestCase):
    """`python3 tools/test_x.py` runs what CI's discover runs: nothing stands below a file's `__main__` guard.
    Three classes of test_generate_data.py did (review 2026-11-13), so running the file skipped them."""

    def test_the_main_guard_is_the_last_statement(self):
        files = sorted(glob.glob(os.path.join(TOOLS, "test_*.py")))
        self.assertGreater(len(files), 10)
        for path in files:
            with open(path, encoding="utf-8") as f:
                body = ast.parse(f.read()).body
            guards = [i for i, node in enumerate(body) if isinstance(node, ast.If) and "__main__" in ast.unparse(node.test)]
            self.assertIn(guards, ([], [len(body) - 1]), os.path.basename(path))


if __name__ == "__main__":
    unittest.main()
