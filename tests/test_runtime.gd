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
        check((state.trauma_state(id) == "accepted") != (state.slot_of(id) >= 0), label + ": accepted traumas leave the shelf, the rest stay: " + id)
    for id in state.held_words():
        check(state.collected.has(id) and not state.forgotten.has(id), label + ": held words were received and not let go")
    for id in state.forgotten:
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
    # Open one mystery, if any can be afforded.
    var mysteries: Array = state.held_traumas().filter(func(id): return state.trauma_state(id) == "mystery")
    var affordable: Array = mysteries.filter(func(id): return state.can_appraise(id))
    if not affordable.is_empty():
        var target: String = affordable[(selection + session) % affordable.size()]
        var exp_before: int = state.exp
        check(state.appraise(target), "Talking opens a mystery")
        check(state.exp == exp_before - state.appraise_cost(target) and state.trauma_state(target) == "appraised", "Opening costs EXP and changes the state")
        check(state.talked and not state.can_appraise(mysteries[0]), "One conversation per session")
        check(state.counsel_step == "talk_recall", "Yodaka recalls the opened trauma")
        state.advance_counseling()
        check(state.counsel_step == "talk_doctor", "Minato answers")
        state.advance_counseling()
        check(state.counsel_step == "board", "Back to the board")
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
    # Face whatever is affordable.
    for id in state.held_traumas():
        if state.can_face(id):
            var cost: int = state.face_cost(id)
            var exp_before: int = state.exp
            check(state.face(id), "Facing an affordable trauma")
            check(state.exp == exp_before - cost and state.trauma_state(id) == "accepted" and state.slot_of(id) < 0, "Facing spends EXP and frees the slot")
            check(state.counsel_step == "face_line", "Facing has Yodaka's line")
            state.advance_counseling()
            check(state.counsel_step == "face_response", "Then Minato's")
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
    check(state.data.traumas.size() == 6 and state.data.slots == State.SLOTS, "Six traumas, eight slots")
    for selection in range(3):
        state.reset()
        check(state.current == "counsel0_6", "Prototype opens in the counseling room")
        check(state.held_traumas().size() == 6 and state.free_slot() == 6, "Six mysteries and two free slots")
        for id in state.traumas:
            check(state.trauma_state(id) == "mystery", "Every trauma starts as a mystery")
        check(state.effective_stats() == [64, 5, 5, 4], "Mysteries already bite: stress plus four, courage capped at twelve, a quarter off sparkle")
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
            check(count == state.collected.size() and stats_after == state.stats, "Duplicate collection or effect")
            var choice: int = selection % node.choices.size() if node.has("choices") else 0
            if not state.can_choose(choice):
                choice = 0
            var was_outing: bool = node.get("kind") == "outing" and node.next == "night"
            var was_main: bool = node.get("kind") == "main" and node.next == "night"
            var stress: int = state.stats[0]
            check(state.choose(choice), "Available choice advances")
            check(state.current != "night", "There is no night: the day ends into the next place")
            if not node.has("choices"):
                check(state.stats[0] == stress, "Moving on costs no stress by itself")
            if was_outing:
                check(state.current == "map" or state.current.begins_with("main"), "An outing leads to the map or into a chapter")
            if was_main:
                check(state.current in ["map", "counseling"], "A chapter leads to the map or a session")
        check(chapters.size() == 4 and chapters[0] == "tiktokの女王" and chapters[3] == "溺れる海のあしか", "Four main chapters in order")
        check(outings == 12, "Twelve outings across the rounds")
        check(sessions == [1, 2, 3, 4], "Four counseling sessions: opening, two between, closing")
        check(state.session == State.SESSIONS, "Closing session is the fourth")
        var opened: int = state.traumas.values().filter(func(t): return t.state != "mystery").size()
        check(opened >= 1, "At least one mystery was opened")
        check(state.collected.size() >= 3 and state.collected.size() <= state.data.words.size(), "Words received across outings and chapters: %d" % state.collected.size())
        check(state.exp_total >= state.read_count, "EXP total covers every tap at least once")
        print("Strategy %d: %d received, %d held, %d let go, %d opened, %d accepted, EXP %d/%d, taps %d, stats %s, effective %s" % [selection, state.collected.size(), state.held_words().size(), state.forgotten.size(), opened, state.accepted_count(), state.exp, state.exp_total, taps, state.stats, state.effective_stats()])
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
        check(restored.exp == state.exp and restored.exp_total == state.exp_total, "EXP persisted")
    # Immediate effects: words, tutorial choices, and resting, under the starting mysteries.
    state.reset()
    state.current = "cafe_7"
    var before_word: Array = state.stats.duplicate()
    check(state.debuff_active("gain_half"), "The coworker mystery halves what words give")
    check(state.finish_line(), "Marked line collects a word")
    check(state.stats[1] == before_word[1] + 3 and state.stats[2] == before_word[2] + 1, "Receiving a word changes stats at once, halved by the trauma")
    check(state.gains["miracle"] == [0, 3, 1, 0], "Collection delta recorded")
    check(state.pending_word == "miracle" and state.free_slot() == 6 and state.keep_pending(), "Two free slots take the first word")
    check(state.held_words() == ["miracle"] and state.effective_stats()[1] == 9, "A held first-level miracle gives courage one")
    state.current = "sumika_10"
    state.finish_line()
    check(state.forget_value("happiness") == 15, "Letting go pays the base halved by the discount mystery")
    check(state.release_pending() == 15 and state.forgotten == ["happiness"], "Let go for EXP")
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
    state.current = "bridge_10"
    var before_hurt: int = state.stats[0]
    state.finish_line()
    check(state.stats[0] == before_hurt + 5 and state.last_delta == [5, 0, 0, 0], "A line that hurts raises stress")
    state.finish_line()
    check(state.stats[0] == before_hurt + 5, "Only once per line")
    state.current = "rest_2"
    var before_rest: int = state.stats[0]
    state.finish_line()
    check(state.stats[0] == before_rest - 8, "Resting at home recovers only half under the mother's words")
    check(state.choose(0) and state.current == "map" and state.outings_done == 1, "Rest counts as an outing and leads straight back to the map")
    # Debuffs by state: a mystery bites, an opened trauma bites harder, an accepted one is gone.
    state.reset()
    state.stats = [50, 20, 40, 40]
    check(state.effective_stats() == [54, 12, 40, 30], "Mysteries: stress plus four, courage capped at twelve, a quarter off sparkle")
    state.traumas["normal"].state = "appraised"
    state.traumas["no_longer"].state = "appraised"
    state.traumas["handle"].state = "appraised"
    check(state.effective_stats() == [62, 5, 40, 20], "Opened: stress plus twelve, courage capped at five, half off sparkle")
    check(state.debuff_text("handle") == "キラキラ が 50% 減る" and state.debuff_text("no_longer") == "勇気 の上限 5" and state.debuff_text("normal") == "ストレス 常時 +12", "Debuffs described")
    state.traumas["normal"].state = "accepted"
    state.slots[state.slot_of("normal")] = {}
    check(state.effective_stats()[0] == 50, "Accepted traumas no longer bite")
    check(state.debuff_active("rest_half") and state.debuff_active("forget_half") and state.debuff_active("gain_half"), "Flag debuffs hold while the traumas sit on the shelf")
    # Facing costs: held words cut them, twice when the kind matches.
    state.reset()
    state.collected = ["miracle", "queen", "company", "new_self"]
    check(state.face_cost("coworker") == 1500 and state.face_cost("no_longer") == 20000, "Full prices without words")
    state.slots[6] = {"kind": "word", "id": "queen"}
    check(state.face_cost("coworker") == 375 and state.face_cost("no_longer") == 10000, "The queen halves it, twice for a trauma of the same kind")
    state.slots[7] = {"kind": "word", "id": "company"}
    check(state.face_cost("coworker") == 188, "Another word halves it again")
    state.levels["queen"] = 3
    check(state.face_cost("coworker") == int(ceil(1500 * 0.25 * 0.25 * 0.5)) and state.exp_per_tap() == 3, "A grown queen cuts deeper and multiplies taps")
    state.slots[7] = {"kind": "word", "id": "happiness"}
    state.collected.append("happiness")
    check(state.forget_value("queen") == 400 and state.forget_value("happiness") == 15, "Happiness multiplies letting go by twenty, except its own farewell; the discount halves it")
    state.exp = 0
    check(state.forget_word("queen") == 400 and state.exp == 400 and state.slot_of("queen") < 0, "A held word can be let go from the shelf")
    # Sessions: opening costs EXP, one per session; facing only when the price is paid.
    state.reset()
    state.current = "counseling"
    state.session = 2
    state.counsel_step = "board"
    state.exp = 10
    check(not state.can_appraise("coworker"), "Twenty EXP needed to open the coworker")
    state.exp = 20
    check(state.can_appraise("coworker") and not state.can_face("coworker"), "Can open, cannot face a mystery")
    check(state.appraise("coworker") and state.exp == 0 and state.trauma_state("coworker") == "appraised", "Opened for twenty")
    check(not state.can_appraise("handle") and state.counsel_step == "talk_recall", "One opening per session")
    state.advance_counseling()
    state.advance_counseling()
    check(state.on_board(), "Talk dialogue returns to the board")
    state.exp = 1499
    check(not state.can_face("coworker"), "Not enough EXP to face")
    state.exp = 1500
    check(state.can_face("coworker") and state.face("coworker"), "Facing at the full price")
    check(state.exp == 0 and state.slot_of("coworker") < 0 and state.free_slot() >= 0 and state.accepted_count() == 1, "Facing frees the slot")
    check(state.counsel_step == "face_line", "Yodaka's line")
    state.advance_counseling()
    check(state.counsel_step == "face_response", "Minato's line")
    state.advance_counseling()
    check(state.on_board(), "Board again")
    state.current = "map"
    state.exp = 100
    check(not state.appraise("handle") and not state.face("handle"), "Nothing opens or is faced outside counseling")
    var restored_face = State.new()
    restored_face.save_path = backup
    check(restored_face.load_game() and restored_face.traumas["coworker"].state == "accepted" and restored_face.slot_of("coworker") < 0, "Accepted trauma persists")
    # Growth.
    state.reset()
    state.current = "counseling"
    state.session = 2
    state.counsel_step = "board"
    state.collected = ["miracle"]
    state.slots[6] = {"kind": "word", "id": "miracle"}
    state.exp = 1000
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
    check(state.exp_per_tap() == 10 and state.face_cost("no_longer") == 200, "Grown miracle multiplies taps and cuts the body trauma to a tenth of a tenth")
    state.exp = 0
    check(state.read_dynamic("counsel_x", "みなと", "……") and state.exp == 10, "Counseling lines are taps too")
    check(not state.read_dynamic("counsel_x", "みなと", "……"), "A line read twice is one tap")
    # Courage gate through the cap.
    state.reset()
    state.current = "main4_31"
    state.stats[1] = 15
    check(not state.can_choose(1), "Courage fifteen is capped at twelve by the mystery")
    state.traumas["no_longer"].state = "accepted"
    state.slots[state.slot_of("no_longer")] = {}
    check(state.can_choose(1) and state.choose(1) and state.current == "main4_38", "Courage fifteen unlocks the choice once the trauma is accepted")
    # Map locks under effective stress.
    state.reset()
    state.current = "map"
    state.stats[0] = 76
    check(state.stress_locked() and not state.event_available("park") and state.event_available("rest"), "Stress seventy-six reads as eighty under the mystery: only rest")
    check(not state.select_event("park"), "Locked outing rejected")
    state.stats[0] = 75
    var before_out: int = state.stats[0]
    check(state.select_event("park") and state.stats[0] == before_out, "Going out costs nothing")
    state.current = "map"
    state.visited.clear()
    check(state.event_available("park") and not state.event_available("sumika") and not state.event_available("cry"), "Week one pool excludes later events")
    state.round_index = 1
    check(state.event_available("sumika") and not state.event_available("cry"), "Week two unlocks new places")
    state.round_index = 2
    check(state.event_available("cry") and state.event_available("inori"), "Week three unlocks the rest")
    state.round_index = 1
    state.visited = ["park"]
    check(not state.event_available("park") and state.event_available("rest"), "Visited place closed, rest repeatable")
    # Rounds route into counseling after the first, third and fourth chapters, with no night between.
    state.reset()
    state.current = "main1_47"
    state.choose(0)
    check(state.current == "counseling" and state.session == 1 and state.round_index == 1, "Chapter one leads straight into the second session")
    state.reset()
    state.round_index = 1
    state.current = "main2_59"
    state.choose(0)
    check(state.current == "map", "Chapter two goes straight to the map")
    state.reset()
    state.round_index = 2
    state.current = "main3_54"
    state.choose(0)
    check(state.current == "counseling", "Chapter three leads to the third session")
    state.reset()
    state.round_index = 3
    state.session = 3
    state.current = "main4_66"
    state.choose(0)
    check(state.current == "counseling" and state.session == 4 and state.is_closing(), "Chapter four leads to the closing session")
    var invalid := FileAccess.open(backup, FileAccess.WRITE)
    invalid.store_string("{broken")
    invalid.close()
    check(not state.load_game(), "Corrupt save rejected")
    var old := FileAccess.open(backup, FileAccess.WRITE)
    old.store_string(JSON.stringify({"version": 5, "current": "main4_5", "collected": [], "answers": [], "stats": [65, 40, 45, 40], "history": []}))
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

