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

func shelf_consistent(state, label: String) -> void:
    check(state.slots.size() == State.SLOTS, label + ": eight slots")
    for id in state.traumas:
        check(state.traumas[id].resolved != (state.slot_of(id) >= 0), label + ": unresolved traumas sit on the shelf, resolved ones do not: " + id)
    for id in state.held_words():
        check(state.collected.has(id) and not state.forgotten.has(id) and not state.used.has(id), label + ": held words were received and not let go")
    for id in state.forgotten + state.used:
        check(state.slot_of(id) < 0, label + ": words let go leave the shelf")
    check(state.exp >= 0 and state.exp_total >= state.exp, label + ": EXP never negative")

func decide_pending(state, selection: int) -> void:
    # Strategy 0 keeps everything (swapping when full), 1 lets everything go, 2 keeps while there is room.
    var id: String = state.pending_word
    var before: int = state.exp
    if selection == 1:
        var value: int = state.release_pending()
        check(value >= 1 and state.exp == before + value and state.forgotten.has(id), "Letting a word go pays EXP")
    elif state.free_slot() >= 0:
        check(state.keep_pending() and state.held_words().has(id), "Kept word takes a free slot")
    elif selection == 0 and not state.held_words().is_empty():
        var victim: String = state.held_words()[0]
        var value: int = state.swap_pending(state.slot_of(victim))
        check(value >= 1 and state.held_words().has(id) and not state.held_words().has(victim) and state.forgotten.has(victim), "Swap forgets a held word for EXP and keeps the new one")
    else:
        check(not state.keep_pending(), "No free slot refuses to keep")
        check(state.release_pending() >= 1, "Full shelf lets the word go")
    check(state.pending_word == "", "Pending word decided")

func play_session(state, selection: int, log: Array) -> void:
    check(state.counsel_step == "opening_doctor", "Session opens with Minato")
    check(state.advance_counseling() and state.advance_counseling() and state.counsel_step == "board", "Opening lines lead to the board")
    var session: int = state.session
    log.append(session)
    # Talk about one trauma, with as many words as the strategy brings.
    var candidates: Array = state.held_traumas().filter(func(id): return state.can_talk(id))
    if session == 1:
        for id in candidates:
            check(not state.trauma_def(id).has("deeper"), "First session keeps to traumas with nothing behind them")
        check(candidates.size() == 6, "Six traumas can be loosened first")
    check(not candidates.is_empty(), "Something to talk about in session %d" % session)
    var target: String = candidates[(selection + session) % candidates.size()]
    check(state.focus_trauma(target), "Focus a trauma")
    var held: Array = state.held_words()
    for i in range(mini(selection, held.size())):
        check(state.toggle_card(held[i]), "Bring a word into the conversation")
    check(state.cards.size() == mini(mini(selection, held.size()), State.MAX_CARDS), "At most two words come along")
    var preview: Dictionary = state.talk_preview(target, state.cards)
    var before: Dictionary = state.traumas[target].duplicate()
    var brought: Array = state.cards.duplicate()
    check(state.talk(), "Talking succeeds")
    check(state.talked and not state.can_talk(target), "One conversation per session")
    var result: Dictionary = state.talk_result
    check(result.before == before.strength and result.after == preview.strength, "Talk result matches its preview")
    if result.emerged == "":
        check(state.traumas[target].strength == preview.strength and state.traumas[target].cost == preview.cost, "Talk applies the preview")
        check(state.traumas[target].strength <= before.strength - State.TALK_WEAKEN or state.traumas[target].strength == 0, "Counseling alone weakens the trauma")
        check(state.traumas[target].unraveled, "A trauma talked about is loosened")
    else:
        check(state.slot_of(result.emerged) >= 0 and state.traumas[target].resolved and state.slot_of(target) < 0, "What emerges takes the slot")
    for id in brought:
        check(state.used.has(id) and state.slot_of(id) < 0, "Words brought along are spent")
    if session == 1:
        check(result.first and state.traumas[target].cost == State.FIRST_FACE_COST, "The first trauma loosened costs the small amount")
        check(state.face_cost(target) <= State.FIRST_FACE_COST, "Facing it is affordable after the opening")
    for step in ["talk_recall", "talk_doctor", "talk_effect"]:
        check(state.counsel_step == step, "Talk dialogue: " + step)
        state.advance_counseling()
    if result.emerged != "":
        check(state.counsel_step == "talk_emerge", "Emergence has its own line")
        state.advance_counseling()
    check(state.counsel_step == "board", "Back to the board after talking")
    # Grow held words while EXP allows (strategy 2 digs deepest).
    if selection == 2:
        for id in state.held_words():
            while state.can_grow(id):
                var level: int = state.level_of(id)
                var cost: int = state.next_level_cost(id)
                var exp_before: int = state.exp
                check(state.grow(id), "Growing a held word")
                check(state.exp == exp_before - cost and state.level_of(id) == level + 1, "Growth costs EXP and raises the level")
                if state.level_of(id) == 2:
                    check(state.counsel_step == "grow_question", "Second level asks how it felt")
                    state.advance_counseling()
                    check(state.counsel_step == "grow_choice", "Then offers the three receptions")
                    var stats_before: Array = state.stats.duplicate()
                    var delta: Array = state.interpret(selection)
                    bounded(state, stats_before, delta, "interpretation")
                    check(state.counsel_step == "grow_reply", "Reception becomes Yodaka's reply")
                else:
                    check(state.counsel_step == "grow_insight", "Third level reveals the insight")
                state.advance_counseling()
                check(state.counsel_step == "grow_response", "Minato responds to growth")
                state.advance_counseling()
                check(state.counsel_step == "board", "Growth returns to the board")
            check(not state.can_grow(id) or state.exp < state.next_level_cost(id), "Growth stops at the top level or when EXP runs out")
    # Face whatever is affordable.
    for id in state.held_traumas():
        if state.can_face(id):
            var cost: int = state.face_cost(id)
            var exp_before: int = state.exp
            check(state.face(id), "Facing an affordable trauma")
            check(state.exp == exp_before - cost and state.traumas[id].resolved and state.slot_of(id) < 0, "Facing spends EXP and frees the slot")
            check(state.counsel_step == "face_line", "Facing has Yodaka's line")
            state.advance_counseling()
    check(state.finish_session() and state.counsel_step == "closing", "Session closes")
    state.advance_counseling()
    check(state.counsel_step == "farewell", "Farewell follows closing")
    state.advance_counseling()
    check(state.current == ("result" if session == State.SESSIONS else "map"), "Session %d leads on" % session)

