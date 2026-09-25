"""Verify the compiled loop: counseling -> outings -> chapters -> counseling."""

import json
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src/tools"))
from import_scenario import (
    CACHE,
    COURAGE_GATE,
    ROOT,
    STATS,
    compile_scenario,
    load_sources,
    read_workbook,
)


def walk(data, start, stop):
    """Every path from start to a node in stop: (visited ids, words seen)."""
    paths = []

    def step(node_id, visited, words):
        if node_id in stop:
            paths.append((visited + [node_id], words))
            return
        assert node_id not in visited, f"Loop at {node_id}"
        node = data["nodes"][node_id]
        assert len(node["text"]) > 0
        words = words | ({node["word"]} if "word" in node else set())
        for target in node.get("choices", [{"next": node["next"]}]):
            step(target["next"], visited + [node_id], words)

    step(start, [], set())
    return paths


def test_opening_counseling_branches_and_reaches_the_map():
    data = compile_scenario()
    assert data["start"] == "counsel0_6"
    paths = walk(data, data["start"], {"map"})
    assert len(paths) == 27  # three tutorial questions, three answers each
    for visited, words in paths:
        assert words == set()
        assert visited[-2] == "counsel1_51"
        assert "counsel1_45" in visited
    assert data["nodes"]["counsel1_45"]["karte"] is True
    for row in [10, 20, 35]:
        choices = data["nodes"][f"counsel1_{row}"]["choices"]
        assert len(choices) == 3
        assert {c["next"] for c in choices} == {
            f"counsel1_{row + 2}",
            f"counsel1_{row + 4}",
            f"counsel1_{row + 6}",
        }
        for choice in choices:
            assert 1 <= len(choice["effects"]) <= 2
            assert set(choice["effects"]) <= set(STATS)
    assert data["nodes"]["counsel1_14"]["next"] == "counsel1_18"
    assert data["nodes"]["counsel1_41"]["next"] == "counsel1_43"
    assert all(
        node["partner"] == "みなと" and node["place"] == "診察室"
        for key, node in data["nodes"].items()
        if key.startswith("counsel")
    )


def test_every_round_chapter_and_outing_ends_in_the_night():
    data = compile_scenario()
    assert [r["chapter"] for r in data["rounds"]] == [
        "main1",
        "main2",
        "main3",
        "main4",
    ]
    assert sum(r["outings"] for r in data["rounds"]) == 6
    chapter_paths = {}
    for chapter in data["chapters"]:
        paths = walk(data, chapter["start"], {"night"})
        chapter_paths[chapter["id"]] = paths
        for visited, _ in paths:
            assert all(
                data["nodes"][n]["kind"] == "main" for n in visited if n != "night"
            )
    assert len(chapter_paths["main1"]) == 1
    assert len(chapter_paths["main2"]) == 3
    assert len(chapter_paths["main3"]) == 2
    assert len(chapter_paths["main4"]) == 2
    for visited, words in chapter_paths["main2"]:
        assert ("main2_33" in visited) != ("main2_40" in visited)
        assert words == {"new_self", "not_wasted"}
    for visited, _ in chapter_paths["main3"]:
        assert ("main3_26" in visited) != ("main3_29" in visited)
    for visited, words in chapter_paths["main4"]:
        assert ("main4_33" in visited) != ("main4_38" in visited)
        assert words == {"not_fault", "sparkle", "friends"}
    gate = data["nodes"]["main4_31"]["choices"][1]["requires"]
    assert gate == {"stat": "勇気", "min": COURAGE_GATE}
    outing_words = {}
    for event in data["map_events"]:
        paths = walk(data, event["start"], {"night"})
        assert len(paths) == 1
        outing_words[event["id"]] = paths[0][1]
        assert all(
            data["nodes"][n]["kind"] == "outing"
            and data["nodes"][n]["place"] == event["place"]
            for n in paths[0][0]
            if n != "night"
        )
    assert outing_words == {
        "sushi": {"praise"},
        "park": set(),
        "cafe": {"miracle"},
        "sumika": {"happiness"},
        "cry": {"cute"},
        "rest": set(),
    }
    rest = next(e for e in data["map_events"] if e["id"] == "rest")
    assert rest["repeatable"] and data["nodes"]["rest_2"]["effects"] == {
        "ストレス": -15
    }
    assert {e["unlock"] for e in data["map_events"]} == {1, 2}
    reachable = set()
    for paths in chapter_paths.values():
        for visited, _ in paths:
            reachable |= set(visited)
    for event in data["map_events"]:
        reachable |= set(walk(data, event["start"], {"night"})[0][0])
    reachable |= {
        n for visited, _ in walk(data, data["start"], {"map"}) for n in visited
    }
    assert set(data["nodes"]) == reachable - {"night", "map"}


def test_markers_are_original_dialogue_with_bounded_effects():
    data = compile_scenario()
    assert data["stats"] == STATS and len(data["initial"]) == 4
    for word in data["words"]:
        node = data["nodes"][word["node"]]
        assert word["word"] in node["text"]
        assert word["speaker"] in ["りあ", "あしか", "すみか", "？？？"]
        assert word["word"] in word["memory"]
        assert 1 <= len(word["effects"]) <= 2 and set(word["effects"]) <= set(STATS)
        assert len(word["interpretations"]) == 3
        for interpretation in word["interpretations"]:
            assert 1 <= len(interpretation["effects"]) <= 2
            assert set(interpretation["effects"]) <= set(STATS)
            assert interpretation["reply"]
        assert word["model"] in ["flower", "rock"]
        assert len(word["color"]) == 6


def test_sources_come_from_workbooks_or_the_committed_cache():
    sources = load_sources()
    assert ("main", "メイン01v3") in sources and (
        "counseling",
        "カウンセリング1",
    ) in sources
    row = next(r for r in sources[("main", "メイン01v3")]["rows"] if r["row"] == 5)
    assert row["C"] == "バスケを辞めてからずっと、時間を持て余している"
    cache = {
        unicodedata.normalize("NFC", name): sheets
        for name, sheets in json.loads(CACHE.read_text()).items()
    }
    assert set(cache) == {
        "カウンセリング.xlsx",
        "よだかプロト版メイン v3_26.07.17.xlsx",
        "よだかプロト_断片集1.xlsx",
        "よだかプロト_断片集2.xlsx",
    }
    assert set(cache["よだかプロト_断片集1.xlsx"]) == {"断片１", "断片４"}
    for path in ROOT.glob("*カウンセリング*.xlsx"):
        sheets = read_workbook(path)
        assert [s["sheet"] for s in sheets] == ["カウンセリング0", "カウンセリング1"]
        assert next(r for r in sheets[0]["rows"] if r["row"] == 7)["B"] == "みなと"
