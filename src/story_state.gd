class_name StoryState
extends RefCounted

const STAT_NAMES = ["ストレス", "勇気", "自認", "キラキラ"]
const INITIAL = [20, 35, 35, 35]
const STRESS_LIMIT = 80
const SLEEP_EFFECTS = {"ストレス": -4}
const OUTING_EFFECTS = {"ストレス": 5}
const CHAPTER_EFFECTS = {"ストレス": 6}
const SAVE_PATH = "user://yodaka_v1.json"
const SAVE_VERSION = 5
const COUNSEL_STEPS = ["opening_doctor", "opening_yodaka", "session", "talk", "closing", "farewell"]
const PENDING_STEPS = ["", "offer", "forget", "kept", "released"]
var save_path: String = SAVE_PATH
var data: Dictionary = {}
var current: String = ""
var collected: Array = []
var gains: Dictionary = {}
var stats: Array = INITIAL.duplicate()
var history: Array = []
var read_count: int = 0
var speed: float = 32.0
var last_error: String = ""
var last_delta: Array = []
var last_exp: int = 0
var scene_key: String = ""
var pending_word: String = ""
var pending_step: String = ""
var pending_gain: int = 0
var pending_slot: int = -1
var counsel_step: String = "opening_doctor"
var counsel_session: int = 0
var counsel_trauma: String = ""
var talk_index: int = 0
var talked: bool = false
var session_lines: Array = []
var round_index: int = 0
var outings_done: int = 0
var visited: Array = []
var slots: Array = []
var trauma_state: Dictionary = {}
var levels: Dictionary = {}
var exp: int = 0
var exp_total: int = 0
var released: Array = []
var resolved: Array = []
var surfaced: Array = []

func _init() -> void:
    data = JSON.parse_string(FileAccess.get_file_as_string("res://src/data/scenario.json"))
    reset()

func reset() -> void:
    current = data.start
    collected.clear()
    gains.clear()
    stats = INITIAL.duplicate()
    history.clear()
    read_count = 0
    last_delta = []
    last_exp = 0
    scene_key = ""
    pending_word = ""
    pending_step = ""
    pending_gain = 0
    pending_slot = -1
    counsel_step = "opening_doctor"
    counsel_session = 0
    counsel_trauma = ""
    talk_index = 0
    talked = false
    session_lines = []
    round_index = 0
    outings_done = 0
    visited.clear()
    slots = []
    trauma_state = {}
    # Every slot starts occupied by a trauma; words need a freed slot.
    for trauma in data.traumas:
        if not trauma.get("deep", false):
            slots.append("t:" + trauma.id)
            trauma_state[trauma.id] = {"hardness": 100, "cost": int(trauma.base_cost), "loosened": false}
    while slots.size() < int(data.rules.slot_count):
        slots.append("")
    levels = {}
    exp = 0
    exp_total = 0
    released = []
    resolved = []
    surfaced = []

# --- lookups ---------------------------------------------------------------

func word_by_id(id: String) -> Dictionary:
    for word in data.words:
        if word.id == id:
            return word
    return {}

func trauma_by_id(id: String) -> Dictionary:
    for trauma in data.traumas:
        if trauma.id == id:
            return trauma
    return {}

func event_by_id(id: String) -> Dictionary:
    for event in data.map_events:
        if event.id == id:
            return event
    return {}

func active_traumas() -> Array:
    var ids: Array = []
    for entry in slots:
        if entry.begins_with("t:"):
            ids.append(entry.trim_prefix("t:"))
    return ids

func kept_words() -> Array:
    var ids: Array = []
    for entry in slots:
        if entry.begins_with("w:"):
            ids.append(entry.trim_prefix("w:"))
    return ids

func is_kept(id: String) -> bool:
    return slots.has("w:" + id)

func free_slot() -> int:
    return slots.find("")

func word_level(id: String) -> int:
    return int(levels.get(id, 1))

func level_data(id: String, level: int = 0) -> Dictionary:
    var word := word_by_id(id)
    if word.is_empty():
        return {}
    var index: int = (word_level(id) if level <= 0 else level) - 1
    return word.levels[clampi(index, 0, word.levels.size() - 1)]

func hardness(id: String) -> int:
    return int(trauma_state.get(id, {}).get("hardness", 0))

func is_loosened(id: String) -> bool:
    return bool(trauma_state.get(id, {}).get("loosened", false))

