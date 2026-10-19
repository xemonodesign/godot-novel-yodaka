class_name StoryState
extends RefCounted

const STAT_NAMES = ["ストレス", "勇気", "自認", "キラキラ"]
const INITIAL = [60, 5, 5, 5]
const STRESS_LIMIT = 80
const SLEEP_EFFECTS = {"ストレス": -4}
const OUTING_EFFECTS = {"ストレス": 5}
const CHAPTER_EFFECTS = {"ストレス": 6}
const SAVE_PATH = "user://yodaka_v1.json"
const SLOTS = 8  # the word shelf; every slot starts filled by a trauma
const EXP_PER_TAP = 1  # every line read for the first time earns this, times held multipliers
const FIRST_FACE_COST = 30  # the first trauma ever loosened costs only this much to face
const TALK_WEAKEN = 20  # talking about a trauma in counseling weakens it by this much on its own
const RESONANCE = 2  # a word whose tag matches the trauma counts this many times
const DEEPER_AT = 30  # weakened this far, a trauma with something behind it lets it out
const MAX_CARDS = 2  # words brought into one conversation
const MAX_LEVEL = 3
const SESSIONS = 4  # opening, two in between, closing
const COUNSEL_STEPS = ["opening_doctor", "opening_yodaka", "board", "talk_recall", "talk_doctor",
    "talk_effect", "talk_emerge", "face_line", "grow_question", "grow_choice", "grow_reply",
    "grow_response", "grow_insight", "closing", "farewell"]
var save_path: String = SAVE_PATH
var data: Dictionary = {}
var current: String = ""
var collected: Array = []  # every word received, in order
var slots: Array = []  # SLOTS entries: {} or {"kind": "trauma" | "word", "id": ...}
var forgotten: Array = []  # words let go or forgotten for EXP
var used: Array = []  # words spent in counseling to loosen a trauma
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
var exp_day: int = 0
var traumas: Dictionary = {}  # id -> {strength, cost, unraveled, resolved}
var levels: Dictionary = {}  # word id -> level, 1 when absent
var session: int = 0
var counsel_step: String = "opening_doctor"
var talked: bool = false
var focus: String = ""
var cards: Array = []
var grow_word: String = ""
var talk_result: Dictionary = {}
var round_index: int = 0
var outings_done: int = 0
var visited: Array = []
var after_night: String = "map"

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
        if trauma.get("hidden", false):
            continue
        slots.append({"kind": "trauma", "id": trauma.id})
        traumas[trauma.id] = {"strength": int(trauma.strength), "cost": int(trauma.cost),
            "unraveled": false, "resolved": false}
    while slots.size() < SLOTS:
        slots.append({})
    forgotten.clear()
    used.clear()
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
    exp_day = 0
    levels.clear()
    session = 0
    counsel_step = "opening_doctor"
    talked = false
    focus = ""
    cards = []
    grow_word = ""
    talk_result = {}
    round_index = 0
    outings_done = 0
    visited.clear()
    after_night = "map"

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

func exp_per_tap() -> int:
    return EXP_PER_TAP * exp_multiplier()

func earn_exp(amount: int) -> int:
    exp += amount
    exp_total += amount
    exp_day += amount
    return amount

# --- Traumas: debuffs that fade as a trauma weakens ------------------------

func intensity(id: String) -> float:
    var def := trauma_def(id)
    if def.is_empty() or not traumas.has(id) or traumas[id].resolved:
        return 0.0
    return clampf(float(traumas[id].strength) / float(def.strength), 0.0, 1.0)

func debuff_level(kind: String, stat: String = "") -> float:
    var level := 0.0
    for id in held_traumas():
        var debuff: Dictionary = trauma_def(id).debuff
        if debuff.kind == kind and (stat == "" or debuff.get("stat", "") == stat):
            level = maxf(level, intensity(id))
    return level

func debuff_active(kind: String) -> bool:
    # Flag-like debuffs switch off once their trauma is weakened below half.
    return debuff_level(kind) > 0.5

func trauma_cap(stat: String) -> int:
    var cap := 100
    for id in held_traumas():
        var debuff: Dictionary = trauma_def(id).debuff
        if debuff.kind == "cap" and debuff.stat == stat:
            cap = mini(cap, int(round(float(debuff.value) + (100.0 - float(debuff.value)) * (1.0 - intensity(id)))))
    return cap