func shelf_hits(scene: Control) -> Array:
    return buttons_of(scene.bottom).filter(func(b): return b.flat and b.position.y == 653)

func run_ui() -> void:
    # Drive actual UI, including mandatory interludes, cast, and counseling dialogue.
    var scene = load("res://src/main.tscn").instantiate()
    root.add_child(scene)
    scene.state.save_path = "/tmp/yodaka-ui-test.json"
    scene.state.reset()
    check(has_label(scene.content, "ガールズモード") and has_label(scene.content, "プロト体験版") and not has_label(scene.content, "ことばの標本"), "Title shows the working title only")
    scene._show_story()
    check(scene.overlay_kind == "scene", "Opening counseling card appears")
    var dark: Panel = null
    for child in scene.overlay.get_children():
        if child is Panel:
            dark = child
            break
    check(dark != null and dark.size == scene.FRAME.size and dark.position == scene.FRAME.position, "Only the frame above the buttons goes dark")
    check(scene.bottom.visible, "The shelf stays in view during the card")
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
    check(scene.stat_labels[0].text == "64" and scene.stat_labels[3].text == "4", "Outline shows the stats as the mysteries make them")
    check(has_label(scene.bottom, "EXP 0") and not has_label(scene.bottom, "カルテ"), "EXP sits where the karte caption was")
    check(not has_label(scene.bottom, "言葉") and not has_label(scene.bottom, "あき"), "No counts on the shelf")
    var hits: Array = shelf_hits(scene)
    check(hits.size() == 6 and hits.all(func(b): return b.tooltip_text == ""), "Six shelf items, no tooltips")
    var goo := 0
    for child in scene.bottom.get_children():
        if child.get_script() == scene.Goo:
            goo += 1
    check(goo == 6, "Every mystery is drawn as goo")
    scene._advance()
    check(scene.completed and scene.state.exp == 1 and has_label(scene.bottom, "EXP 1"), "First action reveals the line and earns EXP")
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
    check(not has_label(scene.overlay, "刺さっている言葉") and not has_label(scene.overlay, "EXP"), "Karte keeps to the meters and the map")
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
    # The tutorial flows into the first session: the room stays, the shelf lights up.
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
    check(scene.state.on_board() and is_instance_valid(scene.body) and scene.portraits.has("みなと"), "The board keeps the room and the characters")
    check("棚にある言葉を" in scene.body.text and scene.next_button.text.begins_with("今日は、ここまで"), "Minato points at the shelf; the button ends the day")
    check(has_label(scene.bottom, "心の棚") and labels_of(scene.bottom).any(func(l): return l.text == "心の棚" and l.get_theme_color("font_color") == scene.GOLD), "Shelf highlighted on the board")
    scene._finish_line()
    scene._advance()
    check(scene.state.on_board(), "Space does not end the session")
    scene._show_peek("coworker")
    check(is_instance_valid(scene.peek) and has_label(scene.peek, "？？？") and has_label(scene.peek, "話してみる？（EXP 20）"), "Hovering a mystery offers to talk")
    scene._hide_peek()
    check(not is_instance_valid(scene.peek), "Peek hides")
    scene._shelf_click("coworker")
    check(scene.state.trauma_state("coworker") == "appraised" and scene.state.exp == 24 and scene.state.counsel_step == "talk_recall", "Clicking talks: the mystery opens for twenty")
    check("勝手に期待した" in scene.body.text, "Recall text rendered")
    scene._finish_line()
    check(has_label(scene.content, "「バイト仲間じゃん？」") and has_label(scene.content, "もらった言葉の変化が半分"), "Opening reveals the crystal and its effect")
    scene._advance()
    check(scene.state.counsel_step == "talk_doctor" and "肩透かし" in scene.body.text, "Minato answers")
    scene._finish_line()
    scene._advance()
    check(scene.state.on_board() and "ほかに" in scene.body.text, "Back on the board with a follow-up prompt")
    var thorns := 0
    for child in scene.bottom.get_children():
        if child.get_script() == scene.Specimen:
            thorns += 1
    check(thorns == 1 and has_label(scene.bottom, "バイト仲間じゃん？"), "The opened trauma shows as a crystal with its words")
    scene._show_peek("coworker")
    check(has_label(scene.peek, "向き合うには EXP 1,500（足りない）"), "Hovering the opened trauma names the price")
    scene._hide_peek()
    scene._show_peek("handle")
    check(has_label(scene.peek, "今日はもう話した"), "A second mystery waits for the next session")
    scene._hide_peek()
    scene._shelf_click("coworker")
    check(scene.state.on_board() and scene.state.trauma_state("coworker") == "appraised", "Clicking an unaffordable trauma does nothing")
    scene._finish_session()
    check(scene.state.counsel_step == "closing" and "ここまで" in scene.body.text, "Closing line for a session in between")
    scene._finish_line()
    scene._advance()
    check(scene.state.counsel_step == "farewell", "Farewell")
    scene._finish_line()
    scene._advance()
    check(scene.mode == "map" and scene.state.current == "map", "First session leads to the map")
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
    check(has_label(scene.overlay, "勇気 +3"), "Collection blackout shows the halved stat change; an opened trauma still bites")
    var keep_button: Button = null
    for button in buttons_of(scene.overlay):
        if button.text.begins_with("心に留める"):
            keep_button = button
    check(keep_button != null, "Keep offered with a free slot")
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
    scene._decide_word("keep", -1)
    await settle(scene)
    check(scene.state.pending_word == "" and scene.state.held_words() == ["miracle"] and not is_instance_valid(scene.overlay), "Keeping puts the word on the shelf and closes the blackout")
    scene.auto_mode = false
    scene._show_word(scene.state.word_by_id("miracle"))
    check(has_label(scene.overlay, "勇気 +1"), "Word card shows the passive effect")
    scene._close_overlay()
    scene._show_trauma("handle")
    check(has_label(scene.overlay, "？？？") and not has_label(scene.overlay, "どう扱えばいい"), "A mystery card shows nothing of its words")
    scene._close_overlay()
    scene._show_trauma("coworker")
    check(has_label(scene.overlay, "先輩は言った") and has_label(scene.overlay, "向き合うには EXP 1,500"), "An opened trauma card shows its words and the full price")
    scene._close_overlay()
    # A full shelf: let go, or swap a held word out.
    scene.state.slots[7] = {"kind": "word", "id": "queen"}
    scene.state.collected.append("queen")
    scene.state.current = "sumika_10"
    scene._show_story()
    await dismiss(scene)
    scene._advance()
    check(scene.state.pending_word == "happiness" and scene.state.free_slot() < 0, "Third word arrives with no room")
    check(has_label(scene.overlay, "枠がない"), "Overlay explains the full shelf")
    await settle(scene)
    var exp_before_swap: int = scene.state.exp
    scene._decide_word("swap", scene.state.slot_of("miracle"))
    await settle(scene)
    check(scene.state.held_words() == ["happiness", "queen"] and scene.state.forgotten == ["miracle"] and scene.state.exp == exp_before_swap + 5, "Swap keeps the new word and pays for the old")
    scene.state.current = "main1_28"
    scene._show_story()
    await dismiss(scene)
    check(scene.portraits.has("あしか") and scene.portraits["あしか"].modulate.r == 1.0, "Speaking Ashika uses supplied portrait")
    # MAP and the stress lock through a mystery.
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
    scene.state.stats[0] = 76
    scene._show_map()
    pins = 0
    for child in scene.content.get_children():
        if child is Button and child.text.begins_with("●"):
            pins += 1
    check(pins == 1, "Stress through the mystery leaves only the home pin")
    scene.state.stats[0] = 60
    scene._show_map()
    scene._select_map_event("sumika")
    check(scene.state.current == "map", "Locked place ignored")
    scene._select_map_event("park")
    check(scene.state.current == "park_6" and scene.state.stats[0] == 60, "MAP opens selected event; going out is free")
    await dismiss(scene)
    scene.state.current = "park_15"
    scene._finish_line()
    scene._advance()
    check(scene.mode == "map" and scene.state.outings_done == 1, "The outing ends straight on the map")
    scene.state.outings_done = 2
    scene._select_map_event("cafe")
    await dismiss(scene)
    scene.state.current = "cafe_14"
    scene._finish_line()
    scene._advance()
    check(scene.state.current == "main1_5" and scene.mode == "story", "Third outing leads into CHAPTER 1 at once")
    await dismiss(scene)
    # A later session: facing with the price paid, and growth by talking about a word.
    scene.state.reset()
    scene.state.session = 1
    scene.state.collected = ["miracle", "queen"]
    scene.state.slots[6] = {"kind": "word", "id": "miracle"}
    scene.state.slots[7] = {"kind": "word", "id": "queen"}
    scene.state.traumas["coworker"].state = "appraised"
    scene.state.exp = 400
    scene.state.current = "main1_47"
    scene.state.choose(0)
    check(scene.state.current == "counseling" and scene.state.session == 2, "Chapter one leads straight into the second session")
    scene._show_story()
    await dismiss(scene)
    check("どうでしたか" in scene.body.text, "Minato asks about the weeks")
    scene._finish_line()
    scene._advance()
    check("2個" in scene.body.text, "Yodaka counts the words")
    scene._finish_line()
    scene._advance()
    check(scene.state.on_board(), "Board")
    scene._show_peek("coworker")
    check(has_label(scene.peek, "向き合う？（EXP 375）"), "The queen halves the price twice for a trauma of its kind")
    scene._hide_peek()
    var exp_before_face: int = scene.state.exp
    scene._shelf_click("coworker")
    check(scene.state.trauma_state("coworker") == "accepted" and scene.state.exp == exp_before_face - 375 and scene.state.counsel_step == "face_line", "Clicking faces the trauma for the shown price")
    check("先輩の距離" in scene.body.text, "Resolve line rendered")
    scene._finish_line()
    scene._advance()
    check(scene.state.counsel_step == "face_response" and "半分受け取って" in scene.body.text, "Minato answers the facing")
    scene._finish_line()
    scene._advance()
    check(scene.state.on_board() and scene.state.free_slot() >= 0, "Board with a freed slot")
    scene.state.exp = 300
    scene._show_peek("queen")
    check(has_label(scene.peek, "強化する？（EXP 80）"), "Hovering a word offers to grow it")
    scene._hide_peek()
    var exp_before_grow: int = scene.state.exp
    scene._shelf_click("queen")
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
    scene._shelf_click("queen")
    check(scene.state.counsel_step == "grow_insight" and "一緒に何かをする相手" in scene.body.text, "Third level reveals the insight")
    scene._finish_line()
    scene._advance()
    check(scene.state.counsel_step == "grow_response" and "もう法月さんのもの" in scene.body.text, "Minato closes the insight")
    scene._finish_line()
    scene._advance()
    scene._show_peek("queen")
    check(has_label(scene.peek, "もう、これ以上は育たない"), "Top level cannot grow")
    scene._hide_peek()
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
    check(scene.mode == "result" and has_label(scene.content, "向き合ったトラウマ 1"), "End screen follows the farewell")
    scene._show_reflections()
    check(has_label(scene.overlay, "振り返りの記録"), "Reflections open")
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
    scene.state.traumas["no_longer"].state = "appraised"
    scene._show_story()
    await dismiss(scene)
    scene._finish_line()
    var locked := false
    for child in scene.choice_box.get_children():
        if child is Button and "お姫様" in child.text:
            locked = child.disabled
    check(locked and has_label(scene.choice_box, "現在 5"), "Capped courage locks the choice in UI")
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
        for key in ["quote", "recall", "doctor", "resolve", "response"]:
            texts.append(trauma[key])
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
    await settle(scene)
    scene._dismiss_interlude()
    await settle(scene)