func trauma_cost(id: String) -> int:
    return int(trauma_state.get(id, {}).get("cost", 0))

# --- effective parameters ---------------------------------------------------

func scaled_debuffs(id: String) -> Array:
    # Debuffs weaken in proportion to the trauma's remaining hardness.
    var scale: float = hardness(id) / 100.0
    var result: Array = []
    for debuff in trauma_by_id(id).get("debuffs", []):
        var entry: Dictionary = debuff.duplicate()
        match debuff.kind:
            "offset":
                entry.value = roundi(float(debuff.value) * scale)
            "cap":
                entry.value = roundi(float(debuff.value) + (100.0 - float(debuff.value)) * (1.0 - scale))
            _:
                entry.value = 1.0 - (1.0 - float(debuff.value)) * scale
        result.append(entry)
    return result

func passives() -> Array:
    var result: Array = []
    for id in kept_words():
        for passive in level_data(id).get("passive", []):
            result.append(passive)
    return result

func stat_offset(i: int) -> int:
    var total := 0
    for id in active_traumas():
        for debuff in scaled_debuffs(id):
            if debuff.kind == "offset" and debuff.stat == STAT_NAMES[i]:
                total += int(debuff.value)
    for passive in passives():
        if passive.kind == "stat" and passive.stat == STAT_NAMES[i]:
            total += int(passive.value)
    return total

func stat_cap(i: int) -> int:
    var cap := 100
    for id in active_traumas():
        for debuff in scaled_debuffs(id):
            if debuff.kind == "cap" and debuff.stat == STAT_NAMES[i]:
                cap = mini(cap, int(debuff.value))
    return cap

func _multiplier(kind: String, stat: String = "") -> float:
    var product := 1.0
    for id in active_traumas():
        for debuff in scaled_debuffs(id):
            if debuff.kind == kind and debuff.get("stat", "") == stat:
                product *= float(debuff.value)
    for passive in passives():
        if passive.kind == kind and passive.get("stat", "") == stat:
            product *= float(passive.value)
    return product

func gain_multiplier(i: int) -> float:
    return _multiplier("gain", STAT_NAMES[i])

func recovery_multiplier() -> float:
    return _multiplier("recovery")

func exp_multiplier() -> float:
    return _multiplier("exp")

func release_multiplier() -> float:
    return _multiplier("release")

func effective(i: int) -> int:
    return clampi(int(stats[i]) + stat_offset(i), 0, stat_cap(i))

func effective_stats() -> Array:
    var result: Array = []
    for i in range(STAT_NAMES.size()):
        result.append(effective(i))
    return result

func exp_per_tap() -> int:
    return maxi(1, roundi(float(data.rules.exp_per_tap) * exp_multiplier()))

func release_value(id: String) -> int:
    var word := word_by_id(id)
    if word.is_empty():
        return 0
    return maxi(1, roundi(float(word.value) * word_level(id) * release_multiplier()))

func preview(effects: Dictionary) -> Array:
    var delta: Array = []
    for i in range(STAT_NAMES.size()):
        delta.append(0)
    for stat in effects:
        var i: int = STAT_NAMES.find(stat)
        if i < 0:
            continue
        var raw: int = int(effects[stat])
        if i > 0 and raw > 0:
            raw = maxi(1, roundi(raw * gain_multiplier(i)))
        elif i == 0 and raw < 0:
            raw = mini(-1, roundi(raw * recovery_multiplier()))
        delta[i] = clampi(int(stats[i]) + raw, 0, 100) - int(stats[i])
    return delta

func apply(effects: Dictionary) -> Array:
    var delta := preview(effects)
    for i in range(STAT_NAMES.size()):
        stats[i] = int(stats[i]) + delta[i]
    last_delta = delta
    return delta

func has_change(delta: Array) -> bool:
    return delta.any(func(value): return value != 0)

func gain_exp(amount: int) -> void:
    exp += amount
    exp_total += amount

# --- reading ----------------------------------------------------------------

func finish_line() -> bool:
    if not data.nodes.has(current):
        return false
    var node: Dictionary = data.nodes[current]
    var added := false
    last_delta = []
    last_exp = 0
    if node.has("word") and not collected.has(node.word):
        collected.append(node.word)
        gains[node.word] = apply(word_by_id(node.word).get("effects", {}))
        pending_word = node.word
        pending_step = "offer"
        added = true
    if history.is_empty() or history.back().id != current:
        history.append({"id": current, "speaker": node.speaker, "text": node.text})
        read_count += 1
        last_exp = exp_per_tap()  # every tap of conversation builds strength
        gain_exp(last_exp)
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
    return requirement.is_empty() or effective(STAT_NAMES.find(requirement.stat)) >= requirement.min

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
    if current == "sleep":
        _end_day(node.get("kind", ""))
    elif current == "counseling":
        _start_counseling(0)
    save_game()
    return true

