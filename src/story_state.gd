class_name StoryState
extends RefCounted

const STAT_NAMES = ["ストレス", "勇気", "自認", "キラキラ"]
const INITIAL = [60, 5, 5, 5]
const STRESS_LIMIT = 80
const OUTING_EFFECTS = {"ストレス": 5}
const CHAPTER_EFFECTS = {"ストレス": 6}
const SAVE_PATH = "user://yodaka_v1.json"
const SLOTS = 8  # the word shelf; six slots start taken by traumas, two are free
const EXP_PER_TAP = 1  # every line read for the first time earns this, times held multipliers
const RESONANCE = 2  # a word whose tag matches the trauma counts its discount this many times
const MAX_LEVEL = 3
const SESSIONS = 4  # opening, two in between, closing
const TRAUMA_STATES = ["mystery", "appraised", "accepted"]
const COUNSEL_STEPS = ["opening_doctor", "opening_yodaka", "board", "talk_recall", "talk_doctor",
    "face_line", "face_response", "grow_question", "grow_choice", "grow_reply", "grow_response",
    "grow_insight", "closing", "farewell"]
var save_path: String = SAVE_PATH
var data: Dictionary = {}
var current: String = ""
var collected: Array = []  # every word received, in order
var slots: Array = []  # SLOTS entries: {} or {"kind": "trauma" | "word", "id": ...}
var forgotten: Array = []  # words let go for EXP
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
var exp: int = 0
var exp_total: int = 0
var traumas: Dictionary = {}  # id -> {"state": mystery | appraised | accepted}
var levels: Dictionary = {}  # word id -> level, 1 when absent
var session: int = 0
var counsel_step: String = "opening_doctor"
var talked: bool = false
var focus: String = ""
var grow_word: String = ""
var round_index: int = 0
var outings_done: int = 0
var visited: Array = []

func _init() -> void:
    data = JSON.parse_string(FileAccess.get_file_as_string("res://src/data/scenario.json"))
    current = data.start
    reset()

func reset() -> void:
    current = data.start
    collected.clear()
    slots.clear()
    traumas.clear()
    for trauma in data.traumas:
        slots.append({"kind": "trauma", "id": trauma.id})
        traumas[trauma.id] = {"state": "mystery"}
    while slots.size() < SLOTS:
        slots.append({})
    forgotten.clear()
    gains.clear()
    answers.clear()
    stats = INITIAL.duplicate()
    history.clear()
    read_count = 0
    last_delta = []
    scene_key = ""
    pending_word = ""
    exp = 0
    exp_total = 0
    levels.clear()
    session = 0
    counsel_step = "opening_doctor"
    talked = false
    focus = ""
    grow_word = ""
    round_index = 0
    outings_done = 0
    visited.clear()

# --- Definitions -----------------------------------------------------------

func word_by_id(id: String) -> Dictionary:
    for word in data.words:
        if word.id == id:
            return word
    return {}

func trauma_def(id: String) -> Dictionary:
    for trauma in data.traumas:
        if trauma.id == id:
            return trauma
    return {}

func event_by_id(id: String) -> Dictionary:
    for event in data.map_events:
        if event.id == id:
            return event
    return {}

func answer_for(id: String) -> Dictionary:
    for i in range(answers.size() - 1, -1, -1):
        if answers[i].word == id:
            return answers[i]
    return {}

# --- The shelf: traumas and words in eight slots ---------------------------

func slot_of(id: String) -> int:
    for i in range(slots.size()):
        if not slots[i].is_empty() and slots[i].id == id:
            return i
    return -1

func held_words() -> Array:
    return slots.filter(func(s): return not s.is_empty() and s.kind == "word").map(func(s): return s.id)

func held_traumas() -> Array:
    return slots.filter(func(s): return not s.is_empty() and s.kind == "trauma").map(func(s): return s.id)

func free_slot() -> int:
    for i in range(slots.size()):
        if slots[i].is_empty():
            return i
    return -1

func trauma_state(id: String) -> String:
    return traumas[id].state if traumas.has(id) else ""

func level_of(id: String) -> int:
    return int(levels.get(id, 1))

func level_data(id: String, level: int = 0) -> Dictionary:
    var word := word_by_id(id)
    if word.is_empty():
        return {}
    return word.levels[clampi((level if level > 0 else level_of(id)) - 1, 0, MAX_LEVEL - 1)]

func next_level_cost(id: String) -> int:
    if level_of(id) >= MAX_LEVEL:
        return -1
    return int(level_data(id, level_of(id) + 1).cost)