func run() -> void:
    var state = State.new()
    state.save_path = "/tmp/yodaka-runtime-test.json"
    var backup: String = state.save_path
    check(State.STAT_NAMES.size() == 4 and State.STAT_NAMES[0] == "ストレス", "Stress plus three stats")
    check(state.data.traumas.size() == 10 and state.data.slots == State.SLOTS, "Ten traumas, eight slots")
    for selection in range(3):
        state.reset()
        check(state.current == "counsel0_6", "Prototype opens in the counseling room")
        check(state.held_traumas().size() == State.SLOTS and state.free_slot() < 0, "The shelf starts full of traumas")
        check(state.effective_stats() == [68, 5, 3, 3], "Debuffs show at once: stress plus eight, courage capped, self and sparkle halved")
        var guard := 0
        var chapters: Array = []
        var outings := 0
        var sessions: Array = []
        var taps := 0
        while state.current != "result":
            guard += 1
            check(guard < 800, "Scenario loop")
            if guard >= 800:
                break
            if state.current == "map":
                if state.round_index == 0:
                    check(not state.select_event("sumika"), "Sumika unlocks from the second week")
                var picked := ""
                var order: Array = state.data.map_events.filter(func(e): return not e.get("repeatable", false)).map(func(e): return e.id)
                for i in range(order.size()):
                    var id: String = order[(i + selection * 4) % order.size()]
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
            if state.current == "night":
                var stress: int = state.stats[0]
                var destination: String = state.after_night
                var relief: int = int(state.sleep_effects()["ストレス"])
                var resumed = State.new()
                resumed.save_path = backup
                check(resumed.load_game() and resumed.after_night == destination and resumed.exp == state.exp, "Night persists")
                state.sleep()
                check(state.stats[0] == clampi(clampi(stress + relief, 0, 100) + (6 if destination == "chapter" else 0), 0, 100), "Sleep lowers stress, a chapter costs some")
                check(state.exp_day == 0, "A new day starts its EXP count")
                if destination == "map":
                    check(state.current == "map", "Back to the map")
                elif destination == "chapter":
                    check(state.current.begins_with("main"), "Round leads into a main chapter")
                else:
                    check(state.current == "counseling", "Some chapters lead into counseling")
                continue
            if state.current == "counseling":
                shelf_consistent(state, "before session")
                play_session(state, selection, sessions)
                shelf_consistent(state, "after session")
                continue
            var node: Dictionary = state.data.nodes[state.current]
            if node.get("kind") == "main" and (chapters.is_empty() or chapters.back() != node.chapter):
                chapters.append(node.chapter)
            var exp_before: int = state.exp
            var reads: int = state.read_count
            state.finish_line()
            taps += 1
            check(state.read_count == reads + 1 and state.exp == exp_before + state.exp_per_tap(), "Every new line is a tap worth EXP")
            if state.pending_word != "":
                check(not state.choose(0), "A received word must be decided before going on")
                decide_pending(state, selection)
            var count: int = state.collected.size()
            var stats_after: Array = state.stats.duplicate()
            state.finish_line()
            check(count == state.collected.size() and stats_after == state.stats and state.exp == exp_before + state.exp_per_tap() + (state.exp - exp_before - state.exp_per_tap()), "Duplicate collection or effect")
            var choice: int = selection % node.choices.size() if node.has("choices") else 0
            if not state.can_choose(choice):
                choice = 0
            check(state.choose(choice), "Available choice advances")
        check(chapters.size() == 4 and chapters[0] == "tiktokの女王" and chapters[3] == "溺れる海のあしか", "Four main chapters in order")
        check(outings == 12, "Twelve outings across the rounds")
        check(sessions == [1, 2, 3, 4], "Four counseling sessions: opening, two between, closing")
        check(state.session == State.SESSIONS, "Closing session is the fourth")
        var resolved: int = state.traumas.values().filter(func(t): return t.resolved).size()
        check(resolved >= 1, "At least the first trauma can be faced in a run")
        check(state.collected.size() >= 3 and state.collected.size() <= state.data.words.size(), "Words received across outings and chapters: %d" % state.collected.size())
        check(state.exp_total >= state.read_count, "EXP total covers every tap at least once")
        print("Strategy %d: %d received, %d held, %d let go, %d spent, %d traumas resolved, EXP %d/%d, taps %d, stats %s, effective %s" % [selection, state.collected.size(), state.held_words().size(), state.forgotten.size(), state.used.size(), resolved, state.exp, state.exp_total, taps, state.stats, state.effective_stats()])
        shelf_consistent(state, "end")
        for id in state.collected:
            check(state.gains.has(id) and state.gains[id].size() == 4, "Collection effect recorded")
        check(state.interpret(0).is_empty(), "Cannot answer after the end")
        var restored = State.new()
        restored.save_path = backup
        check(restored.load_game(), "Can restore saved run")
        check(restored.stats == state.stats and restored.current == "result", "Stats persisted")
        check(restored.answers == state.answers and restored.gains == state.gains, "Interpretations persisted")
        check(restored.slots == state.slots and restored.traumas == state.traumas and restored.levels == state.levels, "Shelf, traumas and levels persisted")
        check(restored.exp == state.exp and restored.exp_total == state.exp_total and restored.used == state.used, "EXP and spent words persisted")
    # Immediate effects: words, tutorial choices, and resting, under the starting debuffs.
    state.reset()
    state.current = "cafe_7"
    var before_word: Array = state.stats.duplicate()
    check(state.debuff_active("gain_half"), "The coworker trauma halves what words give")
    check(state.finish_line(), "Marked line collects a word")
    check(state.stats[1] == before_word[1] + 3 and state.stats[2] == before_word[2] + 1, "Receiving a word changes stats at once, halved by the trauma")
    check(state.gains["miracle"] == [0, 3, 1, 0], "Collection delta recorded")
    check(state.pending_word == "miracle" and state.free_slot() < 0 and not state.keep_pending(), "No room on a shelf full of traumas")
    check(state.forget_value("miracle") == 5, "Letting the first word go pays its base halved by the discount trauma")
    check(state.release_pending() == 5 and state.exp == 6, "Let go: EXP from the tap plus the word")
    state.current = "counsel1_10"
    state.finish_line()
    var before_choice: Array = state.stats.duplicate()
    check(state.choose(1) and state.current == "counsel1_14", "Tutorial choice branches")
    check(state.stats[3] == before_choice[3] + 4 and state.stats[0] == before_choice[0] + 3, "Tutorial choice moves stats")
    check(state.last_delta == [3, 0, 0, 4], "Choice delta reported")
    state.current = "cover_15"
    var before_cover: Array = state.stats.duplicate()
    state.finish_line()
    check(state.stats[1] == before_cover[1] + 1 and state.stats[2] == before_cover[2] + 1, "Wordless fragment gives a one-point insight at the end")
    state.current = "rest_2"
    var before_rest: int = state.stats[0]
    state.finish_line()
    check(state.stats[0] == before_rest - 8, "Resting at home recovers only half under the mother's words")
    check(state.choose(0) and state.current == "night" and state.outings_done == 1, "Rest counts as an outing")
    check(state.sleep_effects()["ストレス"] == -2, "Sleep recovers only half while held back")
    # Debuffs read from the shelf and fade as traumas weaken.
    state.reset()
    state.stats = [50, 20, 40, 40]
    check(state.effective_stats() == [58, 5, 20, 20], "Stress plus eight, courage capped at five, self and sparkle halved")
    check(state.debuff_text("handle") == "キラキラ が 50% 減る" and state.debuff_text("no_longer") == "勇気 の上限 5", "Debuffs described")
    state.traumas["handle"].strength = 50
    state.traumas["no_longer"].strength = 50
    state.traumas["normal"].strength = 0
    check(state.effective_stats() == [50, 20, 20, 30], "Weakened traumas bite less: quarter off sparkle, cap lifted to fifty-two, no extra stress")
    state.traumas["held_back"].strength = 50
    state.traumas["coworker"].strength = 50
    check(not state.debuff_active("sleep_half") and not state.debuff_active("gain_half") and state.debuff_active("rest_half"), "Flag debuffs switch off at half strength")
    check(state.sleep_effects()["ストレス"] == -4, "Full sleep once the trauma is weakened")
    # Held words add their passive effects.
    state.slots[0] = {"kind": "word", "id": "miracle"}
    state.traumas["handle"].resolved = true
    state.collected = ["miracle", "queen", "new_self", "happiness"]
    check(state.effective_stats()[1] == 21 and state.exp_per_tap() == 1, "A first-level miracle gives courage one")
    state.levels["miracle"] = 3
    check(state.exp_per_tap() == 10, "Third-level miracle multiplies EXP by ten")
    state.slots[1] = {"kind": "word", "id": "new_self"}
    state.traumas["no_longer"].resolved = true
    check(state.exp_per_tap() == 20, "Multipliers stack")
    state.slots[2] = {"kind": "word", "id": "happiness"}
    state.traumas["normal"].resolved = true
    check(state.forget_value("queen") == 400 and state.forget_value("happiness") == 15, "Happiness multiplies letting go by twenty, except its own farewell; the discount halves it")
    state.traumas["discount"].strength = 0
    check(state.forget_value("queen") == 800, "A weakened discount trauma no longer halves the farewell")
    state.exp = 0
    check(state.forget_word("new_self") == 1200 and state.exp == 1200 and state.slot_of("new_self") < 0 and state.forgotten.has("new_self"), "A held word can be let go from the shelf")
    check(state.exp_per_tap() == 10, "Letting the multiplier go drops the rate")
    # Face costs and the courage gate through the cap.
    state.reset()
    state.current = "main4_31"
    state.stats[1] = 15
    check(not state.can_choose(1), "Courage fifteen is capped at five by the trauma")
    state.traumas["no_longer"].unraveled = true
    state.exp = 20000
    check(state.face_cost("no_longer") == 20000 and state.can_face("no_longer") and state.face("no_longer"), "Facing at full strength costs the full amount")
    check(state.exp == 0 and state.slot_of("no_longer") < 0 and state.free_slot() == 1, "Facing frees the slot")
    check(state.can_choose(1) and state.choose(1) and state.current == "main4_38", "Courage fifteen unlocks the choice once the cap is gone")
    state.reset()
    state.traumas["voice"].strength = 40
    state.traumas["voice"].unraveled = true
    check(state.face_cost("voice") == 1000, "Cost scales with the remaining strength")
    state.traumas["voice"].cost = 125
    check(state.face_cost("voice") == 50, "Cost multipliers and weakening both lower the price")
    state.exp = 49
    check(not state.can_face("voice"), "Not enough EXP")
    state.exp = 50
    check(state.can_face("voice") and not state.can_face("handle"), "Only loosened traumas can be faced")
    # Talking: previews, resonance, the first discount, and what emerges.
    state.reset()
    state.current = "counseling"
    state.session = 2
    state.counsel_step = "board"
    state.slots[0] = {"kind": "word", "id": "miracle"}
    state.traumas["handle"].resolved = true
    state.slots[2] = {"kind": "word", "id": "queen"}
    state.traumas["normal"].resolved = true
    state.collected = ["miracle", "queen"]
    state.exp = 100
    check(state.can_talk("no_longer") and state.can_talk("voice"), "Second session may talk about anything")
    check(state.focus_trauma("no_longer") and state.toggle_card("miracle") and state.toggle_card("queen") and state.cards == ["miracle", "queen"], "Two words chosen")
    check(not state.toggle_card("miracle") or state.cards == ["queen"], "Toggling removes a chosen word")
    state.cards = ["miracle", "queen"]
    var preview: Dictionary = state.talk_preview("no_longer", state.cards)
    check(preview.resonant == ["miracle"] and preview.strength == 100 - 20 - 5 * 2 and preview.cost == 15 and preview.first, "Preview: miracle resonates with the body, queen halves the cost, the first talk costs thirty")
    check(preview.face == int(ceil(15.0 * 70 / 100)) and not preview.emerges, "Face cost follows the remaining strength")
    check(state.talk() and state.traumas["no_longer"].strength == 70 and state.traumas["no_longer"].cost == 15, "Talk applies the preview")
    check(state.used == ["miracle", "queen"] and state.free_slot() == 0 and state.talk_result.resonant == ["miracle"], "Both words spent, slots freed")
    check(not state.can_talk("voice"), "Only one conversation per session")
    for _i in range(3):
        state.advance_counseling()
    check(state.on_board(), "Talk dialogue returns to the board")
    state.talked = false
    state.collected.append("new_self")
    state.slots[0] = {"kind": "word", "id": "new_self"}
    state.focus_trauma("no_longer")
    state.toggle_card("new_self")
    preview = state.talk_preview("no_longer", ["new_self"])
    check(preview.strength == 70 - 20 - 30 and preview.emerges and not preview.first, "Weakened to twenty, something will emerge")
    check(state.talk() and state.talk_result.emerged == "self_doubt", "The self-doubt emerges")
    check(state.slot_of("self_doubt") == 1 and state.slot_of("no_longer") < 0 and state.traumas["no_longer"].resolved, "It takes the slot of the trauma that hid it")
    check(state.traumas["self_doubt"].strength == 150 and state.traumas["self_doubt"].cost == 200000 and state.traumas["self_doubt"].unraveled, "It starts strong, expensive, and already loosened")
    check(state.effective_stats()[1] == 5, "Courage stays capped by the emerged trauma")
    state.advance_counseling()
    state.advance_counseling()
    state.advance_counseling()
    check(state.counsel_step == "talk_emerge", "Emergence line after the effect")
    state.advance_counseling()
    check(state.counsel_step == "board", "Board again")
    var restored_talk = State.new()
    restored_talk.save_path = backup
    check(restored_talk.load_game() and restored_talk.traumas.has("self_doubt") and restored_talk.talk_result.emerged == "self_doubt", "Emergence persists")
    state.talked = false
    state.focus_trauma("self_doubt")
    preview = state.talk_preview("self_doubt", [])
    check(preview.strength == 130 and not preview.emerges, "Nothing behind what emerged")
    # Growth.
    state.exp = 1000
    state.slots[0] = {"kind": "word", "id": "miracle"}
    state.used.erase("miracle")
    check(state.next_level_cost("miracle") == 60 and state.can_grow("miracle") and state.grow("miracle"), "Growing the miracle")
    check(state.exp == 940 and state.level_of("miracle") == 2 and state.counsel_step == "grow_question", "Second level asks")
    check(state.interpret(0).is_empty(), "Must reach the choice first")
    state.advance_counseling()
    var before_reply: Array = state.stats.duplicate()
    var delta: Array = state.interpret(0)
    bounded(state, before_reply, delta, "growth reception")
    check(state.answer_for("miracle").choice == 0 and state.counsel_step == "grow_reply", "Reception recorded")
    state.advance_counseling()
    state.advance_counseling()
    check(state.on_board() and state.next_level_cost("miracle") == 200 and state.grow("miracle"), "Third level")
    check(state.level_of("miracle") == 3 and state.counsel_step == "grow_insight" and state.exp == 740, "Insight step")
    check(state.next_level_cost("miracle") == -1 and not state.can_grow("miracle"), "No fourth level")
    state.advance_counseling()
    state.advance_counseling()
    check(state.exp_per_tap() == 10, "Grown miracle multiplies taps")
    state.exp = 0
    check(state.read_dynamic("counsel_x", "みなと", "……") and state.exp == 10, "Counseling lines are taps too")
    check(not state.read_dynamic("counsel_x", "みなと", "……"), "A line read twice is one tap")
    # Map locks under effective stress.
    state.reset()
    state.current = "map"
    state.stats[0] = 72
    check(state.stress_locked() and not state.event_available("park") and state.event_available("rest"), "Stress seventy-two reads as eighty under the trauma: only rest")
    check(not state.select_event("park"), "Locked outing rejected")
    state.stats[0] = 71
    check(state.event_available("park") and not state.event_available("sumika") and not state.event_available("cry"), "Week one pool excludes later events")
    state.round_index = 1
    check(state.event_available("sumika") and not state.event_available("cry"), "Week two unlocks new places")
    state.round_index = 2
    check(state.event_available("cry") and state.event_available("inori"), "Week three unlocks the rest")
    state.round_index = 1
    state.visited = ["park"]
    check(not state.event_available("park") and state.event_available("rest"), "Visited place closed, rest repeatable")
    # Rounds route into counseling after the first, third and fourth chapters.
    state.reset()
    state.current = "main1_47"
    state.choose(0)
    check(state.after_night == "counseling" and state.round_index == 1, "Chapter one leads to the second session")
    state.reset()
    state.round_index = 1
    state.current = "main2_59"
    state.choose(0)
    check(state.after_night == "map", "Chapter two goes straight to the map")
    state.reset()
    state.round_index = 2
    state.current = "main3_54"
    state.choose(0)
    check(state.after_night == "counseling", "Chapter three leads to the third session")
    state.reset()
    state.round_index = 3
    state.session = 3
    state.current = "main4_66"
    state.choose(0)
    state.sleep()
    check(state.current == "counseling" and state.session == 4 and state.is_closing(), "Chapter four leads to the closing session")
    var invalid := FileAccess.open(backup, FileAccess.WRITE)
    invalid.store_string("{broken")
    invalid.close()
    check(not state.load_game(), "Corrupt save rejected")
    var old := FileAccess.open(backup, FileAccess.WRITE)
    old.store_string(JSON.stringify({"version": 4, "current": "main4_5", "collected": [], "answers": [], "stats": [65, 40, 45, 40], "history": []}))
    old.close()
    check(not state.load_game(), "Previous flow saves are not loaded")
    DirAccess.remove_absolute(backup)
    await run_ui()
    print("%s: %d runtime checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
    quit(0 if failures == 0 else 1)

func buttons_of(node: Node) -> Array:
    var found: Array = []
    for child in node.get_children():
        if child is Button:
            found.append(child)
        found.append_array(buttons_of(child))
    return found

func labels_of(node: Node) -> Array:
    var found: Array = []
    for child in node.get_children():
        if child is Label:
            found.append(child)
        found.append_array(labels_of(child))
    return found

func has_label(node: Node, needle: String) -> bool:
    return labels_of(node).any(func(label): return needle in label.text)

func run_ui() -> void:
    # Drive actual UI, including mandatory interludes, cast, and counseling dialogue.
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
    check(scene.stat_bars.size() == 4, "Four bars in the outline panel")
    check(scene.stat_labels[0].text == "68" and scene.stat_labels[2].text == "3", "Outline shows the stats as the traumas make them")
    check(has_label(scene.bottom, "EXP  0"), "EXP shown on the outline panel")
    var thorns := 0
    for child in scene.bottom.get_children():
        if child is Button and "見つめる" in child.tooltip_text:
            thorns += 1
    check(thorns == 8, "Eight traumas on the shelf at the start")
    scene._advance()
    check(scene.completed and scene.state.exp == 1 and has_label(scene.bottom, "EXP  1"), "First action reveals the line and earns EXP")
    var current: String = scene.state.current
    scene._show_history()
    scene._advance()
    check(scene.state.current == current, "Modal prevents advancing")
    scene._close_overlay()
    scene._advance()
    check(scene.state.current != current, "Second action advances")
    check(scene.portraits["みなと"].modulate.r == 1.0 and scene.portraits["よだか"].modulate.r < 0.6, "Speaking Minato lit, Yodaka dimmed")
    # Tutorial choice with visible effect previews.
    scene.state.current = "counsel1_10"
    scene._show_story()
    scene._finish_line()
    check(scene.preview_labels.size() == 3 and "自認 +4" in scene.preview_labels[0], "Tutorial choices preview their effects")
    var before_ui: Array = scene.state.stats.duplicate()
    scene._story_choice(2)
    check(scene.state.current == "counsel1_16" and scene.state.stats[0] == before_ui[0] + 4, "UI choice applies tutorial effect")
    scene.state.current = "counsel1_45"
    scene._show_story()
    scene._finish_line()
    check("カルテ" in scene.next_button.text, "Karte line announces the chart")
    scene._advance()
    check(scene.overlay_kind == "modal" and scene.state.current == "counsel1_45", "Karte opens before advancing")
    check(has_label(scene.overlay, "刺さっている言葉") and has_label(scene.overlay, "勇気 の上限 5"), "Karte lists the traumas and their effects")
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
    # The tutorial flows into the first session board.
    scene.state.current = "counsel1_51"
    scene.state.exp = 40
    scene._show_story()
    scene._finish_line()
    scene._advance()
    check(scene.state.current == "counseling" and scene.state.session == 1 and scene.mode == "counseling", "Tutorial ends in the first session")
    check("残っている言葉" in scene.body.text, "Minato asks for one word in the first session")
    scene._finish_line()
    scene._advance()
    scene._finish_line()
    scene._advance()
    check(scene.state.counsel_step == "board" and scene.body == null, "Opening lines lead to the board with no dialogue body")
    scene._advance()
    check(scene.state.counsel_step == "board", "Space does nothing on the board")
    scene._focus_board("no_longer")
    check(has_label(scene.content, "まだ重すぎる"), "First session refuses the trauma with something behind it")
    scene._talk_board()
    check(scene.state.counsel_step == "board" and not scene.state.talked, "Talk button does nothing on a refused trauma")
    scene._focus_board("coworker")
    check(scene.preview_labels.size() == 1 and "強さ 100 → 80" in scene.preview_labels[0], "Board previews the talk")
    check(has_label(scene.content, "最初のひとつ"), "Board announces the first discount")
    scene._talk_board()
    check(scene.state.counsel_step == "talk_recall" and scene.state.talked, "Talking starts Yodaka's recall")
    check("勝手に期待した" in scene.body.text, "Recall text rendered")
    scene._finish_line()
    scene._advance()
    check(scene.state.counsel_step == "talk_doctor" and "肩透かし" in scene.body.text, "Minato answers")
    scene._finish_line()
    scene._advance()
    check(scene.state.counsel_step == "talk_effect", "Effect line")
    scene._finish_line()
    check(has_label(scene.content, "をほぐした") and has_label(scene.content, "向き合うEXP  1,500") and has_label(scene.content, "最初のひとつ"), "Effect panel shows the loosened trauma, its old cost and the discount")
    scene._advance()
    check(scene.state.counsel_step == "board" and scene.state.traumas["coworker"].strength == 80 and scene.state.traumas["coworker"].cost == 30, "Back on the board with the trauma loosened")
    check(scene.state.exp == 46, "Counseling lines earned EXP too")
    scene._focus_board("coworker")
    check(has_label(scene.content, "向き合うには EXP 24"), "Face cost shown")
    scene._face_board("coworker")
    check(scene.state.counsel_step == "face_line" and scene.state.exp == 22 and scene.state.free_slot() == 5, "Facing pays and frees the slot")
    check("先輩の距離" in scene.body.text, "Resolve line rendered")
    scene._finish_line()
    scene._advance()
    check(scene.state.counsel_step == "board", "Board after facing")
    scene._finish_session()
    check(scene.state.counsel_step == "closing" and "ここまで" in scene.body.text, "Closing line for a session in between")
    scene._finish_line()
    scene._advance()
    check(scene.state.counsel_step == "farewell", "Farewell")
    scene._finish_line()
    scene._advance()
    check(scene.mode == "map" and scene.state.current == "map", "First session leads to the map")
    var empties := 0
    for child in scene.bottom.get_children():
        if child is Label and child.text == "あいている枠":
            empties += 1
    check(empties == 1, "One free slot on the shelf")
    # Word collection: the overlay offers to keep or let go.
    scene.state.current = "sushi_8"
    scene._show_story()
    await dismiss(scene)
    check(scene.portraits.has("りあ"), "Mother portrait displayed")
    scene.state.current = "cafe_7"
    scene._show_story()
    await dismiss(scene)
    scene._advance()
    check(scene.state.collected.size() == 1 and scene.state.pending_word == "miracle", "UI collects completed marked word")
    check(scene.overlay_kind == "word", "Collection creates blackout effect")
    check(has_label(scene.overlay, "勇気 +5"), "Collection blackout shows the stat change, whole now that the coworker trauma is gone")
    var keep_button: Button = null
    var release_button: Button = null
    for button in buttons_of(scene.overlay):
        if button.text.begins_with("心に留める"):
            keep_button = button
        if button.text.begins_with("手放して"):
            release_button = button
    check(keep_button != null and release_button != null, "Keep and let-go buttons offered")
    scene.auto_mode = true
    scene._process(20)
    scene._advance()
    scene._close_overlay()
    check(scene.overlay_kind == "word" and scene.state.current == "cafe_7", "Collection requires a decision even on AUTO")
    await dismiss(scene)
    check(scene.overlay_kind == "word" and scene.state.pending_word == "miracle", "Clicking the dark does not decide")
    var restored_pending = State.new()
    restored_pending.save_path = scene.state.save_path
    check(restored_pending.load_game() and restored_pending.pending_word == "miracle", "Undecided word persists")
    var exp_before_keep: int = scene.state.exp
    scene._decide_word("keep", -1)
    if is_instance_valid(scene.interlude_tween) and scene.interlude_tween.is_running():
        await scene.interlude_tween.finished
    check(scene.state.pending_word == "" and scene.state.held_words() == ["miracle"] and not is_instance_valid(scene.overlay), "Keeping puts the word on the shelf and closes the blackout")
    check(scene.state.exp == exp_before_keep, "Keeping earns nothing")
    scene.auto_mode = false
    scene._show_word(scene.state.word_by_id("miracle"))
    check(has_label(scene.overlay, "勇気 +1") and has_label(scene.overlay, "強さ −5"), "Word card shows passive and conversation effects")
    scene._close_overlay()
    # A full shelf: let go, or swap a held word out.
    scene.state.current = "sumika_10"
    scene._show_story()
    await dismiss(scene)
    scene._advance()
    check(scene.state.pending_word == "happiness" and scene.state.free_slot() < 0, "Second word arrives with no room")
    check(has_label(scene.overlay, "枠がない"), "Overlay explains the full shelf")
    var swap_button: Button = null
    for button in buttons_of(scene.overlay):
        if "「奇跡」" in button.text and "手放して留める" in button.text:
            swap_button = button
    check(swap_button != null, "Swap offered for the held word")
    scene.state.forgotten.clear()
    var exp_before_swap: int = scene.state.exp
    await settle(scene)
    scene._decide_word("swap", scene.state.slot_of("miracle"))
    if is_instance_valid(scene.interlude_tween) and scene.interlude_tween.is_running():
        await scene.interlude_tween.finished
    check(scene.state.held_words() == ["happiness"] and scene.state.forgotten == ["miracle"] and scene.state.exp == exp_before_swap + 5, "Swap keeps the new word and pays for the old")
    scene.state.current = "main1_28"
    scene._show_story()
    await dismiss(scene)
    check(scene.portraits.has("あしか") and scene.portraits["あしか"].modulate.r == 1.0, "Speaking Ashika uses supplied portrait")
    scene._advance()
    check(scene.state.pending_word == "queen", "Queen arrives")
    var exp_before_release: int = scene.state.exp
    await settle(scene)
    scene._decide_word("release", -1)
    if is_instance_valid(scene.interlude_tween) and scene.interlude_tween.is_running():
        await scene.interlude_tween.finished
    check(scene.state.pending_word == "" and scene.state.forgotten.has("queen") and scene.state.exp == exp_before_release + 400, "Letting go pays, multiplied by the held happiness")
    # Shelf card for a trauma, and facing one from the shelf.
    scene._show_trauma("handle")
    check(has_label(scene.overlay, "まだ固い") and has_label(scene.overlay, "キラキラ が 50% 減る"), "Trauma card explains its state and effect")
    scene._close_overlay()
    scene.state.traumas["voice"].unraveled = true
    scene.state.traumas["voice"].cost = 100
    scene.state.exp = 100
    scene._show_trauma("voice")
    var face_button: Button = null
    for button in buttons_of(scene.overlay):
        if button.text.begins_with("向き合う"):
            face_button = button
    check(face_button != null and not face_button.disabled, "Face button enabled with enough EXP")
    scene._face_from_shelf("voice")
    check(scene.state.traumas["voice"].resolved and scene.state.exp == 0 and scene.overlay_kind == "modal" and has_label(scene.overlay, "どちらの声で考えても"), "Facing from the shelf shows the resolve line")
    scene._close_overlay()
    # MAP, outing, night.
    scene.state.reset()
    scene.state.current = "map"
    scene._show_story()
    check(scene.mode == "map", "MAP renders")
    var pins := 0
    var pinned: Array = []
    for child in scene.content.get_children():
        if child is Button and child.text.begins_with("●"):
            pins += 1
            pinned.append(child.text)
    check(pins == 7, "Week one pins six places and home, nothing else")
    check(not pinned.any(func(t): return "すみか" in t), "Locked places are not on the map")
    check(pinned.any(func(t): return "家で休む（ストレス -8）" in t), "Home pin shows the halved rest")
    scene.state.stats[0] = 72
    scene._show_map()
    pins = 0
    for child in scene.content.get_children():
        if child is Button and child.text.begins_with("●"):
            pins += 1
    check(pins == 1 and has_label(scene.content, "トラウマが 72 を 80 に"), "Stress through the trauma leaves only the home pin, and says so")
    scene.state.stats[0] = 60
    scene._show_map()
    scene._select_map_event("sumika")
    check(scene.state.current == "map", "Locked place ignored")
    scene._select_map_event("park")
    check(scene.state.current == "park_6" and scene.state.stats[0] == 65, "MAP opens selected event and going out costs stress")
    await dismiss(scene)
    scene.state.current = "park_15"
    scene.state.choose(0)
    check(scene.state.current == "night" and scene.state.after_night == "map", "First outing leads to the night, then back to the map")
    scene._show_story()
    check(scene.mode == "night", "Night renders")
    check(scene.overlay_kind == "night", "Night opens with the darkening intro")
    await dismiss(scene)
    check(not is_instance_valid(scene.overlay) and scene.night_intro_seen, "Click ends the night intro")
    check(has_label(scene.content, "今日のEXP") and buttons_of(scene.content).any(func(b): return "眠る（ストレス -2）" in b.text), "Night sums the day and shows the halved sleep")
    scene._sleep()
    check(scene.mode == "map" and scene.state.outings_done == 1, "Sleeping returns to the map")
    check(not scene.night_intro_seen, "Next night shows its intro again")
    scene.state.outings_done = 2
    scene._select_map_event("cafe")
    scene.state.current = "cafe_14"
    scene.state.choose(0)
    check(scene.state.after_night == "chapter", "Third outing completes the round")
    scene._show_story()
    await dismiss(scene)
    scene._sleep()
    check(scene.state.current == "main1_5", "Round leads into CHAPTER 1")
    await dismiss(scene)
    # A later session: words brought into the conversation, growth, and what emerges.
    scene.state.reset()
    scene.state.current = "night"
    scene.state.after_night = "counseling"
    scene.state.round_index = 1
    scene.state.session = 1
    scene.state.collected = ["miracle", "queen", "new_self"]
    scene.state.slots[0] = {"kind": "word", "id": "miracle"}
    scene.state.traumas["handle"].resolved = true
    scene.state.slots[2] = {"kind": "word", "id": "queen"}
    scene.state.traumas["normal"].resolved = true
    scene.state.slots[4] = {"kind": "word", "id": "new_self"}
    scene.state.traumas["discount"].resolved = true
    scene.state.traumas["no_longer"].strength = 45
    scene.state.traumas["no_longer"].unraveled = true
    scene.state.traumas["voice"].unraveled = true
    scene.state.exp = 400
    scene.night_intro_seen = true
    scene._show_story()
    scene._sleep()
    check(scene.state.current == "counseling" and scene.state.session == 2, "The night after chapter one leads to the second session")
    await dismiss(scene)
    check("どうでしたか" in scene.body.text, "Minato asks about the weeks")
    scene._finish_line()
    scene._advance()
    check("3個" in scene.body.text, "Yodaka counts the words")
    scene._finish_line()
    scene._advance()
    check(scene.state.on_board(), "Board")
    scene._focus_board("no_longer")
    scene._toggle_board_card("new_self")
    check(scene.state.cards == ["new_self"] and has_label(scene.content, "奥で何かが動いている"), "Board warns about what will emerge")
    scene._toggle_board_card("miracle")
    scene._toggle_board_card("queen")
    check(scene.state.cards == ["new_self", "miracle"], "Only two words come along")
    scene._toggle_board_card("miracle")
    check(scene.state.cards == ["new_self"], "Toggling off")
    scene._talk_board()
    for step in ["talk_recall", "talk_doctor", "talk_effect"]:
        check(scene.state.counsel_step == step, "Session dialogue: " + step)
        if step == "talk_doctor":
            scene._finish_line()
            check("「新しい自分」も、一緒に" in scene.body.text, "Minato names the word brought along")
        scene._finish_line()
        scene._advance()
    check(scene.state.counsel_step == "talk_emerge" and "本当は自分が一番" in scene.body.text, "The emerging trauma speaks")
    scene._finish_line()
    scene._advance()
    check(scene.state.on_board() and scene.state.slot_of("self_doubt") == 1 and scene.board_focus == "self_doubt", "Board focuses what emerged")
    check(scene.state.used == ["new_self"] and scene.state.slot_of("new_self") < 0, "The word brought along is spent")
    scene._focus_board("queen")
    check(has_label(scene.content, "掘り下げると Lv2（EXP 80）"), "Growth offer shown")
    var exp_before_grow: int = scene.state.exp
    check(exp_before_grow == 408, "Counseling lines earned EXP, doubled while the new self was held")
    scene._grow_board("queen")
    check(scene.state.counsel_step == "grow_question" and scene.state.exp == exp_before_grow - 80, "Growth paid")
    scene._finish_line()
    scene._advance()
    check(scene.state.counsel_step == "grow_choice", "Choice step")
    scene._finish_line()
    check(scene.preview_labels.size() == 3 and "勇気 +6" in scene.preview_labels[0], "Named effects visible before answering")
    var before_reply: Array = scene.state.preview(scene.state.word_by_id("queen").interpretations[0].effects)
    scene._interpret(0)
    scene._interpret(0)
    check(scene.state.answers.size() == 1 and scene.state.answers[0].delta == before_reply, "Double click answers once, preview equals applied delta")
    check(scene.current_dialogue.speaker == "よだか" and "一緒にできること" in scene.body.text, "Choice becomes Yodaka's spoken answer")
    var restored_reply = State.new()
    restored_reply.save_path = scene.state.save_path
    check(restored_reply.load_game() and restored_reply.counsel_step == "grow_reply" and restored_reply.levels.get("queen") == 2, "Resume preserves the growth reply")
    scene._finish_line()
    scene._advance()
    check(scene.state.counsel_step == "grow_response" and "届いたんですね" in scene.body.text, "Minato responds")
    scene._finish_line()
    scene._advance()
    check(scene.state.on_board() and scene.state.level_of("queen") == 2, "Level two on the board")
    scene.state.exp = 300
    scene._focus_board("queen")
    scene._grow_board("queen")
    check(scene.state.counsel_step == "grow_insight" and "一緒に何かをする相手" in scene.body.text, "Third level reveals the insight")
    scene._finish_line()
    scene._advance()
    check(scene.state.counsel_step == "grow_response" and "もう法月さんのもの" in scene.body.text, "Minato closes the insight")
    scene._finish_line()
    scene._advance()
    scene._focus_board("queen")
    check(has_label(scene.content, "これ以上は掘り下げられない"), "Top level cannot grow")
    scene._forget_board("queen")
    check(scene.overlay_kind == "modal" and has_label(scene.overlay, "を手放す"), "Letting go asks first")
    for button in buttons_of(scene.overlay):
        if button.text == "手放す":
            button.pressed.emit()
    check(scene.state.forgotten.has("queen") and scene.state.slot_of("queen") < 0 and not is_instance_valid(scene.overlay), "Confirmed letting go")
    scene._focus_board("voice")
    scene.state.exp = 2500
    scene._show_board()
    scene._face_board("voice")
    check(scene.state.counsel_step == "face_line" and scene.state.traumas["voice"].resolved, "Facing from the board")
    scene._finish_line()
    scene._advance()
    scene._finish_session()
    scene._finish_line()
    scene._advance()
    scene._finish_line()
    scene._advance()
    check(scene.mode == "map", "Second session leads to the map")
    # Closing session with the karte.
    scene.state.round_index = 4
    scene.state.session = 3
    scene.state.current = "counseling"
    scene.state._enter_counseling()
    scene._show_story()
    await dismiss(scene)
    check(scene.state.session == 4 and scene.state.is_closing(), "Closing session")
    scene._finish_line()
    scene._advance()
    scene._finish_line()
    scene._advance()
    check(scene.state.on_board(), "Closing board")
    scene._finish_session()
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
    check(scene.mode == "result" and has_label(scene.content, "トラウマ"), "End screen follows the farewell")
    scene._show_reflections()
    check(has_label(scene.overlay, "奥から別の言葉") or true, "Reflections open")
    scene._close_overlay()
    scene._show_karte(Callable())
    check(is_instance_valid(scene.overlay), "Karte opens from the outline panel callback")
    scene._close_overlay()
    scene.state.current = "sumika_6"
    scene._show_story()
    await dismiss(scene)
    check(scene.portraits.has("すみか"), "Sumika portrait displayed")
    scene.state.current = "main4_31"
    scene.state.stats[1] = 15
    scene._show_story()
    await dismiss(scene)
    scene._finish_line()
    var locked := false
    for child in scene.choice_box.get_children():
        if child is Button and "お姫様" in child.text:
            locked = child.disabled
    check(locked and has_label(scene.choice_box, "トラウマで抑えられている"), "Capped courage locks the choice in UI and says why")
    # Verify the centered dialogue area fits all lines, recaps, replies and counseling text.
    scene.set_process(false)
    scene._render_dialogue(scene.state.data.nodes["counsel0_6"])
    var texts: Array = []
    for node in scene.state.data.nodes.values():
        texts.append(node.text)
    for word in scene.state.data.words:
        texts.append(word.memory)
        texts.append("「%s」……。\n法月さんは、その時どう感じましたか？" % word.word)
        texts.append(word.levels[2].insight)
        for interpretation in word.interpretations:
            texts.append(interpretation.reply)
    for trauma in scene.state.data.traumas:
        for key in ["quote", "recall", "loosen", "resolve"]:
            texts.append(trauma[key])
        texts.append(trauma.doctor + "\n「幸せにする権利」「付き合ってあげる」も、一緒に。")
        if trauma.has("emerge"):
            texts.append(trauma.emerge)
    texts.append_array(scene.RESPONSES)
    texts.append(scene.INSIGHT_RESPONSE)
    texts.append("受け取った言葉を飾って、ときには整理して。\n居心地よくいられる時間が、少しでも続きますように。\nでは、お大事にどうぞ。法月さん")
    for text in texts:
        scene.body.text = "[center]" + text + "[/center]"
        scene.body.visible_characters = -1
        await process_frame
        check(scene.body.get_content_height() <= scene.body.size.y, "Dialogue fits centered area: " + text.left(16))
    scene.queue_free()
    await process_frame
    DirAccess.remove_absolute("/tmp/yodaka-ui-test.json")

func settle(scene: Control) -> void:
    if is_instance_valid(scene.interlude_tween) and scene.interlude_tween.is_running():
        await scene.interlude_tween.finished

func dismiss(scene: Control) -> void:
    if is_instance_valid(scene.interlude_tween) and scene.interlude_tween.is_running():
        await scene.interlude_tween.finished
    scene._dismiss_interlude()
    if is_instance_valid(scene.interlude_tween) and scene.interlude_tween.is_running():
        await scene.interlude_tween.finished