func _end_day(kind: String) -> void:
    # The day ends in sleep; the next morning is the map, a chapter or counseling.
    var delta := apply(SLEEP_EFFECTS)
    if kind == "main":
        var finished: Dictionary = current_round()
        round_index += 1
        outings_done = 0
        if finished.get("counseling", false):
            var session := 1
            for i in range(round_index - 1):
                if data.rounds[i].get("counseling", false):
                    session += 1
            _start_counseling(session)
        else:
            current = "map"
    else:
        outings_done += 1
        if outings_done < int(current_round().outings):
            current = "map"
        else:
            for chapter in data.chapters:
                if chapter.id == current_round().chapter:
                    current = chapter.start
            var cost := apply(CHAPTER_EFFECTS)
            for i in range(STAT_NAMES.size()):
                delta[i] += cost[i]
    last_delta = delta

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

# --- receiving a word -------------------------------------------------------

func can_keep() -> bool:
    return pending_step == "offer" and free_slot() >= 0

func keep_pending() -> bool:
    if not can_keep():
        return false
    pending_slot = free_slot()
    slots[pending_slot] = "w:" + pending_word
    levels[pending_word] = 1
    pending_gain = 0
    pending_step = "kept"
    save_game()
    return true

func request_forget() -> bool:
    if pending_step != "offer" or free_slot() >= 0 or kept_words().is_empty():
        return false
    pending_step = "forget"
    save_game()
    return true

func cancel_forget() -> bool:
    if pending_step != "forget":
        return false
    pending_step = "offer"
    save_game()
    return true

func _forget(id: String) -> int:
    var index: int = slots.find("w:" + id)
    if index < 0:
        return 0
    var gain := release_value(id)
    slots[index] = ""
    levels.erase(id)
    released.append(id)
    gain_exp(gain)
    return gain

func forget_for_pending(id: String) -> int:
    # Forgetting a kept word turns it into EXP and makes room for the new one.
    if pending_step != "forget" or not is_kept(id):
        return 0
    var gain := _forget(id)
    pending_slot = slots.find("")
    slots[pending_slot] = "w:" + pending_word
    levels[pending_word] = 1
    pending_gain = gain
    pending_step = "kept"
    save_game()
    return gain

func release_pending() -> int:
    if pending_step != "offer":
        return 0
    pending_gain = release_value(pending_word)
    released.append(pending_word)
    gain_exp(pending_gain)
    pending_slot = -1
    pending_step = "released"
    save_game()
    return pending_gain

func acknowledge_word() -> bool:
    if pending_step not in ["kept", "released"]:
        return false
    pending_word = ""
    pending_step = ""
    pending_gain = 0
    pending_slot = -1
    save_game()
    return true

# --- counseling -------------------------------------------------------------

func _start_counseling(session: int) -> void:
    current = "counseling"
    counsel_step = "opening_doctor"
    counsel_session = session
    counsel_trauma = ""
    talk_index = 0
    talked = false
    session_lines = []

func final_session() -> bool:
    return round_index >= data.rounds.size()

func in_session() -> bool:
    return current == "counseling" and counsel_step == "session" and pending_word == ""

func can_talk(id: String) -> bool:
    return in_session() and not talked and active_traumas().has(id)

func start_talk(id: String) -> bool:
    if not can_talk(id):
        return false
    counsel_trauma = id
    talk_index = 0
    counsel_step = "talk"
    save_game()
    return true

func talk_line() -> Dictionary:
    var trauma := trauma_by_id(counsel_trauma)
    if trauma.is_empty() or counsel_step != "talk" or talk_index >= trauma.talk.size():
        return {}
    return {"speaker": trauma.talk[talk_index][0], "text": trauma.talk[talk_index][1]}

