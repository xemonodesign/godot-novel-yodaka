"""Compile the original XLSX text and explicit branch/word annotations for Godot.

The game loop is: opening counseling (tutorial) -> rounds of MAP outings that
collect words -> a main chapter per round -> a closing counseling.
Workbooks stay out of the repository; the rows of the sheets the game uses are
cached in ``src/data/source_rows.json`` so the compiler and tests run without them.
"""

import json
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "src/data/source_rows.json"
NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
STATS = ["ストレス", "勇気", "自認", "キラキラ"]
INITIAL = [60, 35, 35, 35]
COURAGE_GATE = 60
BOOKS = {
    "main": "メイン",
    "fragments1": "断片集1",
    "fragments2": "断片集2",
    "counseling": "カウンセリング",
}
# Rounds: how many outings before each main chapter is unlocked.
ROUNDS = [
    {"outings": 3, "chapter": "main1"},
    {"outings": 3, "chapter": "main2"},
    {"outings": 3, "chapter": "main3"},
    {"outings": 3, "chapter": "main4"},
]
# Every fragment is a MAP destination:
# (id, book, sheet, title or None for the sheet's own, label, place, partner,
#  week unlocked, effect of the closing line for fragments without a word).
EVENTS = [
    (
        "cafe",
        "fragments1",
        "断片１",
        "奇跡を待つ人",
        "喫茶店に寄る",
        "喫茶店",
        "",
        1,
        {},
    ),
    (
        "hands",
        "fragments1",
        "断片２",
        "手を繋ぐ相手",
        "夕方の街を歩く",
        "街（夕方）",
        "",
        1,
        {"自認": 3, "ストレス": 2},
    ),
    (
        "cover",
        "fragments1",
        "断片３",
        "雨除けカバー",
        "住宅街を歩く",
        "路上",
        "",
        1,
        {"勇気": 4, "自認": 2},
    ),
    (
        "park",
        "fragments1",
        "断片４",
        "鴨のいる公園",
        "公園で過ごす",
        "自然公園",
        "",
        1,
        {"ストレス": -5},
    ),
    (
        "parent",
        "fragments1",
        "断片５",
        "友達親子",
        "喫茶店で親子を見る",
        "喫茶店",
        "",
        2,
        {"ストレス": 3, "自認": 2},
    ),
    (
        "chime",
        "fragments1",
        "断片６",
        "季節はずれの風鈴",
        "風鈴の音を追う",
        "路上",
        "",
        2,
        {"ストレス": -4},
    ),
    (
        "unicorn",
        "fragments1",
        "断片７",
        "傘のユニコーン",
        "雨の帰り道",
        "路上",
        "",
        2,
        {"キラキラ": 4, "ストレス": -3},
    ),
    (
        "bridge",
        "fragments1",
        "断片８",
        "歩道橋の夕焼け",
        "歩道橋に立つ",
        "歩道橋",
        "",
        1,
        {"ストレス": 3, "自認": 2},
    ),
    (
        "dream",
        "fragments1",
        "断片９",
        "透明な人の夢",
        "夢を思い出しながら歩く",
        "路上",
        "",
        3,
        {"自認": 3, "ストレス": -2},
    ),
    (
        "karaoke",
        "fragments1",
        "断片１０",
        "カラオケの割引券",
        "路上でティッシュをもらう",
        "路上",
        "",
        3,
        {"ストレス": 4, "自認": 2},
    ),
    (
        "native",
        "fragments2",
        "断片１",
        None,
        "授業を受ける",
        "教室",
        "",
        2,
        {"ストレス": 4, "自認": 3},
    ),
    (
        "sushi",
        "fragments2",
        "断片２",
        None,
        "母と夕飯を食べる",
        "自宅_リビング",
        "りあ",
        1,
        {},
    ),
    (
        "taiko",
        "fragments2",
        "断片３",
        None,
        "ゲーセンに寄る",
        "ゲームセンター",
        "",
        3,
        {},
    ),
    (
        "sumika",
        "fragments2",
        "断片４",
        None,
        "すみかと昼ごはん",
        "ファミレス(昼)",
        "すみか",
        2,
        {},
    ),
    ("inori", "fragments2", "断片５", None, "ショート動画を眺める", "自室", "", 3, {}),
    ("tv", "fragments2", "断片６", None, "テレビを見る", "自室", "", 1, {}),
    ("cry", "fragments2", "断片７", None, "母と話す", "リビング", "りあ", 3, {}),
]
# Tutorial choices: the counselor's questions move the parameters right away.
TUTORIAL_EFFECTS = {
    10: [{"自認": 4}, {"キラキラ": 4, "ストレス": 3}, {"ストレス": 4, "自認": 2}],
    20: [
        {"ストレス": 4, "自認": 2},
        {"ストレス": 5, "勇気": -2},
        {"ストレス": 6, "自認": 3},
    ],
    35: [
        {"ストレス": -6, "キラキラ": 2},
        {"ストレス": -3, "自認": 2},
        {"ストレス": 4, "自認": 4},
    ],
}
TUTORIAL_PROMPTS = {20: "いちばんのハードルは……"}
REST_LINES = [
    ("", "今日はどこにも寄らず、まっすぐ家に帰った。"),
    ("", "制服を脱いで、ベッドに倒れ込む。\n天井を見ているうちに、目が閉じていく。"),
    ("よだか", "（……何もしない日が、あってもいい）"),
]