func hold_stat(stat: String) -> int:
    var total := 0
    for id in held_words():
        total += int(level_data(id).hold.get(stat, 0))
    return total

func exp_multiplier() -> int:
    var product := 1
    for id in held_words():
        product *= int(level_data(id).hold.get("exp_mult", 1))
    return product

func forget_multiplier(exclude: String = "") -> int:
    # The word leaving the shelf does not multiply its own farewell.
    var product := 1
    for id in held_words():
        if id != exclude:
            product *= int(level_data(id).hold.get("forget_mult", 1))
    return product

func resonates(word_id: String, trauma_id: String) -> bool:
    return word_by_id(word_id).get("tag", "") == trauma_def(trauma_id).get("tag", "-")

func cost_multiplier(trauma_id: String) -> float:
    # Held words cut the price of facing a trauma; a word of the same kind counts twice.
    var product := 1.0
    for id in held_words():
        var mult: float = float(level_data(id).hold.get("cost_mult", 1.0))
        for _i in range(RESONANCE if resonates(id, trauma_id) else 1):
            product *= mult
    return product

func exp_per_tap() -> int:
    return EXP_PER_TAP * exp_multiplier()

func earn_exp(amount: int) -> int:
    exp += amount
    exp_total += amount
    return amount

# --- Traumas: three states, each with a debuff ------------------------------

func debuff_active(kind: String) -> bool:
    for id in held_traumas():
        if trauma_def(id).debuff.kind == kind:
            return true
    return false

func debuff_amount(id: String) -> float:
    # A mystery bites by its hidden amount; opened, a trauma shows its full one.
    var debuff: Dictionary = trauma_def(id).debuff
    if trauma_state(id) == "appraised":
        return float(debuff.get("value", 0))
    return float(debuff.get("mystery", 0))

func trauma_cap(stat: String) -> int:
    var cap := 100
    for id in held_traumas():
        var debuff: Dictionary = trauma_def(id).debuff
        if debuff.kind == "cap" and debuff.stat == stat:
            cap = mini(cap, int(debuff_amount(id)))
    return cap

func effective_stats() -> Array:
    var result: Array = []
    for i in range(STAT_NAMES.size()):
        var stat: String = STAT_NAMES[i]
        var value: int = int(stats[i]) + hold_stat(stat)
        var fraction := 0.0
        for id in held_traumas():
            var debuff: Dictionary = trauma_def(id).debuff
            if debuff.get("stat", "") != stat:
                continue
            if debuff.kind == "plus":
                value += int(debuff_amount(id))
            elif debuff.kind == "half":
                fraction = maxf(fraction, debuff_amount(id))
        value -= int(floor(float(value) * fraction))
        value = mini(value, trauma_cap(stat))
        result.append(clampi(value, 0, 100))
    return result

func effective(index: int) -> int:
    return effective_stats()[index]

func debuff_text(id: String) -> String:
    var debuff: Dictionary = trauma_def(id).debuff
    match debuff.kind:
        "half":
            return "%s が %d%% 減る" % [debuff.stat, int(round(100.0 * debuff_amount(id)))]
        "cap":
            return "%s の上限 %d" % [debuff.stat, int(debuff_amount(id))]
        "plus":
            return "%s 常時 +%d" % [debuff.stat, int(debuff_amount(id))]
        "rest_half":
            return "家で休んでも回復が半分"
        "forget_half":
            return "手放した言葉のEXPが半分"
        "gain_half":
            return "もらった言葉の変化が半分"
    return ""

func appraise_cost(id: String) -> int:
    return int(trauma_def(id).get("appraise", 0))

func face_cost(id: String) -> int:
    var def := trauma_def(id)
    if def.is_empty():
        return 0
    return maxi(1, int(ceil(float(def.cost) * cost_multiplier(id) - 0.000001)))

func accepted_count() -> int:
    return traumas.values().filter(func(t): return t.state == "accepted").size()

# --- Stats ------------------------------------------------------------------

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

func halved(effects: Dictionary) -> Dictionary:
    var result := {}
    for stat in effects:
        result[stat] = int(round(float(effects[stat]) / 2.0))
    return result

func word_gain_effects(word: Dictionary) -> Dictionary:
    var effects: Dictionary = word.get("effects", {})
    return halved(effects) if debuff_active("gain_half") else effects

# --- Reading lines ----------------------------------------------------------

