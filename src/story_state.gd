class_name StoryState
extends RefCounted

const STAT_NAMES = ["ストレス", "勇気", "自認", "キラキラ"]
const INITIAL = [60, 35, 35, 35]
const STRESS_LIMIT = 80
const SLEEP_EFFECTS = {"ストレス": -4}
const OUTING_EFFECTS = {"ストレス": 5}
const CHAPTER_EFFECTS = {"ストレス": 6}
const SAVE_PATH = "user://yodaka_v1.json"
const COUNSEL_STEPS = ["opening_doctor", "opening_yodaka", "recall", "grown_reply",
    "question", "choice", "reply", "response", "closing", "farewell"]
var save_path: String = SAVE_PATH
var data: Dictionary = {}
var current: String = ""
var collected: Array = []
var gains: Dictionary = {}
var answers: Array = []
var stats: Array = INITIAL.duplicate()
var history: Array = []
var read_count: int = 0
var speed: float = 32.0
var last_error: String = ""
var last_delta: Array = []
var scene_key: String = ""
var pending_word: String = ""
var counsel_step: String = "opening_doctor"
var reviewed: int = 0
var round_index: int = 0
var outings_done: int = 0
var visited: Array = []
var after_night: String = "map"
var night_step: String = "pick"
var night_word: String = ""

func _init() -> void:
    data = JSON.parse_string(FileAccess.get_file_as_string("res://src/data/scenario.json"))
    current = data.start

func reset() -> void:
    current = data.start
    collected.clear()
    gains.clear()
    answers.clear()
    stats = INITIAL.duplicate()
    history.clear()
    read_count = 0
    last_delta = []
    scene_key = ""
    pending_word = ""
    counsel_step = "opening_doctor"
    reviewed = 0
    round_index = 0
    outings_done = 0
    visited.clear()
    after_night = "map"
    night_step = "pick"
    night_word = ""

func word_by_id(id: String) -> Dictionary:
    for word in data.words:
        if word.id == id:
            return word
    return {}

func event_by_id(id: String) -> Dictionary:
    for event in data.map_events:
        if event.id == id:
            return event
    return {}

func answer_for(id: String) -> Dictionary:
    for answer in answers:
        if answer.word == id:
            return answer
    return {}

func is_grown(id: String) -> bool:
    return not answer_for(id).is_empty()

func preview(effects: Dictionary) -> Array:
    var delta: Array = []
    for i in range(STAT_NAMES.size()):
        delta.append(0)
    for stat in effects:
        var i: int = STAT_NAMES.find(stat)
        if i >= 0:
            delta[i] = clampi(int(stats[i]) + int(effects[stat]), 0, 100) - int(stats[i])
    return delta

func apply(effects: Dictionary) -> Array:
    var delta := preview(effects)
    for i in range(STAT_NAMES.size()):
        stats[i] = int(stats[i]) + delta[i]
    last_delta = delta
    return delta

func has_change(delta: Array) -> bool:
    return delta.any(func(value): return value != 0)

func finish_line() -> bool:
    if not data.nodes.has(current):
        return false
    var node: Dictionary = data.nodes[current]
    var added := false
    last_delta = []
    if node.has("word") and not collected.has(node.word):
        collected.append(node.word)
        gains[node.word] = apply(word_by_id(node.word).get("effects", {}))
        pending_word = node.word
        added = true
    if history.is_empty() or history.back().id != current:
        history.append({"id": current, "speaker": node.speaker, "text": node.text})
        read_count += 1
        if node.has("effects"):
            apply(node.effects)
    save_game()
    return added

func can_choose(index: int) -> bool:
    if not data.nodes.has(current):
        return false
    var node: Dictionary = data.nodes[current]
    if not node.has("choices"):
        return index == 0
    if index < 0 or index >= node.choices.size():
        return false
    var requirement: Dictionary = node.choices[index].get("requires", {})
    return requirement.is_empty() or stats[STAT_NAMES.find(requirement.stat)] >= requirement.min

func choose(index: int) -> bool:
    if not can_choose(index):
        return false
    var node: Dictionary = data.nodes[current]
    last_delta = []
    if node.has("choices"):
        history.append({"id": current + "_choice", "speaker": "選んだこと",
            "text": node.choices[index].text})
        apply(node.choices[index].get("effects", {}))
        current = node.choices[index].next
    else:
        current = node.next
    if current == "night":
        _enter_night(node.get("kind", ""))
    save_game()
    return true