def read_workbook(path):
    with zipfile.ZipFile(path) as archive:

        def text(element):
            # Exclude Excel's phonetic rPh runs: they are not scenario text.
            return "".join(
                t.text or ""
                for t in element.findall("m:t", NS) + element.findall("m:r/m:t", NS)
            )

        strings = [text(e) for e in ET.fromstring(archive.read("xl/sharedStrings.xml"))]
        sheets = ET.fromstring(archive.read("xl/workbook.xml")).findall(
            "m:sheets/m:sheet", NS
        )
        result = []
        for index, sheet in enumerate(sheets, 1):
            rows = []
            xml = ET.fromstring(archive.read(f"xl/worksheets/sheet{index}.xml"))
            for row in xml.findall(".//m:row", NS):
                cells = {"row": int(row.get("r"))}
                for cell in row:
                    value = cell.find("m:v", NS)
                    value = value.text if value is not None else ""
                    if cell.get("t") == "s":
                        value = strings[int(value)]
                    if value:
                        cells["".join(c for c in cell.get("r") if c.isalpha())] = value
                if len(cells) > 1:
                    rows.append(cells)
            result.append({"file": path.name, "sheet": sheet.get("name"), "rows": rows})
        return result


def load_sources():
    """Sheets keyed by (book, sheet name): workbook when present, else the cache."""
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    sources = {}
    for key, pattern in BOOKS.items():
        paths = sorted(p for p in ROOT.glob("*.xlsx") if pattern in p.name)
        if paths:
            for sheet in read_workbook(paths[0]):
                sources[(key, sheet["sheet"])] = sheet
        else:
            for file, sheets in cache.items():
                if pattern in file:
                    for name, rows in sheets.items():
                        sources[(key, name)] = {
                            "file": file,
                            "sheet": name,
                            "rows": rows,
                        }
    return sources


def sheet_title(sheet):
    return next(r["B"].split("：")[-1] for r in sheet["rows"] if r["row"] == 3)


def dialogue_rows(sheet):
    return [r for r in sheet["rows"] if r["row"] >= 5 and "C" in r]