func finish_line() -> bool:
    if not data.nodes.has(current):
        return false
    var node: Dictionary = data.nodes[current]
    var added := false
    last_delta = []
    if node.has("word") and not collected.has(node.word):
        collected.append(node.word)
        gains[node.word] = apply(word_gain_effects(word_by_id(node.word)))
        pending_word = node.word
        added = true
    if history.is_empty() or history.back().id != current:
        history.append({"id": current, "speaker": node.speaker, "text": node.text})
        read_count += 1
        earn_exp(exp_per_tap())
        if node.has("effects"):
            var effects: Dictionary = node.effects
            if current.begins_with("rest_") and debuff_active("rest_half"):
                effects = halved(effects)
            apply(effects)
    save_game()
    return added

func read_dynamic(id: String, speaker: String, text: String) -> bool:
    # Counseling lines are composed at runtime; reading one still counts as a tap.
    if not history.is_empty() and history.back().id == id:
        return false
    history.append({"id": id, "speaker": speaker, "text": text})
    read_count += 1
    earn_exp(exp_per_tap())
    save_game()
    return true

func can_choose(index: int) -> bool:
    if not data.nodes.has(current):
        return false
    var node: Dictionary = data.nodes[current]
    if not node.has("choices"):
        return index == 0
    if index < 0 or index >= node.choices.size():
        return false
    var requirement: Dictionary = node.choices[index].get("requires", {})
    return requirement.is_empty() or effective(STAT_NAMES.find(requirement.stat)) >= requirement.min

func choose(index: int) -> bool:
    if not can_choose(index) or pending_word != "":
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
        _end_day(node.get("kind", ""))
    elif current == "counseling":
        _enter_counseling()
    save_game()
    return true

# --- Receiving a word: keep it, or let it go for EXP -----------------------

func forget_value(id: String) -> int:
    var word := word_by_id(id)
    if word.is_empty():
        return 0
    var value: int = int(word.forget) * forget_multiplier(id)
    if debuff_active("forget_half"):
        value = int(ceil(float(value) / 2.0))
    return maxi(1, value)

func keep_pending() -> bool:
    var slot := free_slot()
    if pending_word == "" or slot < 0:
        return false
    slots[slot] = {"kind": "word", "id": pending_word}
    pending_word = ""
    save_game()
    return true

func release_pending() -> int:
    if pending_word == "":
        return 0
    var value := earn_exp(forget_value(pending_word))
    forgotten.append(pending_word)
    pending_word = ""
    save_game()
    return value

func swap_pending(slot: int) -> int:
    # No free slot: a held word leaves for EXP and the new word takes its place.
    if pending_word == "" or slot < 0 or slot >= slots.size() or slots[slot].is_empty() or slots[slot].kind != "word":
        return 0
    var value := earn_exp(forget_value(slots[slot].id))
    forgotten.append(slots[slot].id)
    slots[slot] = {"kind": "word", "id": pending_word}
    pending_word = ""
    save_game()
    return value

func forget_word(id: String) -> int:
    var slot := slot_of(id)
    if slot < 0 or slots[slot].kind != "word" or pending_word != "":
        return 0
    if current == "counseling" and counsel_step != "board":
        return 0
    var value := earn_exp(forget_value(id))
    forgotten.append(id)
    slots[slot] = {}
    save_game()
    return value

# --- Rounds and the map (days end without a night) --------------------------

func _end_day(kind: String) -> void:
    # No night, no nightly recovery: the next place follows at once.
    pending_word = ""
    if kind == "main":
        round_index += 1
        outings_done = 0
        var finished: Dictionary = data.rounds[round_index - 1]
        if finished.get("counseling", false) or round_index >= data.rounds.size():
            current = "counseling"
            _enter_counseling()
        else:
            current = "map"
    else:
        outings_done += 1
        if outings_done < int(data.rounds[round_index].outings):
            current = "map"
        else:
            for chapter in data.chapters:
                if chapter.id == current_round().chapter:
                    current = chapter.start
            apply(CHAPTER_EFFECTS)

func current_round() -> Dictionary:
    if round_index < data.rounds.size():
        return data.rounds[round_index]
    return data.rounds.back()

func stress_locked() -> bool:
    return effective(0) >= STRESS_LIMIT

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

# --- Counseling sessions ----------------------------------------------------

func _enter_counseling() -> void:
    session += 1
    counsel_step = "opening_doctor"
    talked = false
    focus = ""
    grow_word = ""

func is_closing() -> bool:
    return round_index >= data.rounds.size()

func on_board() -> bool:
    return current == "counseling" and counsel_step == "board"

