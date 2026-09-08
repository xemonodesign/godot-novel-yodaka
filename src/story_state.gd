class_name StoryState
extends RefCounted

const STAT_NAMES = ["ストレス", "勇気", "知性", "忍耐", "キラキラ", "自認"]
const INITIAL = [65, 40, 45, 40, 35, 35]
const SAVE_PATH = "user://yodaka_v1.json"
var save_path: String = SAVE_PATH
var data: Dictionary = {}
var current: String = "intro_0"
var collected: Array = []
var answers: Array = []
var stats: Array = INITIAL.duplicate()
var history: Array = []
var read_count: int = 0
var speed: float = 32.0
var last_error: String = ""
var scene_key: String = ""
var pending_word: String = ""
var counsel_step: String = "opening_doctor"

func _init() -> void:
    data = JSON.parse_string(FileAccess.get_file_as_string("res://src/data/scenario.json"))

func reset() -> void:
    current = data.start
    collected.clear()
    answers.clear()
    stats = INITIAL.duplicate()
    history.clear()
    read_count = 0
    scene_key = ""
    pending_word = ""
    counsel_step = "opening_doctor"

func word_by_id(id: String) -> Dictionary:
    for word in data.words:
        if word.id == id:
            return word
    return {}

func finish_line() -> bool:
    if not data.nodes.has(current):
        return false
    var node: Dictionary = data.nodes[current]
    var added := false
    if node.has("word") and not collected.has(node.word):
        collected.append(node.word)
        pending_word = node.word
        added = true
    if history.is_empty() or history.back().id != current:
        history.append({"id": current, "speaker": node.speaker, "text": node.text})
        read_count += 1
    save_game()
    return added

func choose(index: int) -> void:
    var node: Dictionary = data.nodes[current]
    if node.has("choices"):
        history.append({"id": current + "_choice", "speaker": "選んだこと",
            "text": node.choices[index].text})
        current = node.choices[index].next
    else:
        current = node.next
    save_game()

func preview_effects(index: int) -> Array:
    if answers.size() >= collected.size() or index not in [0, 1, 2]:
        return []
    var word := word_by_id(collected[answers.size()])
    var delta: Array = [0, 0, 0, 0, 0, 0]
    var effects: Dictionary = word.interpretations[index].effects
    for stat in effects:
        var i: int = STAT_NAMES.find(stat)
        delta[i] = clampi(int(stats[i]) + int(effects[stat]), 0, 100) - int(stats[i])
    return delta

func interpret(index: int) -> Array:
    var delta := preview_effects(index)
    if delta.is_empty():
        return []
    var word := word_by_id(collected[answers.size()])
    for i in range(6):
        stats[i] += delta[i]
    answers.append({"word": word.id, "choice": index, "delta": delta})
    counsel_step = "reply"
    save_game()
    return delta

func save_game() -> bool:
    var file := FileAccess.open(save_path, FileAccess.WRITE)
    if file == null:
        last_error = "この環境では保存できません"
        return false
    file.store_string(JSON.stringify({"version": 2, "current": current,
        "collected": collected, "answers": answers, "stats": stats,
        "history": history, "read_count": read_count, "speed": speed,
        "scene_key": scene_key, "pending_word": pending_word,
        "counsel_step": counsel_step}))
    last_error = ""
    return true

func has_save() -> bool:
    return FileAccess.file_exists(save_path)

func load_game() -> bool:
    if not has_save():
        return false
    var parser := JSON.new()
    if parser.parse(FileAccess.get_file_as_string(save_path)) != OK:
        return false
    var saved = parser.data
    if not saved is Dictionary:
        return false
    var version = saved.get("version", 0)
    if not (version is float or version is int) or version != int(version) or int(version) not in [1, 2]:
        return false
    if not saved.get("current", "") in ["counseling", "result"] and not data.nodes.has(saved.get("current", "")):
        return false
    if not saved.get("stats") is Array or saved.stats.size() != 6:
        return false
    for value in saved.stats:
        if not (value is float or value is int) or value < 0 or value > 100:
            return false
    if not saved.get("collected") is Array or not saved.get("answers") is Array or not saved.get("history") is Array:
        return false
    var seen: Array = []
    for id in saved.collected:
        if not id is String or word_by_id(id).is_empty() or seen.has(id):
            return false
        seen.append(id)
    if saved.answers.size() > seen.size():
        return false
    for i in range(saved.answers.size()):
        var answer = saved.answers[i]
        if not answer is Dictionary or answer.get("word") != seen[i]:
            return false
        var choice = answer.get("choice", -1)
        if not (choice is float or choice is int) or choice != int(choice) or int(choice) not in [0, 1, 2]:
            return false
        if not answer.get("delta") is Array or answer.delta.size() != 6:
            return false
        for value in answer.delta:
            if not (value is float or value is int):
                return false
        answer.choice = int(choice)
        answer.delta = answer.delta.map(func(value): return int(value))
    for entry in saved.history:
        if not entry is Dictionary or not entry.get("text") is String or not entry.get("speaker") is String or not entry.get("id") is String:
            return false
    var step = saved.get("counsel_step", "opening_doctor")
    if step not in ["opening_doctor", "opening_yodaka", "recall", "question", "choice", "reply", "response"]:
        return false
    if step in ["reply", "response"] and saved.answers.is_empty():
        return false
    var pending = saved.get("pending_word", "")
    if not pending is String or (pending != "" and not seen.has(pending)):
        return false
    if not saved.get("scene_key", "") is String:
        return false
    current = saved.current
    collected = saved.collected
    answers = saved.answers
    stats = saved.stats.map(func(value): return int(value))
    history = saved.history
    read_count = int(saved.get("read_count", 0))
    speed = clampf(float(saved.get("speed", 32)), 12, 80)
    scene_key = saved.get("scene_key", "")
    pending_word = pending
    counsel_step = step
    return true