func _enter_night(kind: String) -> void:
    night_step = "pick"
    night_word = ""
    if kind == "main":
        round_index += 1
        outings_done = 0
        after_night = "map" if round_index < data.rounds.size() else "counseling"
    else:
        outings_done += 1
        after_night = "map" if outings_done < int(data.rounds[round_index].outings) else "chapter"

func current_round() -> Dictionary:
    if round_index < data.rounds.size():
        return data.rounds[round_index]
    return data.rounds.back()

func stress_locked() -> bool:
    return int(stats[0]) >= STRESS_LIMIT

func event_available(id: String) -> bool:
    var event := event_by_id(id)
    if event.is_empty() or current != "map" or round_index >= data.rounds.size():
        return false
    if int(event.unlock) > round_index + 1:
        return false
    if visited.has(id) and not event.get("repeatable", false):
        return false
    return event.get("repeatable", false) or not stress_locked()

func select_event(id: String) -> bool:
    if not event_available(id):
        return false
    var event := event_by_id(id)
    if not event.get("repeatable", false):
        visited.append(id)
        apply(OUTING_EFFECTS)  # going out costs social energy; resting does not
    current = event.start
    save_game()
    return true

func grow_candidates() -> Array:
    return collected.filter(func(id): return not is_grown(id))

func preview_interpretation(id: String, index: int) -> Array:
    var word := word_by_id(id)
    if word.is_empty() or index not in [0, 1, 2]:
        return []
    return preview(word.interpretations[index].effects)

func grow(id: String, index: int) -> Array:
    if current != "night" or night_step != "pick" or is_grown(id) or not collected.has(id):
        return []
    var delta := preview_interpretation(id, index)
    if delta.is_empty():
        return []
    apply(word_by_id(id).interpretations[index].effects)
    answers.append({"word": id, "choice": index, "delta": delta, "stage": "night"})
    night_word = id
    night_step = "reply"
    save_game()
    return delta

func sleep() -> Array:
    if current != "night":
        return []
    var delta := apply(SLEEP_EFFECTS)
    night_step = "pick"
    night_word = ""
    match after_night:
        "chapter":
            for chapter in data.chapters:
                if chapter.id == current_round().chapter:
                    current = chapter.start
            var cost := apply(CHAPTER_EFFECTS)
            for i in range(STAT_NAMES.size()):
                delta[i] += cost[i]
            last_delta = delta
        "counseling":
            current = "counseling"
            counsel_step = "opening_doctor"
            reviewed = 0
        _:
            current = "map"
    save_game()
    return delta

func review_word() -> Dictionary:
    if reviewed < collected.size():
        return word_by_id(collected[reviewed])
    return {}

func interpret(index: int) -> Array:
    if current != "counseling" or counsel_step != "choice" or reviewed >= collected.size():
        return []
    var id: String = collected[reviewed]
    if is_grown(id):
        return []
    var delta := preview_interpretation(id, index)
    if delta.is_empty():
        return []
    apply(word_by_id(id).interpretations[index].effects)
    answers.append({"word": id, "choice": index, "delta": delta, "stage": "counseling"})
    counsel_step = "reply"
    save_game()
    return delta

func advance_counseling() -> bool:
    if current != "counseling":
        return false
    match counsel_step:
        "opening_doctor":
            counsel_step = "opening_yodaka"
        "opening_yodaka":
            counsel_step = "recall" if reviewed < collected.size() else "closing"
        "recall":
            counsel_step = "grown_reply" if is_grown(collected[reviewed]) else "question"
        "grown_reply", "reply":
            counsel_step = "response"
        "question":
            counsel_step = "choice"
        "response":
            reviewed += 1
            counsel_step = "recall" if reviewed < collected.size() else "closing"
        "closing":
            counsel_step = "farewell"
        "farewell":
            current = "result"
            counsel_step = "opening_doctor"
        _:
            return false
    save_game()
    return true

func save_game() -> bool:
    var file := FileAccess.open(save_path, FileAccess.WRITE)
    if file == null:
        last_error = "この環境では保存できません"
        return false
    file.store_string(JSON.stringify({"version": 4, "current": current,
        "collected": collected, "gains": gains, "answers": answers, "stats": stats,
        "history": history, "read_count": read_count, "speed": speed,
        "scene_key": scene_key, "pending_word": pending_word,
        "counsel_step": counsel_step, "reviewed": reviewed,
        "round_index": round_index, "outings_done": outings_done, "visited": visited,
        "after_night": after_night, "night_step": night_step, "night_word": night_word}))
    last_error = ""
    return true