func can_appraise(id: String) -> bool:
    # Talking about a mystery opens it: one per session, and it costs EXP.
    return on_board() and not talked and slot_of(id) >= 0 and trauma_state(id) == "mystery" and exp >= appraise_cost(id)

func appraise(id: String) -> bool:
    if not can_appraise(id):
        return false
    exp -= appraise_cost(id)
    traumas[id].state = "appraised"
    talked = true
    focus = id
    counsel_step = "talk_recall"
    save_game()
    return true

func can_face(id: String) -> bool:
    return on_board() and slot_of(id) >= 0 and trauma_state(id) == "appraised" and exp >= face_cost(id)

func face(id: String) -> bool:
    # Facing an opened trauma spends the outrageous EXP and frees its slot for good.
    if not can_face(id):
        return false
    exp -= face_cost(id)
    traumas[id].state = "accepted"
    slots[slot_of(id)] = {}
    focus = id
    counsel_step = "face_line"
    save_game()
    return true

func can_grow(id: String) -> bool:
    if not on_board() or not held_words().has(id) or level_of(id) >= MAX_LEVEL:
        return false
    return exp >= next_level_cost(id)

func grow(id: String) -> bool:
    # Talking about a held word digs into it for EXP; the word says what it meant.
    if not can_grow(id):
        return false
    exp -= next_level_cost(id)
    levels[id] = level_of(id) + 1
    grow_word = id
    counsel_step = "grow_question" if levels[id] == 2 else "grow_insight"
    save_game()
    return true

func interpret(index: int) -> Array:
    if current != "counseling" or counsel_step != "grow_choice" or grow_word == "" or index not in [0, 1, 2]:
        return []
    var effects: Dictionary = word_by_id(grow_word).interpretations[index].effects
    var delta := preview(effects)
    apply(effects)
    answers.append({"word": grow_word, "choice": index, "delta": delta, "stage": "counseling"})
    counsel_step = "grow_reply"
    save_game()
    return delta

func finish_session() -> bool:
    if not on_board():
        return false
    counsel_step = "closing"
    save_game()
    return true

func advance_counseling() -> bool:
    if current != "counseling":
        return false
    match counsel_step:
        "opening_doctor":
            counsel_step = "opening_yodaka"
        "opening_yodaka":
            counsel_step = "board"
        "talk_recall":
            counsel_step = "talk_doctor"
        "face_line":
            counsel_step = "face_response"
        "talk_doctor", "face_response", "grow_response":
            counsel_step = "board"
        "grow_question":
            counsel_step = "grow_choice"
        "grow_reply", "grow_insight":
            counsel_step = "grow_response"
        "closing":
            counsel_step = "farewell"
        "farewell":
            if is_closing():
                current = "result"
            else:
                current = "map"
            counsel_step = "opening_doctor"
        _:
            return false
    save_game()
    return true

# --- Saving -----------------------------------------------------------------

func save_game() -> bool:
    var file := FileAccess.open(save_path, FileAccess.WRITE)
    if file == null:
        last_error = "この環境では保存できません"
        return false
    file.store_string(JSON.stringify({"version": 6, "current": current,
        "collected": collected, "slots": slots, "forgotten": forgotten,
        "gains": gains, "answers": answers, "stats": stats,
        "history": history, "read_count": read_count, "speed": speed,
        "scene_key": scene_key, "pending_word": pending_word,
        "exp": exp, "exp_total": exp_total,
        "traumas": traumas, "levels": levels, "session": session,
        "counsel_step": counsel_step, "talked": talked, "focus": focus, "grow_word": grow_word,
        "round_index": round_index, "outings_done": outings_done, "visited": visited}))
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

func _valid_ids(value, lookup: Callable) -> bool:
    if not value is Array:
        return false
    for id in value:
        if not id is String or lookup.call(id).is_empty():
            return false
    return true

