"""Compile the original XLSX text and explicit branch/word annotations for Godot."""

import json
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


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


def compile_scenario():
    books = {"main": [], "fragments1": [], "fragments2": []}
    for path in ROOT.glob("*.xlsx"):
        key = (
            "main"
            if "メイン" in path.name
            else "fragments1" if "断片集1" in path.name else "fragments2"
        )
        books[key] = read_workbook(path)
    nodes = {}
    chapters = []
    sequence = [
        ("mother", books["fragments2"][1]),
        ("main1", books["main"][0]),
        ("main2", books["main"][1]),
        ("sumika", books["fragments2"][3]),
        ("main3", books["main"][2]),
        ("main4", books["main"][3]),
    ]
    previous = None
    for chapter_index, (key, sheet) in enumerate(sequence):
        title = next(r["B"].split("：")[-1] for r in sheet["rows"] if r["row"] == 3)
        ids = []
        place = "街"
        for row in sheet["rows"]:
            if row["row"] < 5:
                continue
            if "背景：" in row.get("D", ""):
                place = row["D"].split("背景：")[1].split("\n")[0]
            if "C" not in row:
                continue
            node_id = f"{key}_{row['row']}"
            ids.append(node_id)
            nodes[node_id] = {
                "speaker": row.get("B", ""),
                "text": row["C"],
                "chapter": title,
                "chapter_index": chapter_index + 1,
                "place": place,
                "next": "counseling",
                "source": {
                    "file": sheet["file"],
                    "sheet": sheet["sheet"],
                    "row": row["row"],
                },
            }
            if previous:
                nodes[previous]["next"] = node_id
            previous = node_id
        chapters.append({"id": key, "title": title, "start": ids[0]})

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
    intro = [
        (
            "医師",
            "よだかさん。身体が変わってから、いろいろなことがありましたね。\n今日は、答えを急がずにお話ししましょう。",
        ),
        (
            "よだか",
            "TSして、バスケを辞めて。\n自分のことなのに、まだうまく考えられません。",
        ),
        (
            "医師",
            "変化を受け入れるか、受け入れないか。\n今すぐ決める必要はありません。迷ったままでも大丈夫です。",
        ),
        (
            "医師",
            "いろいろな人と話してみてください。\n心に残る言葉があったら、少しだけ持って帰ってきましょう。",
        ),
        (
            "医師",
            "嬉しかった言葉も、引っかかった言葉も。\n誰かの言葉を、そのまま自分の答えにしなくてもいいんです。",
        ),
        (
            "医師",
            "来週、また聞かせてください。\n誰と、どんな話をして、その時どう感じたのか。\nよだかさんの言葉で、ゆっくり話してもらえたら。",
        ),
        ("よだか", "……はい。\nまだ空っぽのままだけど、少し、話してみます。"),
    ]
    for i, (speaker, text) in enumerate(intro):
        nodes[f"intro_{i}"] = {
            "speaker": speaker,
            "text": text,
            "chapter": "答えを急がない日",
            "chapter_index": 0,
            "place": "診察室",
            "next": f"intro_{i+1}" if i + 1 < len(intro) else chapters[0]["start"],
        }
    markers = json.loads((ROOT / "src/data/word_marks.json").read_text())
    for marker in markers:
        node = nodes[marker["node"]]
        assert marker["word"] in node["text"], marker
        marker["quote"] = node["text"]
        marker["speaker"] = node["speaker"]
        node["word"] = marker["id"]
    result = {
        "start": "intro_0",
        "nodes": nodes,
        "chapters": chapters,
        "words": markers,
    }
    (ROOT / "src/data/scenario.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2)
    )
    (ROOT / "src/data/source_archive.json").write_text(
        json.dumps(books, ensure_ascii=False, indent=2)
    )
    print(f"Compiled {len(nodes)} nodes, {len(markers)} words; archived all 21 sheets.")
    return result


if __name__ == "__main__":
    compile_scenario()
