extends SceneTree

const State = preload("res://src/story_state.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        push_error(message)

func _initialize() -> void:
    call_deferred("run")

func bounded(state, before: Array, delta: Array, label: String) -> void:
    check(delta.filter(func(value): return value != 0).size() <= 2, label + ": at most two stats move")
    for k in range(4):
        check(state.stats[k] == before[k] + delta[k], label + ": accurate delta")
        check(state.stats[k] >= 0 and state.stats[k] <= 100, label + ": bounded stats")

func slots_consistent(state, label: String) -> void:
    check(state.slots.size() == 8, label + ": eight slots")
    for entry in state.slots:
        if entry.begins_with("t:"):
            var id: String = entry.trim_prefix("t:")
            check(state.hardness(id) > 0 and state.hardness(id) <= 100, label + ": active trauma has hardness")
            check(not state.resolved.has(id), label + ": resolved trauma left its slot")
        elif entry.begins_with("w:"):
            var id: String = entry.trim_prefix("w:")
            check(state.word_level(id) >= 1 and state.word_level(id) <= 3, label + ": kept word has a level")
            check(not state.released.has(id), label + ": released word left its slot")
        else:
            check(entry == "", label + ": slot is trauma, word or empty")
    check(state.exp >= 0, label + ": EXP never negative")
    for id in state.surfaced:
        check(state.slots.has("t:" + id) or state.resolved.has(id), label + ": surfaced trauma occupies a slot")

func handle_word(state, selection: int) -> void:
    check(state.pending_step == "offer", "A new word is offered")
    var kept_before: int = state.kept_words().size()
    var exp_before: int = state.exp
    var id: String = state.pending_word
    if selection == 0 and state.can_keep():
        check(state.keep_pending(), "Keep into a free slot")
        check(state.is_kept(id) and state.pending_step == "kept" and state.kept_words().size() == kept_before + 1, "Kept word fills a slot")
    elif selection == 0 and not state.kept_words().is_empty():
        check(state.request_forget(), "Full slots ask which word to forget")
        var victim: String = state.kept_words()[0]
        var value: int = state.release_value(victim)
        check(state.forget_for_pending(victim) == value, "Forgetting returns the word's EXP value")
        check(not state.is_kept(victim) and state.is_kept(id) and state.released.has(victim), "Forgotten word swapped for the new one")
        check(state.exp == exp_before + value and state.pending_gain == value, "Forgotten word became EXP")
    elif selection == 2 and state.can_keep():
        check(state.keep_pending(), "Keep when a slot is free")
    else:
        var value: int = state.release_value(id)
        check(not state.keep_pending(), "Cannot keep without a slot" if not state.can_keep() else "Release chosen")
        check(state.release_pending() == value and state.exp == exp_before + value, "Released word becomes EXP")
        check(state.pending_step == "released" and state.released.has(id) and not state.is_kept(id), "Released word is recorded")
    check(state.acknowledge_word() and state.pending_word == "" and state.pending_step == "", "Offer acknowledged")

func run() -> void:
    var state = State.new()
    state.save_path = "/tmp/yodaka-runtime-test.json"
    var backup: String = state.save_path
    check(State.STAT_NAMES.size() == 4 and State.STAT_NAMES[0] == "ストレス", "Stress plus three stats")
    # Initial situation: every slot holds a trauma and the debuffs bite.
    state.reset()
    check(state.slots.size() == 8 and state.active_traumas().size() == 8 and state.kept_words().is_empty(), "All eight slots start as traumas")
    check(state.free_slot() == -1, "No free slot at the start")
    check(state.effective(0) == 50 and state.stat_offset(0) == 30, "Blank half year adds constant stress")
    check(state.stat_cap(1) == 5 and state.effective(1) == 5, "Lost basketball shoes cap courage at five")
    check(state.effective(2) == 20 and state.effective(3) == 20, "Mirror and empty morning lower self and sparkle")
    check(is_equal_approx(state.gain_multiplier(3), 0.5) and is_equal_approx(state.gain_multiplier(2), 0.5), "Uniform and classroom air halve gains")
    check(is_equal_approx(state.recovery_multiplier(), 0.5), "Stalling halves stress recovery")
    check(state.exp_per_tap() == 1 and is_equal_approx(state.exp_multiplier(), 0.5), "EXP debuff never drops a tap below one")
    check(state.preview({"キラキラ": 6}) == [0, 0, 0, 3], "Halved gain applies to previews")
    check(state.preview({"ストレス": -4}) == [-2, 0, 0, 0], "Halved recovery applies to stress relief")
    check(state.preview({"勇気": 1}) == [0, 1, 0, 0], "A gain never rounds to nothing")
    for selection in range(3):
        state.reset()
        check(state.current == "counsel0_6", "Prototype opens in the counseling room")
        var guard := 0
        var chapters: Array = []
        var outings := 0
        var sessions: Array = []
        var confronts := 0
        var grown := 0
        while state.current != "result":
            guard += 1
            check(guard < 900, "Scenario loop")
            if guard >= 900:
                break
            if state.current == "map":
                if state.round_index == 0:
                    check(not state.select_event("sumika"), "Sumika unlocks from the second week")
                var picked := ""
                var order := ["sushi", "park", "cafe", "sumika", "cry"]
                for i in range(order.size()):
                    var id: String = order[(i + selection) % order.size()]
                    if state.event_available(id):
                        picked = id
                        break
                if picked == "" or (selection == 2 and outings == 1):
                    picked = "rest"
                var visited_before: int = state.visited.size()
                check(state.select_event(picked), "Select an available event: " + picked)
                check(picked == "rest" or state.visited.size() == visited_before + 1, "Visited event recorded")
                check(not state.select_event(picked) or picked == "rest", "Cannot select the same event twice")
                outings += 1
                continue
            if state.current == "counseling":
                sessions.append(state.counsel_session)
                var steps: Array = []
                var exp_at_start: int = state.exp
                while state.current == "counseling":
                    guard += 1
                    if guard >= 900:
                        break
                    steps.append(state.counsel_step)
                    match state.counsel_step:
                        "session":
                            check(state.in_session(), "Session step is interactive")
                            if not state.talked:
                                var sealed: Array = state.active_traumas().filter(func(id): return not state.is_loosened(id))
                                if not sealed.is_empty():
                                    var target: String = sealed[selection % sealed.size()]
                                    check(state.confront_preview(target, []).is_empty(), "Sealed trauma cannot be faced")
                                    check(state.start_talk(target) and state.counsel_step == "talk", "Talking about a trauma starts its dialogue")
                                    var resumed = State.new()
                                    resumed.save_path = backup
                                    check(resumed.load_game() and resumed.counsel_step == "talk" and resumed.counsel_trauma == target, "Talk persists")
                                    continue
                            var acted := false
                            for id in state.active_traumas():
                                if not state.is_loosened(id):
                                    continue
                                var cards: Array = state.kept_words().slice(0, 2)
                                var plan: Dictionary = state.confront_preview(id, cards)
                                check(not plan.is_empty() and plan.cost >= 1, "Loosened trauma has a plan")
                                if plan.affordable:
                                    var exp_before: int = state.exp
                                    var hardness_before: int = state.hardness(id)
                                    var result: Dictionary = state.confront(id, cards)
                                    check(not result.is_empty() and state.exp == exp_before - int(plan.cost), "Facing a trauma spends the previewed EXP")
                                    check(result.before == hardness_before and result.after == plan.after, "Facing softens as previewed")
                                    if result.surfaced != "":
                                        check(state.slots.has("t:" + result.surfaced) and state.hardness(result.surfaced) == 100, "Deeper trauma takes the slot")
                                    elif result.resolved:
                                        check(state.resolved.has(id) and not state.slots.has("t:" + id), "Resolved trauma frees its slot")
                                    else:
                                        check(state.hardness(id) == plan.after, "Hardness updated")
                                    check(state.session_lines.size() == 2, "Counseling lines accompany the change")
                                    confronts += 1
                                    acted = true
                                    break
                            if not acted and selection != 1:
                                for id in state.kept_words():
                                    if state.can_grow(id):
                                        var level: int = state.word_level(id)
                                        var cost: int = state.grow_cost(id)
                                        var exp_before: int = state.exp
                                        check(not state.grow(id).is_empty() and state.word_level(id) == level + 1 and state.exp == exp_before - cost, "Growing a word costs its level price")
                                        grown += 1
                                        acted = true
                                        break
                            if not acted:
                                check(state.end_session() and state.counsel_step == "closing", "Ending the session leads to the closing")
                        _:
                            check(state.advance_counseling(), "Counseling advances: " + state.counsel_step)
                check(steps[0] == "opening_doctor" and steps.back() == "farewell", "Counseling opens and closes")
                check(steps.has("session") and steps.has("talk"), "Every session talks about one trauma")
                check(state.exp <= exp_at_start + 20, "A session spends rather than earns EXP")
                slots_consistent(state, "after session")
                continue
            var node: Dictionary = state.data.nodes[state.current]
            if node.get("kind") == "main" and (chapters.is_empty() or chapters.back() != node.chapter):
                chapters.append(node.chapter)
            var exp_before: int = state.exp
            var added: bool = state.finish_line()
            check(state.exp == exp_before + state.last_exp and state.last_exp >= 1, "Every read line earns EXP")
            if added:
                handle_word(state, selection)
            var count: int = state.collected.size()
            var stats_after: Array = state.stats.duplicate()
            var exp_after: int = state.exp
            state.finish_line()
            check(count == state.collected.size() and stats_after == state.stats and exp_after == state.exp, "Duplicate collection, effect or EXP")
            var choice: int = selection % node.choices.size() if node.has("choices") else 0
            if not state.can_choose(choice):
                choice = 0
            check(state.choose(choice), "Available choice advances")
        check(chapters.size() == 4 and chapters[0] == "tiktokの女王" and chapters[3] == "溺れる海のあしか", "Four main chapters in order")
        check(outings == 6, "Six outings across the rounds")
        check(sessions == [0, 1, 2, 3], "Four counseling sessions: opening, two in between, closing")
        check(state.collected.size() >= 6 and state.collected.size() <= 10, "Words heard across outings and chapters: %d" % state.collected.size())
        check(state.resolved.size() + state.surfaced.size() >= 1, "The first trauma dissolves or reveals its depth in a run")
        slots_consistent(state, "end of run")
        print("Strategy %d: %d words heard, %d kept, %d released, %d faced, %d grown, %d resolved, %d surfaced, EXP %d/%d, stats %s eff %s" % [selection, state.collected.size(), state.kept_words().size(), state.released.size(), confronts, grown, state.resolved.size(), state.surfaced.size(), state.exp, state.exp_total, state.stats, state.effective_stats()])
        for id in state.collected:
            check(state.gains.has(id) and state.gains[id].size() == 4, "Collection effect recorded")
        check(state.confront("bash", []).is_empty() and state.grow("praise").is_empty(), "No counseling actions after the end")
        var restored = State.new()
        restored.save_path = backup
        check(restored.load_game(), "Can restore saved run")
        check(restored.stats == state.stats and restored.current == "result", "Stats persisted")
        check(restored.slots == state.slots and restored.exp == state.exp and restored.levels == state.levels, "Slots, EXP and levels persisted")
        check(restored.resolved == state.resolved and restored.released == state.released and restored.surfaced == state.surfaced, "History persisted")
    # Opening session: 37 lines earn 37 EXP, one trauma loosens for 20 and one facing fits.
    state.reset()
    var guard := 0
    while state.current != "counseling" and guard < 100:
        guard += 1
        state.finish_line()
        state.choose(0)
    check(state.current == "counseling" and state.counsel_session == 0 and state.exp == 37, "Tutorial ends in session zero with one EXP per line")
    check(not state.in_session() and state.advance_counseling() and state.advance_counseling() and state.in_session(), "Opening lines lead into the session")
    check(not state.can_talk("nowhere") and state.can_talk("blank"), "Only traumas in slots can be talked about")
    check(state.start_talk("blank"), "Talk about the half year")
    var lines := 0
    while state.counsel_step == "talk":
        var line: Dictionary = state.talk_line()
        check(line.speaker in ["みなと", "よだか"] and line.text != "", "Talk lines alternate between the two")
        state.advance_counseling()
        lines += 1
    check(lines == 5 and state.is_loosened("blank") and state.trauma_cost("blank") == 20, "First loosened trauma costs the starter price")
    check(state.talked and not state.can_talk("bash"), "One talk per session")
    var plan: Dictionary = state.confront_preview("blank", [])
    check(plan.cost == 20 and plan.soften == 30 and plan.after == 70 and plan.affordable and not plan.surfaces, "Preview of the first facing")
    var before_face: Array = state.effective_stats()
    var result: Dictionary = state.confront("blank", [])
    check(result.after == 70 and state.exp == 17 and state.stat_offset(0) == 21 and state.effective(0) == before_face[0] - 9, "Facing shrinks the constant stress")
    check(not state.confront_preview("blank", []).affordable and state.confront("blank", []).is_empty(), "Cannot face without EXP")
    check(state.confront_preview("blank", ["praise"]).is_empty(), "Only kept words can be combined")
    var resumed_session = State.new()
    resumed_session.save_path = backup
    check(resumed_session.load_game() and resumed_session.in_session() and resumed_session.hardness("blank") == 70 and resumed_session.talked, "Session persists")
    check(state.end_session() and state.advance_counseling() and state.advance_counseling() and state.current == "map" and state.round_index == 0, "Session zero returns to the first map")
    # Later talks divide the outrageous cost; the second week's counseling is session one.
    state.current = "counseling"
    state.counsel_step = "session"
    state.talked = false
    check(state.start_talk("bash"), "Second talk")
    while state.counsel_step == "talk":
        state.advance_counseling()
    check(state.trauma_cost("bash") == 1000 and state.trauma_by_id("bash").base_cost == 200000, "Talking divides 200,000 EXP to 1,000")
    # Words: keep, release, forget, grow, passives and combination effects.
    state.reset()
    state.slots[6] = ""
    state.current = "sushi_10"
    var before_word: Array = state.stats.duplicate()
    check(state.finish_line() and state.pending_word == "praise" and state.pending_step == "offer", "Marked line offers a word")
    check(state.stats[0] == before_word[0] - 3 and state.stats[2] == before_word[2] + 3, "Hearing a word changes stats at once, through the debuffs")
    check(state.gains["praise"] == [-3, 0, 3, 0], "Collection delta recorded")
    check(state.release_value("praise") == 30 and state.can_keep() and state.keep_pending(), "Keep the first word")
    check(state.slots[6] == "w:praise" and state.word_level("praise") == 1 and state.pending_slot == 6, "Kept word sits in the freed slot")
    check(state.stat_offset(1) == 1 and state.effective(1) == 5, "Passive courage is capped by the shoes")
    check(state.acknowledge_word(), "Acknowledge")
    state.current = "cafe_7"
    check(state.finish_line() and not state.can_keep() and state.request_forget(), "Full slots ask to forget")
    check(state.cancel_forget() and state.pending_step == "offer" and state.request_forget(), "Forgetting can be cancelled and asked again")
    var exp_taps: int = state.exp
    check(state.forget_for_pending("praise") == 30 and state.slots[6] == "w:miracle" and state.released.has("praise") and state.exp == exp_taps + 30, "Forget swaps words and pays EXP")
    check(state.acknowledge_word(), "Acknowledge swap")
    state.current = "main1_28"
    exp_taps = state.exp
    check(state.finish_line() and state.release_pending() == 80 and state.exp == exp_taps + 81 and state.pending_step == "released", "Release pays the word's value")
    check(state.acknowledge_word(), "Acknowledge release")
    state.current = "counseling"
    state.counsel_step = "session"
    check(state.grow_cost("miracle") == 200 and not state.can_grow("miracle"), "Growth needs EXP")
    state.exp = 1300
    check(state.grow("miracle").level == 2 and state.exp == 1100 and state.stat_offset(1) == 6, "Grown word strengthens its passive")
    check(state.grow("miracle").level == 3 and state.exp == 300 and state.grow_cost("miracle") == -1 and state.grow("miracle").is_empty(), "Words stop at level three")
    check(state.release_value("miracle") == 150, "Release value grows with level")
    state.slots[7] = "w:cute"
    state.levels["cute"] = 1
    state.trauma_state["uniform"].loosened = true
    state.trauma_state["uniform"].cost = 600
    state.slots[4] = "w:happiness"
    state.levels["happiness"] = 1
    var combo: Dictionary = state.confront_preview("uniform", ["miracle", "cute"])
    check(combo.cost == 600 and combo.soften == 30 + 40 + 15 and combo.after == 15, "Combined words add their softening")
    var cheap: Dictionary = state.confront_preview("uniform", ["happiness", "cute"])
    check(cheap.cost == 60 and cheap.soften == 45, "A tenth-cost word divides the price")
    check(state.confront_preview("uniform", ["miracle", "cute", "happiness"]).is_empty() and state.confront_preview("uniform", ["cute", "cute"]).is_empty(), "At most two distinct words")
    check(is_equal_approx(state.gain_multiplier(3), 0.5), "Sparkle gain halved by the uniform")
    check(state.forget_in_session("cute") == 40 and state.slots[7] == "" and state.exp == 340, "Forgetting in session frees a slot for EXP")
    # Deeper traumas surface when softened past the threshold without a calming word.
    state.reset()
    state.current = "counseling"
    state.counsel_step = "session"
    state.exp = 5000
    state.trauma_state["mirror"].loosened = true
    state.trauma_state["mirror"].cost = 100
    state.slots[7] = "w:sparkle"
    state.levels["sparkle"] = 2
    state.slots[6] = "w:new_self"
    state.levels["new_self"] = 1
    var risky: Dictionary = state.confront_preview("mirror", ["sparkle"])
    check(risky.soften == 60 and risky.after == 40 and risky.surfaces, "Crossing below fifty wakes the deeper trauma")
    var safe: Dictionary = state.confront_preview("mirror", ["sparkle", "new_self"])
    check(safe.calm and not safe.surfaces, "A calming word keeps the deeper trauma down")
    var surfaced: Dictionary = state.confront("mirror", ["sparkle"])
    check(surfaced.surfaced == "nameless" and state.slots[5] == "t:nameless" and state.hardness("nameless") == 100 and not state.is_loosened("nameless"), "Nameless feeling replaces the mirror")
    check(state.stat_offset(2) == -30 and state.stat_offset(1) == -10 and state.surfaced == ["nameless"], "The deeper trauma hits harder")
    check(state.exp == 4900 and state.hardness("mirror") == 0 and not state.resolved.has("mirror"), "Surfacing is not a resolution")
    state.trauma_state["blank"].loosened = true
    state.trauma_state["blank"].cost = 100
    check(state.confront("blank", ["sparkle", "new_self"]).after == 40 and state.slots[1] == "t:blank" and state.hardness("blank") == 40, "Calm facing keeps the half year as it is")
    check(state.confront("blank", ["sparkle"]).resolved and state.slots[1] == "" and state.resolved == ["blank"], "Below the threshold the half year resolves without surfacing")
    check(state.stat_offset(0) == 0, "Resolved trauma stops its debuff")
    # Courage gate uses the effective value; the shoes must soften first.
    state.reset()
    state.current = "main4_31"
    state.stats[1] = 60
    check(not state.can_choose(1) and not state.choose(1) and state.current == "main4_31", "Capped courage cannot unlock the princess choice")
    state.trauma_state["bash"].hardness = 40
    check(state.stat_cap(1) == 62 and state.effective(1) == 60, "Softened shoes raise the cap")
    check(state.choose(1) and state.current == "main4_38", "Effective courage 60 unlocks choice")
    state.reset()
    state.stats[1] = 59
    state.current = "main4_31"
    state.slots[0] = ""
    state.resolved.append("bash")
    check(not state.choose(1), "Courage 59 is rejected")
    state.stats[1] = 60
    check(state.choose(1), "Courage 60 is accepted once the shoes are gone")
    # Day endings: rest, outings, chapters and the counseling after flagged rounds.
    state.reset()
    state.current = "rest_2"
    var before_rest: int = state.stats[0]
    state.finish_line()
    check(state.stats[0] == before_rest - 8, "Resting lowers stress, halved by stalling")
    check(state.choose(0) and state.current == "map" and state.outings_done == 1, "Rest counts as an outing and the day ends in sleep")
    state.current = "park_15"
    var before_sleep: int = state.stats[0]
    check(state.choose(0) and state.current == "main1_5" and state.outings_done == 2, "Second outing opens the chapter")
    check(state.stats[0] == clampi(before_sleep - 2 + 6, 0, 100), "Sleep then a chapter costs stress")
    state.current = "main1_47"
    check(state.data.nodes["main1_47"].next == "sleep" and state.choose(0) and state.current == "counseling" and state.counsel_session == 1 and state.round_index == 1, "Chapter one leads to the second counseling")
    state.round_index = 1
    state.current = "main2_59"
    check(state.data.nodes["main2_59"].next == "sleep" and state.choose(0) and state.current == "map" and state.round_index == 2, "Chapter two returns to the map")
    state.current = "main3_54"
    check(state.choose(0) and state.current == "counseling" and state.counsel_session == 2, "Chapter three leads to the third counseling")
    state.round_index = 3
    state.current = "main4_66"
    check(state.choose(0) and state.current == "counseling" and state.counsel_session == 3 and state.final_session(), "Chapter four leads to the final counseling")
    state.counsel_step = "farewell"
    check(state.advance_counseling() and state.current == "result", "Final farewell ends the prototype")
    # Stress lock uses the effective stress.
    state.reset()
    state.current = "map"
    state.stats[0] = 50
    check(not state.event_available("park") and state.event_available("rest"), "Effective stress 80 allows only resting")
    check(not state.select_event("park"), "Locked outing rejected")
    state.stats[0] = 49
    check(state.event_available("park") and not state.event_available("sumika"), "Week one pool excludes later events")
    state.round_index = 1
    check(state.event_available("sumika") and state.event_available("cry"), "Week two unlocks new places")
    state.visited = ["park"]
    check(not state.event_available("park") and state.event_available("rest"), "Visited place closed, rest repeatable")
    # Saves: corrupt, previous flow, and inconsistent data are rejected.
    var invalid := FileAccess.open(backup, FileAccess.WRITE)
    invalid.store_string("{broken")
    invalid.close()
    check(not state.load_game(), "Corrupt save rejected")
    var old := FileAccess.open(backup, FileAccess.WRITE)
    old.store_string(JSON.stringify({"version": 4, "current": "main4_5", "collected": [], "answers": [], "stats": [65, 40, 45, 40], "history": []}))
    old.close()
    check(not state.load_game(), "Previous flow saves are not loaded")
    state.reset()
    state.save_game()
    var parser := JSON.new()
    parser.parse(FileAccess.get_file_as_string(backup))
    var tampered: Dictionary = parser.data
    tampered.slots[0] = "w:praise"
    var tampered_file := FileAccess.open(backup, FileAccess.WRITE)
    tampered_file.store_string(JSON.stringify(tampered))
    tampered_file.close()
    check(not state.load_game(), "A kept word must have been heard and levelled")
    DirAccess.remove_absolute(backup)
    # Drive the actual UI: interludes, cast, the word offer, the session screen.
    var scene = load("res://src/main.tscn").instantiate()
    root.add_child(scene)
    scene.state.save_path = "/tmp/yodaka-ui-test.json"
    scene.state.reset()
    scene._show_story()
    check(scene.overlay_kind == "scene", "Opening counseling card appears")
    var start_id: String = scene.state.current
    scene._process(10)
    scene._advance()
    scene._close_overlay()
    check(scene.state.current == start_id and not scene.completed, "Card blocks input and typewriter")
    check(scene.overlay_kind == "scene", "Escape cannot skip card acknowledgement")
    await dismiss(scene)
    check(not is_instance_valid(scene.overlay), "Click closes card")
    check(scene.portraits.has("みなと") and scene.portraits.has("よだか"), "Counselor Minato and Yodaka present")
    check(scene.portraits["よだか"].modulate.r == 1.0, "Narration lights Yodaka")
    check(scene.portraits["みなと"].get_index() > scene.body.get_index(), "Partner in front of dialogue")
    check(is_equal_approx(scene.body.position.x + scene.body.size.x / 2, 640), "Text centered on screen")
    check(scene.stat_bars.size() == 4 and scene.slot_buttons.size() == 8, "Four bars and eight slots in the bottom panel")
    check(scene.stat_labels[1].text == "5" and scene.stat_labels[0].text == "50", "Bars show effective values")
    scene._advance()
    check(scene.completed and scene.hint.text.begins_with("+1 EXP") and scene.exp_label.text == "1 EXP", "First action reveals the line and earns EXP")
    var current: String = scene.state.current
    scene._show_history()
    scene._advance()
    check(scene.state.current == current, "Modal prevents advancing")
    scene._close_overlay()
    scene._advance()
    check(scene.state.current != current, "Second action advances")
    check(scene.portraits["みなと"].modulate.r == 1.0 and scene.portraits["よだか"].modulate.r < 0.6, "Speaking Minato lit, Yodaka dimmed")
    scene._slot_pressed(0)
    check(scene.overlay_kind == "modal", "Clicking a trauma slot opens its card")
    scene._close_overlay()
    # Tutorial choice with visible effect previews.
    scene.state.current = "counsel1_10"
    scene._show_story()
    scene._finish_line()
    check(scene.preview_labels.size() == 3 and "自認 +2" in scene.preview_labels[0], "Tutorial choices preview their halved effects")
    var before_ui: Array = scene.state.stats.duplicate()
    scene._story_choice(2)
    check(scene.state.current == "counsel1_16" and scene.state.stats[0] == before_ui[0] + 4, "UI choice applies tutorial effect")
    scene.state.current = "counsel1_45"
    scene._show_story()
    scene._finish_line()
    check("カルテ" in scene.next_button.text, "Karte line announces the chart")
    scene._advance()
    check(scene.overlay_kind == "modal" and scene.state.current == "counsel1_45", "Karte opens before advancing")
    scene._close_overlay()
    check(not scene.karte_shown, "Escape leaves karte unacknowledged")
    scene._advance()
    for child in scene.overlay.get_children():
        for button in child.get_children():
            if button is Button:
                button.pressed.emit()
    check(scene.karte_shown and not is_instance_valid(scene.overlay), "Closing karte acknowledges it")
    scene._advance()
    check(scene.state.current == "counsel1_47", "Advance continues after karte")
    # Word offer: release when no slot is free, keep when one is.
    scene.state.current = "sushi_10"
    scene._show_story()
    await dismiss(scene)
    scene._advance()
    check(scene.portraits.has("りあ"), "Mother portrait displayed")
    check(scene.state.collected.size() == 1 and scene.state.pending_step == "offer", "UI offers the completed marked word")
    check(scene.overlay_kind == "word", "Offer creates blackout effect")
    var keep_button: Button
    var release_button: Button
    var delta_shown := false
    for child in scene.overlay.get_children():
        if child is Label and "ストレス -3" in child.text:
            delta_shown = true
        if child is Button and child.text.begins_with("心に留める") or (child is Button and "忘れて" in child.text):
            keep_button = child
        if child is Button and child.text.begins_with("手放す"):
            release_button = child
    check(delta_shown, "Offer shows the stat change")
    check(keep_button != null and keep_button.disabled and release_button != null and "30 EXP" in release_button.text, "Keeping is impossible while traumas fill every slot")
    scene.auto_mode = true
    scene._process(20)
    scene._advance()
    scene._close_overlay()
    check(scene.overlay_kind == "word" and scene.state.current == "sushi_10", "Offer requires a decision even on AUTO")
    await dismiss(scene)
    check(scene.overlay_kind == "word" and scene.state.pending_step == "offer", "Clicking the background does not skip the decision")
    var restored_pending = State.new()
    restored_pending.save_path = scene.state.save_path
    check(restored_pending.load_game() and restored_pending.pending_word == "praise" and restored_pending.pending_step == "offer", "Undecided offer persists")
    scene._release_pending()
    check(scene.state.pending_step == "released" and scene.state.exp >= 30 and scene.exp_label.text == State._format_exp(scene.state.exp), "Release pays EXP and updates the counter")
    await dismiss(scene)
    check(scene.state.pending_word == "" and not is_instance_valid(scene.overlay), "Click acknowledges the released word")
    scene.state.slots[3] = ""
    scene.state.trauma_state.erase("air")
    scene.state.current = "cafe_7"
    scene._show_story()
    await dismiss(scene)
    scene._advance()
    check(scene.state.pending_step == "offer" and scene.state.can_keep(), "A freed slot allows keeping")
    await settle(scene)
    scene._keep_pending()
    check(scene.state.pending_step == "kept" and scene.state.slots[3] == "w:miracle", "Keep places the word in the free slot")
    await dismiss(scene)
    check(scene.state.pending_word == "" and scene.state.is_kept("miracle"), "Kept word acknowledged")
    scene.state.current = "main1_28"
    scene._show_story()
    await dismiss(scene)
    scene._advance()
    check(scene.state.pending_step == "offer" and not scene.state.can_keep(), "Slots full again")
    await settle(scene)
    scene._keep_pending()
    check(scene.state.pending_step == "forget", "Keeping with full slots asks what to forget")
    var forget_buttons := 0
    for child in scene.overlay.get_children():
        if child is Button and child.text.begins_with("忘れる"):
            forget_buttons += 1
    check(forget_buttons == 1, "One kept word offered for forgetting")
    scene._cancel_forget()
    check(scene.state.pending_step == "offer", "Cancel returns to the offer")
    scene._keep_pending()
    scene._forget_pending("miracle")
    check(scene.state.pending_step == "kept" and scene.state.slots[3] == "w:queen" and scene.state.released.has("miracle"), "Forgetting swaps the words")
    await dismiss(scene)
    check(scene.portraits.has("あしか") and scene.portraits["あしか"].modulate.r == 1.0, "Speaking Ashika uses supplied portrait")
    # MAP and the day ending straight into the next morning.
    scene.state.reset()
    scene.state.current = "map"
    scene._show_story()
    check(scene.mode == "map", "MAP renders")
    var enabled := 0
    for child in scene.content.get_children():
        if child is Button and child.text.begins_with("0") and not child.disabled:
            enabled += 1
    check(enabled == 4, "Week one offers three places and rest")
    scene._select_map_event("sumika")
    check(scene.state.current == "map", "Locked place ignored")
    scene._select_map_event("park")
    check(scene.state.current == "park_6" and scene.state.stats[0] == 25, "MAP opens selected event and going out costs stress")
    await dismiss(scene)
    scene.state.current = "park_15"
    scene._finish_line()
    scene._advance()
    check(scene.mode == "map" and scene.state.outings_done == 1, "The outing ends and the next morning is the map")
    # Counseling session screen.
    scene.state.reset()
    scene.state.exp = 60
    scene.state.slots[2] = "w:cute"
    scene.state.levels["cute"] = 1
    scene.state.trauma_state.erase("uniform")
    scene.state.current = "counseling"
    scene.state.counsel_session = 1
    scene.state.round_index = 1
    scene._show_story()
    await dismiss(scene)
    check("どうでしたか" in scene.body.text, "Minato asks about the weeks")
    scene._finish_line()
    scene._advance()
    check(scene.state.counsel_step == "opening_yodaka" and "話せませんでした" in scene.body.text, "Yodaka reports the quiet weeks")
    scene._finish_line()
    scene._advance()
    check(scene.mode == "session" and scene.state.in_session(), "Session screen opens")
    scene._slot_pressed(0)
    check(scene.session_selected == 0 and scene.mode == "session", "Selecting a slot shows its details")
    var talk_button: Button
    for child in scene.content.get_children():
        if child is Button and child.text.begins_with("この傷について"):
            talk_button = child
    check(talk_button != null and not talk_button.disabled, "Sealed trauma offers a talk")
    scene._talk("bash")
    check(scene.mode == "counseling" and scene.state.counsel_step == "talk" and "バッシュ" in scene.body.text, "Talk renders as dialogue")
    for i in range(5):
        scene._finish_line()
        scene._advance()
    check(scene.mode == "session" and scene.state.is_loosened("bash") and scene.state.trauma_cost("bash") == 20, "Talk ends back in the session with a loosened trauma")
    check(scene.state.exp == 67, "Counseling lines also earn EXP")
    scene._slot_pressed(0)
    check(scene.preview_labels.size() == 1 and "20 EXP" in scene.preview_labels[0] and "100 → 70" in scene.preview_labels[0], "Facing previews cost and softening")
    scene._toggle_card("cute")
    check(scene.session_cards == ["cute"] and "100 → 55" in scene.preview_labels[0], "Combining a word changes the preview")
    scene._confront("bash")
    check(scene.state.hardness("bash") == 55 and scene.state.exp == 47 and scene.session_cards.is_empty(), "UI facing applies the plan")
    check(scene.stat_labels[1].text == str(scene.state.effective(1)) and scene.state.effective(1) > 5, "Courage bar follows the loosened cap")
    scene._slot_pressed(2)
    scene._grow("cute")
    check(scene.state.word_level("cute") == 1, "Cannot grow without EXP")
    scene.state.exp = 200
    scene._show_session()
    scene._grow("cute")
    check(scene.state.word_level("cute") == 2 and scene.state.exp == 50 and scene.state.session_lines[0][0] == "よだか", "Growing shows Yodaka's insight")
    scene._slot_pressed(0)
    scene.state.trauma_state["bash"].hardness = 20
    scene._show_session()
    scene._confront("bash")
    check(scene.overlay_kind == "resolved" and scene.state.resolved == ["bash"] and scene.state.slots[0] == "", "Resolution shows its interlude and frees the slot")
    await dismiss(scene)
    check(scene.mode == "session" and not is_instance_valid(scene.overlay), "Back to the session after the interlude")
    scene._end_session()
    check(scene.mode == "counseling" and scene.state.counsel_step == "closing", "Ending the session leads to the closing line")
    scene._finish_line()
    scene._advance()
    check(scene.overlay_kind == "modal", "Closing shows the karte")
    for child in scene.overlay.get_children():
        for button in child.get_children():
            if button is Button:
                button.pressed.emit()
    scene._advance()
    check(scene.state.counsel_step == "farewell", "Farewell after the karte")
    scene._finish_line()
    scene._advance()
    check(scene.mode == "map", "A mid counseling returns to the map")
    scene.state.current = "counseling"
    scene.state.counsel_step = "farewell"
    scene.state.round_index = 4
    scene.state.counsel_session = 3
    scene._show_story()
    await dismiss(scene)
    scene._finish_line()
    scene._advance()
    check(scene.mode == "result", "End screen follows the final farewell")
    scene.state.current = "sumika_6"
    scene._show_story()
    await dismiss(scene)
    check(scene.portraits.has("すみか"), "Sumika portrait displayed")
    scene.state.reset()
    scene.state.current = "main4_31"
    scene.state.stats[1] = 60
    scene._show_story()
    await dismiss(scene)
    scene._finish_line()
    var locked := false
    for child in scene.choice_box.get_children():
        if child is Button and "お姫様" in child.text:
            locked = child.disabled
    check(locked, "Capped courage disables the choice in UI")
    # Verify the centered dialogue area fits all lines, talks and counseling text.
    scene.set_process(false)
    scene._render_dialogue(scene.state.data.nodes["counsel0_6"])
    var texts: Array = []
    for node in scene.state.data.nodes.values():
        texts.append(node.text)
    for trauma in scene.state.data.traumas:
        for line in trauma.talk:
            texts.append(line[1])
    for text in scene.OPENING_TEXT.values():
        texts.append(text)
    for text in scene.SESSION_TEXT.values():
        texts.append(text if not "%d" in text else text % 10)
    for text in texts:
        scene.body.text = "[center]" + text + "[/center]"
        scene.body.visible_characters = -1
        await process_frame
        check(scene.body.get_content_height() <= scene.body.size.y, "Dialogue fits centered area: " + text.left(16))
    scene.queue_free()
    await process_frame
    DirAccess.remove_absolute("/tmp/yodaka-ui-test.json")
    print("%s: %d runtime checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
    quit(0 if failures == 0 else 1)

func settle(scene: Control) -> void:
    if is_instance_valid(scene.interlude_tween) and scene.interlude_tween.is_running():
        await scene.interlude_tween.finished

func dismiss(scene: Control) -> void:
    if is_instance_valid(scene.interlude_tween) and scene.interlude_tween.is_running():
        await scene.interlude_tween.finished
    scene._dismiss_interlude()
    if is_instance_valid(scene.interlude_tween) and scene.interlude_tween.is_running():
        await scene.interlude_tween.finished
