"""Pure generator regressions: python -m unittest discover -s tests -p test_generate_dungeon_quests.py"""

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("dungeon_generator", Path(__file__).resolve().parents[1] / "tools/generate_dungeon_quests.py")
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


def fixture():
    return {"quests": {}, "npcs": {}, "objects": {}, "items": {}, "areas": {"12": 1429},
            "dungeonAreas": {}, "questDE": {}, "npcDE": {}, "objectDE": {}, "itemDE": {}, "catalog": {}}


class DungeonGeneratorTests(unittest.TestCase):
    def test_branch_graph_keeps_both_alternatives_and_shared_ancestors(self):
        quests = {"1": {"13": {"1": 2, "2": 3}}, "2": {"12": {"1": 4}},
                  "3": {"12": {"1": 4}}, "4": {}}
        self.assertEqual(generator.chain_ids(1, quests), ([4, 2, 3, 1], True, []))

    def test_missing_optional_branch_is_explicit(self):
        quests = {"1": {"13": {"1": 2, "2": 3}}, "2": {}}
        self.assertEqual(generator.chain_ids(1, quests), ([2, 1], False, [3]))

    def test_cycle_does_not_recurse_forever_or_claim_complete(self):
        self.assertEqual(generator.chain_ids(1, {"1": {"13": {"1": 2}}, "2": {"13": {"1": 1}}}), ([2, 1], False, []))

    def test_active_quest_requirements_are_included(self):
        self.assertEqual(generator.chain_ids(1, {"1": {"25": 2, "34": 3}, "2": {}, "3": {}}), ([2, 3, 1], True, []))

    def test_distinct_npcs_in_same_area_keep_their_own_names(self):
        source = fixture()
        source["npcs"] = {"1": {"1": "First", "7": {"12": {"1": {"1": 5, "2": 5}}}},
                          "2": {"1": "Second", "7": {"12": {"1": {"1": 6, "2": 6}}}}}
        source["npcDE"] = {"1": {"1": "Erster"}, "2": "Zweiter"}
        points = generator.Generator(source).points([("npcs", 1), ("npcs", 2)])
        self.assertEqual(points, [[1429, 5, 5, "First", "Erster"], [1429, 6, 6, "Second", "Zweiter"]])

    def test_points_are_bounded_per_target_and_reject_instance_sentinels(self):
        source = fixture()
        source["npcs"] = {str(npc): {"1": str(npc), "7": {"12": {str(i): {"1": x, "2": 5} for i, x in enumerate([-1, 1, 11, 21, 31, 41, 51, 61, 71], 1)}}}
                          for npc in (1, 2)}
        points = generator.Generator(source).points([("npcs", 1), ("npcs", 2)])
        self.assertEqual(len(points), 12)
        self.assertTrue(all(0 <= point[1] <= 100 for point in points))

    def test_delivery_marker_requires_no_kill_or_collection_objective(self):
        source = fixture()
        source["quests"] = {"1": {"1": "Delivery", "3": {"1": {"1": 1}}},
                            "2": {"1": "Dungeon kill", "3": {"1": {"1": 1}}, "10": {"1": {"1": {"1": 2}}}, "17": 2437}}
        source["npcs"] = {"1": {"1": "Receiver"}, "2": {"1": "Boss"}}
        model = generator.Generator(source)
        self.assertTrue(model.node(1)["delivery"])
        self.assertFalse(model.node(2)["delivery"])
        self.assertTrue(model.node(2)["inside"])

    def test_forever_race_bits_are_not_truncated_to_32_bits(self):
        self.assertEqual(generator.restrictions({"6": 4294967296, "7": 64}), ([95], [7], "A"))
        self.assertEqual(generator.restrictions({"6": 8589934592}), ([96], [], "H"))

    def test_item_started_quest_points_to_item_source_without_inventing_a_giver(self):
        source = fixture()
        source["quests"] = {"1": {"1": "Letter quest", "2": {"3": {"1": 91}}}}
        source["items"] = {"91": {"1": "Letter", "2": {"1": 1}}}
        source["itemDE"] = {"91": "Brief"}
        source["npcs"] = {"1": {"1": "Source mob", "7": {"12": {"1": {"1": 5, "2": 5}}}}}
        node = generator.Generator(source).node(1)
        self.assertEqual(node["startItem"], ["Letter", "Brief"])
        self.assertEqual(node["start"][7], "item")
        self.assertEqual(node["startSpots"][0], [1429, 5, 5, "Source mob", "Source mob"])


if __name__ == "__main__":
    unittest.main()
