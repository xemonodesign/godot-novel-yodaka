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
    RULES,
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


def test_opening_counseling_branches_into_the_first_session():
    data = compile_scenario()
    assert data["start"] == "counsel0_6"
    paths = walk(data, data["start"], {"counseling"})
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
    # The opening session must be affordable: every tutorial path earns enough
    # EXP for one facing of the first loosened trauma.
    assert min(len(visited) - 1 for visited, _ in paths) >= RULES["first_cost"]


def test_every_round_chapter_and_outing_ends_in_sleep():
    data = compile_scenario()
    assert [r["chapter"] for r in data["rounds"]] == [
        "main1",
        "main2",
        "main3",
        "main4",
    ]
    assert sum(r["outings"] for r in data["rounds"]) == 6
    # Opening session plus three sessions after flagged chapters: four in all.
    assert [r["counseling"] for r in data["rounds"]] == [True, False, True, True]
    assert data["rounds"][-1]["counseling"] is True
    chapter_paths = {}
    for chapter in data["chapters"]:
        paths = walk(data, chapter["start"], {"sleep"})
        chapter_paths[chapter["id"]] = paths
        for visited, _ in paths:
            assert all(
                data["nodes"][n]["kind"] == "main" for n in visited if n != "sleep"
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
        paths = walk(data, event["start"], {"sleep"})
        assert len(paths) == 1
        outing_words[event["id"]] = paths[0][1]
        assert all(
            data["nodes"][n]["kind"] == "outing"
            and data["nodes"][n]["place"] == event["place"]
            for n in paths[0][0]
            if n != "sleep"
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
        reachable |= set(walk(data, event["start"], {"sleep"})[0][0])
    reachable |= {
        n for visited, _ in walk(data, data["start"], {"counseling"}) for n in visited
    }
    assert set(data["nodes"]) == reachable - {"sleep", "counseling"}


def test_words_are_original_dialogue_with_three_levels():
    data = compile_scenario()
    assert data["stats"] == STATS and len(data["initial"]) == 4
    assert data["rules"] == RULES
    for word in data["words"]:
        node = data["nodes"][word["node"]]
        assert word["word"] in node["text"]
        assert word["speaker"] in ["りあ", "あしか", "すみか", "？？？"]
        assert word["word"] in word["memory"]
        assert 1 <= len(word["effects"]) <= 2 and set(word["effects"]) <= set(STATS)
        assert word["value"] > 0
        assert len(word["levels"]) == 3
        costs = [level["cost"] for level in word["levels"]]
        assert costs[0] == 0 and costs == sorted(costs) and costs[1] > 0
        for level in word["levels"]:
            assert level["insight"]
            assert level["passive"] and level["counsel"]
            for passive in level["passive"]:
                assert passive["kind"] in ["stat", "gain", "exp", "release"]
                if passive["kind"] in ["stat", "gain"]:
                    assert passive["stat"] in STATS
            for effect in level["counsel"]:
                assert effect["kind"] in ["cost", "soften", "calm"]
                if effect["kind"] == "cost":
                    assert 0 < effect["value"] < 1
        assert word["model"] in ["flower", "rock"]
        assert len(word["color"]) == 6
    # The weak first word grows into a strong one.
    praise = next(w for w in data["words"] if w["id"] == "praise")
    assert praise["levels"][0]["passive"] == [
        {"kind": "stat", "stat": "勇気", "value": 1}
    ]
    assert praise["levels"][2]["passive"] == [{"kind": "exp", "value": 10}]


def test_traumas_fill_the_slots_and_hide_deeper_ones():
    data = compile_scenario()
    traumas = {t["id"]: t for t in data["traumas"]}
    initial = [t for t in data["traumas"] if not t.get("deep")]
    deep = [t for t in data["traumas"] if t.get("deep")]
    assert len(initial) == RULES["slot_count"] == 8
    assert {t["id"] for t in deep} == {"nowhere", "nameless"}
    assert {t["deeper"] for t in initial if t["deeper"]} == {"nowhere", "nameless"}
    for trauma in data["traumas"]:
        assert trauma["name"] and trauma["story"] and len(trauma["color"]) == 6
        assert trauma["base_cost"] >= 50000
        assert trauma["base_cost"] // RULES["talk_divisor"] >= 250
        assert len(trauma["talk"]) == 5
        assert [line[0] for line in trauma["talk"]] == [
            "みなと",
            "よだか",
            "みなと",
            "よだか",
            "みなと",
        ]
        assert set(trauma["soften"]) == {"first", "mid", "resolved"}
        assert all(len(pair) == 2 for pair in trauma["soften"].values())
        for debuff in trauma["debuffs"]:
            assert debuff["kind"] in ["offset", "cap", "gain", "exp", "recovery"]
            if debuff["kind"] in ["offset", "cap", "gain"]:
                assert debuff["stat"] in STATS
            if debuff["kind"] in ["gain", "exp", "recovery"]:
                assert 0 < debuff["value"] < 1
        if trauma["deeper"]:
            assert traumas[trauma["deeper"]].get("deep") is True
            assert "surface" in traumas[trauma["deeper"]]
            assert "この奥に" in trauma["story"]
    assert {d["kind"] for t in initial for d in t["debuffs"]} == {
        "offset",
        "cap",
        "gain",
        "exp",
        "recovery",
    }
    # The deeper traumas hit harder than the ones hiding them.
    assert (
        traumas["nowhere"]["debuffs"][0]["value"]
        > traumas["blank"]["debuffs"][0]["value"]
    )
    assert (
        traumas["nameless"]["debuffs"][0]["value"]
        < traumas["mirror"]["debuffs"][0]["value"]
    )
    assert RULES["first_cost"] < 50 and RULES["soften_base"] * 4 >= 100


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