func effective_stats() -> Array:
    var result: Array = []
    for i in range(STAT_NAMES.size()):
        var stat: String = STAT_NAMES[i]
        var value: int = int(stats[i]) + hold_stat(stat)
        for id in held_traumas():
            var debuff: Dictionary = trauma_def(id).debuff
            if debuff.kind == "plus" and debuff.stat == stat:
                value += int(ceil(float(debuff.value) * intensity(id)))
        value -= int(floor(float(value) * 0.5 * debuff_level("half", stat)))
        value = mini(value, trauma_cap(stat))
        result.append(clampi(value, 0, 100))
    return result

func effective(index: int) -> int:
    return effective_stats()[index]

func debuff_text(id: String) -> String:
    var debuff: Dictionary = trauma_def(id).debuff
    var level := intensity(id)
    match debuff.kind:
        "half":
            return "%s が %d%% 減る" % [debuff.stat, int(round(50.0 * level))]
        "cap":
            return "%s の上限 %d" % [debuff.stat, trauma_cap(debuff.stat) if traumas.has(id) else int(debuff.value)]
        "plus":
            return "%s 常時 +%d" % [debuff.stat, int(ceil(float(debuff.value) * level))]
        "rest_half":
            return "家で休んでも回復が半分" + ("" if level > 0.5 else "（弱まって効果なし）")
        "forget_half":
            return "手放した言葉のEXPが半分" + ("" if level > 0.5 else "（弱まって効果なし）")
        "gain_half":
            return "もらった言葉の変化が半分" + ("" if level > 0.5 else "（弱まって効果なし）")
        "sleep_half":
            return "眠っても回復が半分" + ("" if level > 0.5 else "（弱まって効果なし）")
    return ""

func faced_count() -> int:
    # Traumas Yodaka faced and was rid of; one that let something deeper out does not count.
    var count := 0
    for id in traumas:
        var def := trauma_def(id)
        if traumas[id].resolved and not (def.has("deeper") and traumas.has(def.deeper)):
            count += 1
    return count

func face_cost(id: String) -> int:
    var def := trauma_def(id)
    if def.is_empty() or not traumas.has(id):
        return 0
    var state: Dictionary = traumas[id]
    if int(state.strength) <= 0:
        return 0
    return maxi(1, int(ceil(float(state.cost) * float(state.strength) / float(def.strength))))

func can_face(id: String) -> bool:
    if pending_word != "" or slot_of(id) < 0 or not traumas.has(id):
        return false
    if current == "counseling" and counsel_step != "board":
        return false
    var state: Dictionary = traumas[id]
    return state.unraveled and not state.resolved and exp >= face_cost(id)

func face(id: String) -> bool:
    # Facing a loosened trauma spends EXP and frees its slot for good.
    if not can_face(id):
        return false
    exp -= face_cost(id)
    traumas[id].resolved = true
    traumas[id].strength = 0
    slots[slot_of(id)] = {}
    focus = id
    if current == "counseling":
        counsel_step = "face_line"
    save_game()
    return true

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
        _enter_night(node.get("kind", ""))
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
    cards.erase(id)
    save_game()
    return value

# --- Rounds, nights, map ----------------------------------------------------

func _enter_night(kind: String) -> void:
    pending_word = ""  # any collection choice was made before the day ended
    if kind == "main":
        round_index += 1
        outings_done = 0
        var finished: Dictionary = data.rounds[round_index - 1]
        after_night = "counseling" if finished.get("counseling", false) or round_index >= data.rounds.size() else "map"
    else:
        outings_done += 1
        after_night = "map" if outings_done < int(data.rounds[round_index].outings) else "chapter"

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

func sleep_effects() -> Dictionary:
    return halved(SLEEP_EFFECTS) if debuff_active("sleep_half") else SLEEP_EFFECTS

func sleep() -> Array:
    if current != "night":
        return []
    var delta := apply(sleep_effects())
    exp_day = 0
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
            _enter_counseling()
        _:
            current = "map"
    save_game()
    return delta

# --- Counseling sessions ----------------------------------------------------

func _enter_counseling() -> void:
    session += 1
    counsel_step = "opening_doctor"
    talked = false
    focus = ""
    cards = []
    grow_word = ""
    talk_result = {}

func is_closing() -> bool:
    return round_index >= data.rounds.size()

func on_board() -> bool:
    return current == "counseling" and counsel_step == "board"

