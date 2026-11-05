"""studio/build-recipe.py: studio.yaml is exactly trader.yaml plus the three edits, and a trader.yaml
whose anchors moved is refused instead of producing a Studio recipe without its permissions.
Run: python3 -I tests/test_build_recipe.py"""
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("build_recipe", ROOT / "studio/build-recipe.py")
br = importlib.util.module_from_spec(spec)
spec.loader.exec_module(br)
TRADER = (ROOT / "agent/recipes/trader.yaml").read_text()
SECTION = (ROOT / "studio/prompt-section.txt").read_text()


class BuildRecipe(unittest.TestCase):
    def test_committed_file_is_current(self):
        self.assertEqual(br.build(TRADER, SECTION), (ROOT / "agent/recipes/studio.yaml").read_text())

    def test_protocol_is_the_traders(self):
        out = br.build(TRADER, SECTION)
        # Everything between the first prompt line and the home-directory sentence, and the
        # protocol after the Studio section, is byte-identical to the trader's.
        # The two wait edits (below) are the only other differences.
        trader = TRADER.replace(br.KEEP_OLD, br.KEEP_NEW).replace(br.WAIT_OLD, br.WAIT_NEW)
        pre_t, rest_t = trader.split(br.FORBID)
        pre_s, rest_s = out.split(br.ALLOW)
        self.assertEqual(pre_t[pre_t.index("prompt: |"):], pre_s[pre_s.index("prompt: |"):])
        self.assertEqual(rest_t.split(br.START)[0], rest_s.split(SECTION)[0])
        self.assertEqual(rest_t.split(br.START)[1], rest_s.split(br.START)[1])

    def test_studio_does_not_start_the_mailbox_wait(self):
        # Steps 1-3 need no mailbox, and a turn stuck in `mbx wait` holds the person's words back
        # (Ctrl-C works since goose-acp-cancel-abandoned-prompt.patch, but nothing should force it).
        out = br.build(TRADER, SECTION)
        self.assertIn("Do NOT run `mbx wait`", out)
        self.assertNotIn("Then wait for buyers with `mbx wait`", out)
        self.assertNotIn("right after you tell your user the address, go straight", out)
        # The trader (devcon8 trade) still waits at start-up.
        self.assertIn("Then wait for buyers with `mbx wait`", TRADER)
        self.assertIn("right after you tell your user the address, go straight", TRADER)
        # A purchase (buy_from) still starts at once.
        self.assertIn("Then start\n  the purchase from {{ buy_from }}.", out)

    def test_permissions_are_widened_only_as_stated(self):
        out = br.build(TRADER, SECTION)
        self.assertIn("Do not curl anything, install anything or read other files", out)
        self.assertIn("/opt/devcon8/agent/skills/terms-pack-author/SKILL.md", out)
        self.assertIn("under ~/studio", out)
        self.assertNotIn("\ninstructions:", out)  # ACP providers drop it (devcon-workshop#27)
        for bad in ("curl http", "pip install", "--break-system-packages"):
            self.assertNotIn(bad, SECTION)

    def test_missing_anchor_is_refused(self):
        for anchor in (br.TITLE, br.FORBID, br.START, br.DESC_START, br.KEEP_OLD, br.WAIT_OLD):
            with self.assertRaises(SystemExit):
                br.build(TRADER.replace(anchor, "", 1), SECTION)
        with self.assertRaises(SystemExit):
            br.build(TRADER + br.FORBID, SECTION)  # ambiguous anchor


if __name__ == "__main__":
    unittest.main()