func _finish_talk() -> void:
    # Talking loosens the trauma: the first one ever becomes cheap, the rest
    # drop from their outrageous cost to something words and EXP can reach.
    var first := true
    for id in trauma_state:
        if trauma_state[id].loosened:
            first = false
    var state: Dictionary = trauma_state[counsel_trauma]
    state.loosened = true
    state.cost = int(data.rules.first_cost) if first else maxi(1, int(trauma_by_id(counsel_trauma).base_cost) / int(data.rules.talk_divisor))
    talked = true
    session_lines = [["みなと", "……話してくれて、ありがとうございます。\n少しだけ、ほどけた気がしませんか。"],
        ["よだか", "はい。……向き合うのに必要な力が、%s になりました。" % _format_exp(state.cost)]]
    counsel_step = "session"
    counsel_trauma = ""
    talk_index = 0

static func _format_exp(amount: int) -> String:
    var text := str(amount)
    var result := ""
    while text.length() > 3:
        result = "," + text.right(3) + result
        text = text.left(text.length() - 3)
    return text + result + " EXP"

func valid_cards(cards: Array) -> bool:
    if cards.size() > int(data.rules.max_cards):
        return false
    var seen: Array = []
    for id in cards:
        if not id is String or not is_kept(id) or seen.has(id):
            return false
        seen.append(id)
    return true

func confront_preview(id: String, cards: Array) -> Dictionary:
    if not active_traumas().has(id) or not is_loosened(id) or not valid_cards(cards):
        return {}
    var multiplier := 1.0
    var soften: int = int(data.rules.soften_base)
    var calm := false
    for card in cards:
        for effect in level_data(card).get("counsel", []):
            match effect.kind:
                "cost":
                    multiplier *= float(effect.value)
                "soften":
                    soften += int(effect.value)
                "calm":
                    calm = true
    var cost: int = maxi(1, ceili(trauma_cost(id) * multiplier))
    var before := hardness(id)
    var after: int = maxi(0, before - soften)
    var deeper: String = trauma_by_id(id).get("deeper", "")
    var surfaces: bool = deeper != "" and not calm and before >= int(data.rules.surface_threshold) and after < int(data.rules.surface_threshold)
    return {"cost": cost, "soften": soften, "before": before, "after": after, "surfaces": surfaces,
        "calm": calm, "affordable": exp >= cost, "resolves": after <= 0 and not surfaces}

func confront(id: String, cards: Array) -> Dictionary:
    if not in_session():
        return {}
    var plan := confront_preview(id, cards)
    if plan.is_empty() or not plan.affordable:
        return {}
    exp -= int(plan.cost)
    var trauma := trauma_by_id(id)
    var index: int = slots.find("t:" + id)
    var result := {"id": id, "cost": plan.cost, "before": plan.before, "after": plan.after,
        "resolved": false, "surfaced": "", "cards": cards.duplicate()}
    if plan.surfaces:
        # The wound goes deeper than it looked: a heavier trauma takes the slot.
        var deeper: Dictionary = trauma_by_id(trauma.deeper)
        slots[index] = "t:" + deeper.id
        trauma_state[id].hardness = 0
        trauma_state[deeper.id] = {"hardness": 100, "cost": int(deeper.base_cost), "loosened": false}
        surfaced.append(deeper.id)
        result.surfaced = deeper.id
        session_lines = [["みなと", deeper.surface[0]], ["よだか", deeper.surface[1]]]
    elif plan.after <= 0:
        trauma_state[id].hardness = 0
        slots[index] = ""
        resolved.append(id)
        result.resolved = true
        session_lines = [["みなと", trauma.soften.resolved[0]], ["よだか", trauma.soften.resolved[1]]]
    else:
        trauma_state[id].hardness = plan.after
        var stage: String = "first" if plan.before >= 100 else "mid"
        session_lines = [["みなと", trauma.soften[stage][0]], ["よだか", trauma.soften[stage][1]]]
    save_game()
    return result

func grow_cost(id: String) -> int:
    var word := word_by_id(id)
    if word.is_empty() or not is_kept(id) or word_level(id) >= word.levels.size():
        return -1
    return int(word.levels[word_level(id)].cost)

func can_grow(id: String) -> bool:
    var cost := grow_cost(id)
    return in_session() and cost >= 0 and exp >= cost

func grow(id: String) -> Dictionary:
    if not can_grow(id):
        return {}
    exp -= grow_cost(id)
    levels[id] = word_level(id) + 1
    var insight: String = level_data(id).insight
    session_lines = [["よだか", insight], ["みなと", "……そう受け取ったんですね。\nその言葉は、法月さんのものになったと思います。"]]
    save_game()
    return {"id": id, "level": word_level(id), "insight": insight}