func can_talk(id: String) -> bool:
    if not on_board() or talked or slot_of(id) < 0 or not traumas.has(id) or traumas[id].resolved:
        return false
    # The first session keeps to traumas with nothing waiting behind them.
    return session > 1 or not trauma_def(id).has("deeper")

func focus_trauma(id: String) -> bool:
    if not on_board() or slot_of(id) < 0 or not traumas.has(id):
        return false
    if focus != id:
        cards = []
    focus = id
    return true

func toggle_card(id: String) -> bool:
    if not on_board() or not held_words().has(id):
        return false
    if cards.has(id):
        cards.erase(id)
    elif cards.size() < MAX_CARDS:
        cards.append(id)
    else:
        return false
    return true

func resonates(word_id: String, trauma_id: String) -> bool:
    return word_by_id(word_id).get("tag", "") == trauma_def(trauma_id).get("tag", "-")

func talk_preview(id: String, chosen: Array) -> Dictionary:
    var def := trauma_def(id)
    if def.is_empty() or not traumas.has(id):
        return {}
    var state: Dictionary = traumas[id]
    var first: bool = not traumas.values().any(func(t): return t.unraveled)
    var cost: float = float(FIRST_FACE_COST if first and not state.unraveled else state.cost)
    var strength: int = int(state.strength) - TALK_WEAKEN
    var resonant: Array = []
    for word_id in chosen:
        var release: Dictionary = level_data(word_id).release
        var times: int = RESONANCE if resonates(word_id, id) else 1
        if resonates(word_id, id):
            resonant.append(word_id)
        strength -= int(release.get("weaken", 0)) * times
        for _i in range(times):
            cost *= float(release.get("cost_mult", 1.0))
    strength = maxi(strength, 0)
    var cost_after: int = maxi(1, int(ceil(cost)))
    var face: int = 0 if strength == 0 else maxi(1, int(ceil(float(cost_after) * float(strength) / float(def.strength))))
    var emerges: bool = def.has("deeper") and strength <= DEEPER_AT and not traumas.has(def.deeper)
    return {"strength": strength, "cost": cost_after, "face": face, "resonant": resonant, "emerges": emerges, "first": first and not state.unraveled}

func talk() -> bool:
    # Yodaka talks about the focused trauma, bringing the chosen words into it.
    if focus == "" or not can_talk(focus):
        return false
    var def := trauma_def(focus)
    var state: Dictionary = traumas[focus]
    var preview := talk_preview(focus, cards)
    talk_result = {"id": focus, "before": int(state.strength), "after": int(preview.strength),
        "cost_before": face_cost(focus), "cost_after": int(preview.face), "cards": cards.duplicate(),
        "resonant": preview.resonant, "emerged": "", "first": preview.first}
    for word_id in cards:
        slots[slot_of(word_id)] = {}
        used.append(word_id)
    cards = []
    state.strength = int(preview.strength)
    state.cost = int(preview.cost)
    state.unraveled = true
    talked = true
    if preview.emerges:
        var deeper: Dictionary = trauma_def(def.deeper)
        state.resolved = true  # what it hid takes its place; the slot stays taken
        state.strength = 0
        slots[slot_of(focus)] = {"kind": "trauma", "id": deeper.id}
        traumas[deeper.id] = {"strength": int(deeper.strength), "cost": int(deeper.cost),
            "unraveled": true, "resolved": false}
        talk_result.emerged = deeper.id
    counsel_step = "talk_recall"
    save_game()
    return true

func can_grow(id: String) -> bool:
    if not on_board() or not held_words().has(id) or level_of(id) >= MAX_LEVEL:
        return false
    return exp >= next_level_cost(id)