func load_game() -> bool:
    if not has_save():
        return false
    var parser := JSON.new()
    if parser.parse(FileAccess.get_file_as_string(save_path)) != OK:
        return false
    var saved = parser.data
    if not saved is Dictionary or saved.get("version", 0) != 6:
        return false
    var node_id = saved.get("current", "")
    if not node_id is String or (not node_id in ["map", "counseling", "result"] and not data.nodes.has(node_id)):
        return false
    if not saved.get("stats") is Array or saved.stats.size() != STAT_NAMES.size():
        return false
    for value in saved.stats:
        if not _is_int(value, 0, 100):
            return false
    if not _valid_ids(saved.get("collected"), word_by_id) or not _valid_ids(saved.get("forgotten"), word_by_id):
        return false
    if not saved.get("answers") is Array or not saved.get("history") is Array:
        return false
    if not saved.get("gains", {}) is Dictionary or not saved.get("visited", []) is Array:
        return false
    if not saved.get("slots") is Array or saved.slots.size() != SLOTS or not saved.get("traumas") is Dictionary or not saved.get("levels", {}) is Dictionary:
        return false
    var seen: Array = []
    for id in saved.collected:
        if seen.has(id):
            return false
        seen.append(id)
    var held: Array = []
    for slot in saved.slots:
        if not slot is Dictionary:
            return false
        if slot.is_empty():
            continue
        if slot.get("kind", "") not in ["trauma", "word"] or not slot.get("id", 0) is String or held.has(slot.id):
            return false
        if slot.kind == "word" and (not seen.has(slot.id) or saved.forgotten.has(slot.id)):
            return false
        if slot.kind == "trauma" and (trauma_def(slot.id).is_empty() or not saved.traumas.has(slot.id)):
            return false
        held.append(slot.id)
    for id in saved.forgotten:
        if not seen.has(id) or saved.forgotten.count(id) != 1:
            return false
    for id in saved.gains:
        if not seen.has(id) or not _valid_delta(saved.gains[id]):
            return false
    if saved.traumas.size() != data.traumas.size():
        return false
    for id in saved.traumas:
        var state = saved.traumas[id]
        if trauma_def(id).is_empty() or not state is Dictionary or state.get("state", "") not in TRAUMA_STATES:
            return false
        if held.has(id) == (state.state == "accepted"):
            return false
    for id in saved.levels:
        if not seen.has(id) or not _is_int(saved.levels[id], 1, MAX_LEVEL):
            return false
    for answer in saved.answers:
        if not answer is Dictionary or not seen.has(answer.get("word")):
            return false
        if not _is_int(answer.get("choice", -1), 0, 2) or not _valid_delta(answer.get("delta")):
            return false
        answer.choice = int(answer.choice)
        answer.delta = answer.delta.map(func(value): return int(value))
    for entry in saved.history:
        if not entry is Dictionary or not entry.get("text") is String or not entry.get("speaker") is String or not entry.get("id") is String:
            return false
    var step = saved.get("counsel_step", "opening_doctor")
    if step not in COUNSEL_STEPS or not _is_int(saved.get("session", 0), 0, SESSIONS):
        return false
    if node_id == "counseling" and int(saved.session) < 1:
        return false
    var focused = saved.get("focus", "")
    if not focused is String or (focused != "" and trauma_def(focused).is_empty()):
        return false
    if step in ["talk_recall", "talk_doctor"] and (focused == "" or saved.traumas[focused].state != "appraised"):
        return false
    if step in ["face_line", "face_response"] and (focused == "" or saved.traumas[focused].state != "accepted"):
        return false
    var growing = saved.get("grow_word", "")
    if not growing is String or (growing != "" and not held.has(growing)):
        return false
    if step in ["grow_question", "grow_choice", "grow_reply", "grow_response", "grow_insight"] and growing == "":
        return false
    if not saved.get("talked", false) is bool:
        return false
    if not _is_int(saved.get("exp", 0), 0, 99999999) or not _is_int(saved.get("exp_total", 0), 0, 99999999):
        return false
    if not _is_int(saved.get("round_index", 0), 0, data.rounds.size()) or not _is_int(saved.get("outings_done", 0), 0, 99):
        return false
    for id in saved.visited:
        if not id is String or event_by_id(id).is_empty():
            return false
    var pending = saved.get("pending_word", "")
    if not pending is String or (pending != "" and (not seen.has(pending) or held.has(pending) or saved.forgotten.has(pending))):
        return false
    if not saved.get("scene_key", "") is String:
        return false
    current = node_id
    collected = saved.collected
    slots = saved.slots
    forgotten = saved.forgotten
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
    exp = int(saved.get("exp", 0))
    exp_total = int(saved.get("exp_total", 0))
    traumas = {}
    for id in saved.traumas:
        traumas[id] = {"state": saved.traumas[id].state}
    levels = {}
    for id in saved.levels:
        levels[id] = int(saved.levels[id])
    session = int(saved.get("session", 0))
    counsel_step = step
    talked = saved.get("talked", false)
    focus = focused
    grow_word = growing
    round_index = int(saved.get("round_index", 0))
    outings_done = int(saved.get("outings_done", 0))
    visited = saved.visited
    last_delta = []
    return true
