"""Verify the real workbook conversion and every authored branch."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src/tools"))
from import_scenario import ROOT, compile_scenario, read_workbook


def test_all_routes_reach_counseling_with_all_words():
    data = compile_scenario()
    paths = []

    def walk(node_id, visited, words):
        if node_id == "counseling":
            paths.append((visited, words))
            return
        assert node_id not in visited, f"Loop at {node_id}"
        node = data["nodes"][node_id]
        assert len(node["text"]) > 0
        words = words | ({node["word"]} if "word" in node else set())
        for target in node.get("choices", [{"next": node["next"]}]):
            walk(target["next"], visited + [node_id], words)

    walk(data["start"], [], set())
    assert len(paths) == 12
    for visited, words in paths:
        assert len(words) == 8
        assert ("main2_33" in visited) != ("main2_40" in visited)
        assert ("main3_26" in visited) != ("main3_29" in visited)
        assert ("main4_33" in visited) != ("main4_38" in visited)
    assert set(data["nodes"]) == set().union(*(set(p[0]) for p in paths))


def test_markers_are_original_dialogue_from_other_people():
    data = compile_scenario()
    for word in data["words"]:
        node = data["nodes"][word["node"]]
        assert word["word"] in node["text"]
        assert word["speaker"] in ["りあ", "あしか", "すみか"]
        assert word["word"] in word["memory"]
        assert len(word["interpretations"]) == 3
        for interpretation in word["interpretations"]:
            assert len(interpretation["effects"]) <= 2
            assert set(interpretation["effects"]) <= {
                "ストレス",
                "勇気",
                "知性",
                "忍耐",
                "キラキラ",
                "自認",
            }
            assert interpretation["reply"]
        assert word["model"] in ["flower", "rock"]
        assert len(word["color"]) == 6
    main_path = next(ROOT.glob("*メイン*.xlsx"))
    sheets = read_workbook(main_path)
    row = next(r for r in sheets[0]["rows"] if r["row"] == 5)
    assert row["C"] == "バスケを辞めてからずっと、時間を持て余している"
    assert len(sheets) == 4