func forget_in_session(id: String) -> int:
    if not in_session() or not is_kept(id):
        return 0
    var gain := _forget(id)
    session_lines = [["みなと", "手放すのも、整理のひとつです。"],
        ["よだか", "「%s」を、忘れることにしました。……%s になりました。" % [word_by_id(id).word, _format_exp(gain)]]]
    save_game()
    return gain

func end_session() -> bool:
    if not in_session():
        return false
    counsel_step = "closing"
    session_lines = []
    save_game()
    return true

func advance_counseling() -> bool:
    if current != "counseling":
        return false
    match counsel_step:
        "opening_doctor":
            counsel_step = "opening_yodaka"
        "opening_yodaka":
            counsel_step = "session"
        "talk":
            talk_index += 1
            if talk_index >= trauma_by_id(counsel_trauma).talk.size():
                _finish_talk()
        "closing":
            counsel_step = "farewell"
        "farewell":
            current = "result" if final_session() else "map"
            counsel_step = "opening_doctor"
            talked = false
            session_lines = []
        _:
            return false
    save_game()
    return true

# --- persistence ------------------------------------------------------------

func save_game() -> bool:
    var file := FileAccess.open(save_path, FileAccess.WRITE)
    if file == null:
        last_error = "この環境では保存できません"
        return false
    file.store_string(JSON.stringify({"version": SAVE_VERSION, "current": current,
        "collected": collected, "gains": gains, "stats": stats,
        "history": history, "read_count": read_count, "speed": speed,
        "scene_key": scene_key, "pending_word": pending_word, "pending_step": pending_step,
        "pending_gain": pending_gain, "pending_slot": pending_slot,
        "counsel_step": counsel_step, "counsel_session": counsel_session,
        "counsel_trauma": counsel_trauma, "talk_index": talk_index, "talked": talked,
        "session_lines": session_lines,
        "round_index": round_index, "outings_done": outings_done, "visited": visited,
        "slots": slots, "trauma_state": trauma_state, "levels": levels,
        "exp": exp, "exp_total": exp_total, "released": released, "resolved": resolved,
        "surfaced": surfaced}))
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
    var seen: Array = []
    for id in value:
        if not id is String or lookup.call(id).is_empty() or seen.has(id):
            return false
        seen.append(id)
    return true