func grow(id: String) -> bool:
    # Digging into a held word costs EXP; the word says what it meant.
    if not can_grow(id):
        return false
    exp -= next_level_cost(id)
    levels[id] = level_of(id) + 1
    grow_word = id
    cards.erase(id)
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
        "talk_doctor":
            counsel_step = "talk_effect"
        "talk_effect":
            counsel_step = "talk_emerge" if talk_result.get("emerged", "") != "" else "board"
        "talk_emerge", "face_line", "grow_response":
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
    file.store_string(JSON.stringify({"version": 5, "current": current,
        "collected": collected, "slots": slots, "forgotten": forgotten, "used": used,
        "gains": gains, "answers": answers, "stats": stats,
        "history": history, "read_count": read_count, "speed": speed,
        "scene_key": scene_key, "pending_word": pending_word,
        "exp": exp, "exp_total": exp_total, "exp_day": exp_day,
        "traumas": traumas, "levels": levels, "session": session,
        "counsel_step": counsel_step, "talked": talked, "focus": focus, "cards": cards,
        "grow_word": grow_word, "talk_result": talk_result,
        "round_index": round_index, "outings_done": outings_done, "visited": visited,
        "after_night": after_night}))
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
    if not saved is Dictionary or saved.get("version", 0) != 5:
        return false
    var node_id = saved.get("current", "")
    if not node_id is String or (not node_id in ["map", "night", "counseling", "result"] and not data.nodes.has(node_id)):
        return false
    if not saved.get("stats") is Array or saved.stats.size() != STAT_NAMES.size():
        return false
    for value in saved.stats:
        if not _is_int(value, 0, 100):
            return false
    if not _valid_ids(saved.get("collected"), word_by_id) or not _valid_ids(saved.get("forgotten"), word_by_id) or not _valid_ids(saved.get("used"), word_by_id):
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
        if slot.kind == "word" and (not seen.has(slot.id) or saved.forgotten.has(slot.id) or saved.used.has(slot.id)):
            return false
        if slot.kind == "trauma" and (trauma_def(slot.id).is_empty() or not saved.traumas.has(slot.id)):
            return false
        held.append(slot.id)
    for id in saved.forgotten + saved.used:
        if not seen.has(id) or saved.forgotten.count(id) + saved.used.count(id) != 1:
            return false
    for id in saved.gains:
        if not seen.has(id) or not _valid_delta(saved.gains[id]):
            return false
    for id in saved.traumas:
        var def := trauma_def(id)
        var state = saved.traumas[id]
        if def.is_empty() or not state is Dictionary or not _is_int(state.get("strength", -1), 0, int(def.strength)):
            return false
        if not _is_int(state.get("cost", 0), 1, int(def.cost)) or not state.get("unraveled", 0) is bool or not state.get("resolved", 0) is bool:
            return false
        if held.has(id) == state.resolved:
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
    if step in ["talk_recall", "talk_doctor", "talk_effect", "talk_emerge", "face_line"] and focused == "":
        return false
    var growing = saved.get("grow_word", "")
    if not growing is String or (growing != "" and not held.has(growing)):
        return false
    if step in ["grow_question", "grow_choice", "grow_reply", "grow_response", "grow_insight"] and growing == "":
        return false
    if not saved.get("cards", []) is Array or not saved.get("talk_result", {}) is Dictionary or not saved.get("talked", false) is bool:
        return false
    for id in saved.cards:
        if not held.has(id) or word_by_id(id).is_empty():
            return false
    if not _is_int(saved.get("exp", 0), 0, 99999999) or not _is_int(saved.get("exp_total", 0), 0, 99999999) or not _is_int(saved.get("exp_day", 0), 0, 99999999):
        return false
    if not _is_int(saved.get("round_index", 0), 0, data.rounds.size()) or not _is_int(saved.get("outings_done", 0), 0, 99):
        return false
    for id in saved.visited:
        if not id is String or event_by_id(id).is_empty():
            return false
    if saved.get("after_night", "map") not in ["map", "chapter", "counseling"]:
        return false
    var pending = saved.get("pending_word", "")
    if not pending is String or (pending != "" and (not seen.has(pending) or held.has(pending) or saved.forgotten.has(pending) or saved.used.has(pending))):
        return false
    if not saved.get("scene_key", "") is String:
        return false
    current = node_id
    collected = saved.collected
    slots = saved.slots
    forgotten = saved.forgotten
    used = saved.used
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
    exp_day = int(saved.get("exp_day", 0))
    traumas = {}
    for id in saved.traumas:
        traumas[id] = {"strength": int(saved.traumas[id].strength), "cost": int(saved.traumas[id].cost),
            "unraveled": saved.traumas[id].unraveled, "resolved": saved.traumas[id].resolved}
    levels = {}
    for id in saved.levels:
        levels[id] = int(saved.levels[id])
    session = int(saved.get("session", 0))
    counsel_step = step
    talked = saved.get("talked", false)
    focus = focused
    cards = saved.get("cards", [])
    grow_word = growing
    talk_result = saved.get("talk_result", {})
    round_index = int(saved.get("round_index", 0))
    outings_done = int(saved.get("outings_done", 0))
    visited = saved.visited
    after_night = saved.get("after_night", "map")
    last_delta = []
    return true