def compile_scenario():
    sources = load_sources()
    nodes = {}
    used = {}

    def sheet(book, name):
        source = sources[(book, name)]
        used.setdefault(source["file"], {})[name] = [
            {k: v for k, v in r.items() if k in ["row", "B", "C", "D"]}
            for r in source["rows"]
            if r["row"] == 3 or (r["row"] >= 5 and ("C" in r or "D" in r))
        ]
        return source

    def add(node_id, row, sheet_info, **fields):
        nodes[node_id] = {
            "speaker": row.get("B", ""),
            "text": row["C"],
            "source": {
                "file": sheet_info["file"],
                "sheet": sheet_info["sheet"],
                "row": row["row"],
            },
            **fields,
        }

    # --- Opening counseling: OP sheet, then the system tutorial with its choices.
    counsel = {
        "chapter": "はじめてのカウンセリング",
        "chapter_index": 0,
        "kind": "counsel",
        "place": "診察室",
        "partner": "みなと",
    }
    tails = []  # nodes whose "next" is the following regular line

    def line(node_id, row, sheet_info):
        add(node_id, row, sheet_info, next="", **counsel)
        for tail in tails:
            nodes[tail]["next"] = node_id
        tails.clear()
        tails.append(node_id)

    opening = sheet("counseling", "カウンセリング0")
    for row in dialogue_rows(opening):
        line(f"counsel0_{row['row']}", row, opening)
    start = "counsel0_" + str(dialogue_rows(opening)[0]["row"])
    tutorial = sheet("counseling", "カウンセリング1")
    rows = [r for r in tutorial["rows"] if r["row"] >= 5 and ("C" in r or "D" in r)]
    prompt = ""
    i = 0
    while i < len(rows):
        row = rows[i]
        labels = row.get("C", "").split("／")
        marker = rows[i + 1].get("D", "") if i + 1 < len(rows) else ""
        # A choice row lists labels with ／ and is followed by "<label>[、を選択]".
        if (
            "B" not in row
            and len(labels) > 1
            and "C" not in rows[i + 1]
            and marker.replace("、を選択", "").replace("を選択", "") == labels[0]
        ):
            node_id = f"counsel1_{row['row']}"
            prompt_row = {
                "row": row["row"],
                "C": TUTORIAL_PROMPTS.get(row["row"], prompt),
            }
            line(node_id, prompt_row, tutorial)
            tails.clear()
            branches = []
            i += 1
            while rows[i].get("D") != "選択肢差分終了":
                if "C" not in rows[i]:
                    branches.append([])  # "<label>、を選択" opens a branch
                else:
                    branch_id = f"counsel1_{rows[i]['row']}"
                    add(branch_id, rows[i], tutorial, next="", **counsel)
                    if branches[-1]:
                        nodes[branches[-1][-1]]["next"] = branch_id
                    branches[-1].append(branch_id)
                i += 1
            assert len(branches) == len(labels), (labels, branches)
            nodes[node_id]["choices"] = [
                {"text": label, "next": branch[0], "effects": effects}
                for label, branch, effects in zip(
                    labels, branches, TUTORIAL_EFFECTS[row["row"]]
                )
            ]
            tails.extend(branch[-1] for branch in branches)
        elif "C" in row and row["C"] != "暗転":
            node_id = f"counsel1_{row['row']}"
            line(node_id, row, tutorial)
            if "C" not in rows[i + 1] and "ステータス" in rows[i + 1].get("D", ""):
                nodes[node_id]["karte"] = True
        else:
            prompt = row.get("D", "")
        i += 1
    for tail in tails:
        nodes[tail]["next"] = "map"

    # --- Main chapters, one per round.
    chapters = []
    for index, name in enumerate(
        ["メイン01v3", "メイン02v3", "メイン03v3", "メイン04v3"]
    ):
        key = f"main{index + 1}"
        source = sheet("main", name)
        title = sheet_title(source)
        chapter_ids = []
        place = "街"
        for row in source["rows"]:
            if row["row"] < 5:
                continue
            if "背景：" in row.get("D", ""):
                place = row["D"].split("背景：")[1].split("\n")[0]
            if "C" not in row:
                continue
            node_id = f"{key}_{row['row']}"
            partner = "あしか" if key != "main1" or row["row"] >= 8 else ""
            add(
                node_id,
                row,
                source,
                chapter=title,
                chapter_index=index + 1,
                kind="main",
                place=place,
                partner=partner,
                next="night",
            )
            if chapter_ids:
                nodes[chapter_ids[-1]]["next"] = node_id
            chapter_ids.append(node_id)
        chapters.append(
            {"id": key, "title": title, "start": chapter_ids[0], "index": index + 1}
        )

    def choice(node_id, labels, targets):
        nodes[node_id]["text"] = "この気持ちを、どう受け止めよう。"
        nodes[node_id]["choices"] = [
            {"text": text, "next": target} for text, target in zip(labels, targets)
        ]

    choice("main2_31", ["考えてみる", "考えない"], ["main2_33", "main2_40"])
    choice("main2_38", ["想像してみた", "想像できなかった"], ["main2_44", "main2_44"])
    nodes["main2_42"]["next"] = "main2_44"
    choice("main3_22", ["当たり前に思えた", "違和感だった"], ["main3_23", "main3_23b"])
    for row in [23, 24]:
        nodes[f"main3_{row}b"] = dict(nodes[f"main3_{row}"])
    nodes["main3_23b"]["next"] = "main3_24b"
    nodes["main3_24b"]["next"] = "main3_29"
    nodes["main3_27"]["next"] = "main3_34"
    choice(
        "main4_31", ["おかしくない", "お姫様じゃなくてもいい"], ["main4_33", "main4_38"]
    )
    nodes["main4_36"]["next"] = "main4_48"
    nodes["main4_31"]["choices"][1]["requires"] = {"stat": "勇気", "min": COURAGE_GATE}

    # --- MAP outings: every fragment is a place to go; each ends in the night.
    map_events = []
    for key, book, name, title, label, place, partner, unlock, effects in EVENTS:
        source = sheet(book, name)
        title = title or sheet_title(source)
        rows = dialogue_rows(source)
        event_ids = [f"{key}_{r['row']}" for r in rows]
        for i, row in enumerate(rows):
            add(
                event_ids[i],
                row,
                source,
                chapter="寄り道 / " + title,
                chapter_index=0,
                kind="outing",
                place=place,
                partner=partner,
                next=event_ids[i + 1] if i + 1 < len(rows) else "night",
            )
        if effects:
            nodes[event_ids[-1]]["effects"] = effects
        map_events.append(
            {
                "id": key,
                "start": event_ids[0],
                "title": title,
                "label": label,
                "place": place,
                "unlock": unlock,
            }
        )
    for i, (speaker, text) in enumerate(REST_LINES):
        nodes[f"rest_{i}"] = {
            "speaker": speaker,
            "text": text,
            "chapter": "寄り道 / 家で休む",
            "chapter_index": 0,
            "kind": "outing",
            "place": "自宅_リビング",
            "partner": "",
            "next": f"rest_{i + 1}" if i + 1 < len(REST_LINES) else "night",
        }
    nodes["rest_2"]["effects"] = {"ストレス": -15}
    map_events.append(
        {
            "id": "rest",
            "start": "rest_0",
            "title": "何もしない日",
            "label": "家で休む",
            "place": "自宅_リビング",
            "unlock": 1,
            "repeatable": True,
        }
    )

    markers = json.loads((ROOT / "src/data/word_marks.json").read_text())
    for marker in markers:
        node = nodes[marker["node"]]
        assert marker["word"] in node["text"], marker
        marker["quote"] = node["text"]
        marker["speaker"] = node["speaker"]
        node["word"] = marker["id"]
    result = {
        "start": start,
        "stats": STATS,
        "initial": INITIAL,
        "nodes": nodes,
        "chapters": chapters,
        "rounds": ROUNDS,
        "map_events": map_events,
        "words": markers,
    }
    (ROOT / "src/data/scenario.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2)
    )
    CACHE.write_text(json.dumps(used, ensure_ascii=False, indent=1))
    print(
        f"Compiled {len(nodes)} nodes, {len(markers)} words; cached {len(used)} books."
    )
    return result


if __name__ == "__main__":
    compile_scenario()