func load_game() -> bool:
    if not has_save():
        return false
    var parser := JSON.new()
    if parser.parse(FileAccess.get_file_as_string(save_path)) != OK:
        return false
    var saved = parser.data
    if not saved is Dictionary or saved.get("version", 0) != SAVE_VERSION:
        return false
    var node_id = saved.get("current", "")
    if not node_id is String or (not node_id in ["map", "counseling", "result"] and not data.nodes.has(node_id)):
        return false
    if not saved.get("stats") is Array or saved.stats.size() != STAT_NAMES.size():
        return false
    for value in saved.stats:
        if not _is_int(value, 0, 100):
            return false
    if not _valid_ids(saved.get("collected"), word_by_id) or not saved.get("history") is Array:
        return false
    if not saved.get("gains", {}) is Dictionary or not saved.get("visited", []) is Array:
        return false
    for id in saved.gains:
        if not saved.collected.has(id) or not _valid_delta(saved.gains[id]):
            return false
    for entry in saved.history:
        if not entry is Dictionary or not entry.get("text") is String or not entry.get("speaker") is String or not entry.get("id") is String:
            return false
    # Slots: traumas with state, kept words with levels, or empty.
    var saved_slots = saved.get("slots")
    if not saved_slots is Array or saved_slots.size() != int(data.rules.slot_count):
        return false
    var kept: Array = []
    var active: Array = []
    for entry in saved_slots:
        if not entry is String:
            return false
        if entry.begins_with("w:"):
            var id: String = entry.trim_prefix("w:")
            if word_by_id(id).is_empty() or kept.has(id) or not saved.collected.has(id):
                return false
            kept.append(id)
        elif entry.begins_with("t:"):
            var id: String = entry.trim_prefix("t:")
            if trauma_by_id(id).is_empty() or active.has(id):
                return false
            active.append(id)
        elif entry != "":
            return false
    if not saved.get("trauma_state") is Dictionary:
        return false
    for id in active:
        var state = saved.trauma_state.get(id)
        if not state is Dictionary or not _is_int(state.get("hardness"), 1, 100) or not _is_int(state.get("cost"), 1, 10000000):
            return false
        if not state.get("loosened") is bool:
            return false
    for id in saved.trauma_state:
        if trauma_by_id(id).is_empty() or not saved.trauma_state[id] is Dictionary:
            return false
    if not saved.get("levels") is Dictionary:
        return false
    for id in saved.levels:
        if not kept.has(id) or not _is_int(saved.levels[id], 1, word_by_id(id).levels.size()):
            return false
    for id in kept:
        if not saved.levels.has(id):
            return false
    if not _is_int(saved.get("exp"), 0, 100000000) or not _is_int(saved.get("exp_total"), 0, 100000000):
        return false
    if not _valid_ids(saved.get("released", []), word_by_id) or not _valid_ids(saved.get("resolved", []), trauma_by_id) or not _valid_ids(saved.get("surfaced", []), trauma_by_id):
        return false
    for id in saved.released:
        if kept.has(id) or not saved.collected.has(id):
            return false
    for id in saved.resolved:
        if active.has(id):
            return false
    # Pending word offer.
    var pending = saved.get("pending_word", "")
    var step = saved.get("pending_step", "")
    if not pending is String or step not in PENDING_STEPS or (pending == "") != (step == ""):
        return false
    if pending != "":
        if not saved.collected.has(pending):
            return false
        if step == "kept" and not kept.has(pending):
            return false
        if step in ["offer", "forget", "released"] and kept.has(pending):
            return false
        if step == "released" and not saved.released.has(pending):
            return false
    if not _is_int(saved.get("pending_gain", 0), 0, 100000000) or not _is_int(saved.get("pending_slot", -1), -1, int(data.rules.slot_count) - 1):
        return false
    # Counseling.
    var counsel = saved.get("counsel_step", "opening_doctor")
    if counsel not in COUNSEL_STEPS or not _is_int(saved.get("counsel_session", 0), 0, data.rounds.size()):
        return false
    var talking = saved.get("counsel_trauma", "")
    if not talking is String or (counsel == "talk") != (talking != ""):
        return false
    if talking != "" and (not active.has(talking) or not _is_int(saved.get("talk_index", 0), 0, trauma_by_id(talking).talk.size() - 1)):
        return false
    if not saved.get("talked", false) is bool or not saved.get("session_lines", []) is Array:
        return false
    for line in saved.session_lines:
        if not line is Array or line.size() != 2 or not line[0] is String or not line[1] is String:
            return false
    if not _is_int(saved.get("round_index", 0), 0, data.rounds.size()) or not _is_int(saved.get("outings_done", 0), 0, 99):
        return false
    for id in saved.visited:
        if not id is String or event_by_id(id).is_empty():
            return false
    if not saved.get("scene_key", "") is String:
        return false
    current = node_id
    collected = saved.collected
    gains = {}
    for id in saved.gains:
        gains[id] = saved.gains[id].map(func(value): return int(value))
    stats = saved.stats.map(func(value): return int(value))
    history = saved.history
    read_count = int(saved.get("read_count", 0))
    speed = clampf(float(saved.get("speed", 32)), 12, 80)
    scene_key = saved.get("scene_key", "")
    pending_word = pending
    pending_step = step
    pending_gain = int(saved.get("pending_gain", 0))
    pending_slot = int(saved.get("pending_slot", -1))
    counsel_step = counsel
    counsel_session = int(saved.get("counsel_session", 0))
    counsel_trauma = talking
    talk_index = int(saved.get("talk_index", 0))
    talked = saved.get("talked", false)
    session_lines = saved.get("session_lines", [])
    round_index = int(saved.get("round_index", 0))
    outings_done = int(saved.get("outings_done", 0))
    visited = saved.visited
    slots = saved_slots
    trauma_state = {}
    for id in saved.trauma_state:
        var state: Dictionary = saved.trauma_state[id]
        trauma_state[id] = {"hardness": int(state.get("hardness", 0)), "cost": int(state.get("cost", 0)),
            "loosened": bool(state.get("loosened", false))}
    levels = {}
    for id in saved.levels:
        levels[id] = int(saved.levels[id])
    exp = int(saved.exp)
    exp_total = int(saved.exp_total)
    released = saved.released
    resolved = saved.resolved
    surfaced = saved.surfaced
    last_delta = []
    last_exp = 0
    return true