func has_save() -> bool:
    return FileAccess.file_exists(save_path)

static func _is_int(value, low: int, high: int) -> bool:
    return (value is float or value is int) and value == int(value) and int(value) >= low and int(value) <= high

func _valid_delta(value) -> bool:
    if not value is Array or value.size() != STAT_NAMES.size():
        return false
    for entry in value:
        if not (entry is float or entry is int):
            return false
    return true

func load_game() -> bool:
    if not has_save():
        return false
    var parser := JSON.new()
    if parser.parse(FileAccess.get_file_as_string(save_path)) != OK:
        return false
    var saved = parser.data
    if not saved is Dictionary or saved.get("version", 0) != 4:
        return false
    var node_id = saved.get("current", "")
    if not node_id is String or (not node_id in ["map", "night", "counseling", "result"] and not data.nodes.has(node_id)):
        return false
    if not saved.get("stats") is Array or saved.stats.size() != STAT_NAMES.size():
        return false
    for value in saved.stats:
        if not _is_int(value, 0, 100):
            return false
    if not saved.get("collected") is Array or not saved.get("answers") is Array or not saved.get("history") is Array:
        return false
    if not saved.get("gains", {}) is Dictionary or not saved.get("visited", []) is Array:
        return false
    var seen: Array = []
    for id in saved.collected:
        if not id is String or word_by_id(id).is_empty() or seen.has(id):
            return false
        seen.append(id)
    for id in saved.gains:
        if not seen.has(id) or not _valid_delta(saved.gains[id]):
            return false
    var answered: Array = []
    for answer in saved.answers:
        if not answer is Dictionary or not seen.has(answer.get("word")) or answered.has(answer.get("word")):
            return false
        if not _is_int(answer.get("choice", -1), 0, 2) or not _valid_delta(answer.get("delta")):
            return false
        if answer.get("stage", "") not in ["night", "counseling"]:
            return false
        answered.append(answer.word)
        answer.choice = int(answer.choice)
        answer.delta = answer.delta.map(func(value): return int(value))
    for entry in saved.history:
        if not entry is Dictionary or not entry.get("text") is String or not entry.get("speaker") is String or not entry.get("id") is String:
            return false
    var step = saved.get("counsel_step", "opening_doctor")
    if step not in COUNSEL_STEPS or not _is_int(saved.get("reviewed", 0), 0, seen.size()):
        return false
    if step in ["reply", "response", "grown_reply"] and (int(saved.reviewed) >= seen.size() or not answered.has(seen[int(saved.reviewed)])):
        return false
    if step in ["recall", "question", "choice"] and int(saved.reviewed) >= seen.size():
        return false
    if not _is_int(saved.get("round_index", 0), 0, data.rounds.size()) or not _is_int(saved.get("outings_done", 0), 0, 99):
        return false
    for id in saved.visited:
        if not id is String or event_by_id(id).is_empty():
            return false
    if saved.get("after_night", "map") not in ["map", "chapter", "counseling"] or saved.get("night_step", "pick") not in ["pick", "reply"]:
        return false
    var night = saved.get("night_word", "")
    if not night is String or (night != "" and not answered.has(night)) or (saved.get("night_step", "pick") == "reply" and night == ""):
        return false
    var pending = saved.get("pending_word", "")
    if not pending is String or (pending != "" and not seen.has(pending)):
        return false
    if not saved.get("scene_key", "") is String:
        return false
    current = node_id
    collected = saved.collected
    gains = {}
    for id in saved.gains:
        gains[id] = saved.gains[id].map(func(value): return int(value))
    answers = saved.answers
    stats = saved.stats.map(func(value): return int(value))
    history = saved.history
    read_count = int(saved.get("read_count", 0))
    speed = clampf(float(saved.get("speed", 32)), 12, 80)
    scene_key = saved.get("scene_key", "")
    pending_word = pending
    counsel_step = step
    reviewed = int(saved.get("reviewed", 0))
    round_index = int(saved.get("round_index", 0))
    outings_done = int(saved.get("outings_done", 0))
    visited = saved.visited
    after_night = saved.get("after_night", "map")
    night_step = saved.get("night_step", "pick")
    night_word = night
    last_delta = []
    return true
