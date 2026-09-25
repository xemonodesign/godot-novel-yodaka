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

func run() -> void:
    var state = State.new()
    state.save_path = "/tmp/yodaka-runtime-test.json"
    var backup: String = state.save_path
    check(State.STAT_NAMES.size() == 4 and State.STAT_NAMES[0] == "ストレス", "Stress plus three stats")
    for selection in range(3):
        state.reset()
        check(state.current == "counsel0_6", "Prototype opens in the counseling room")
        var guard := 0
        var chapters: Array = []
        var outings := 0
        var grown := 0
        while state.current != "result":
            guard += 1
            check(guard < 600, "Scenario loop")
            if guard >= 600:
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
                var candidates: Array = state.grow_candidates()
                if not candidates.is_empty():
                    var before: Array = state.stats.duplicate()
                    var preview: Array = state.preview_interpretation(candidates[0], selection)
                    check(state.stats == before, "Preview never mutates stats")
                    var delta: Array = state.grow(candidates[0], selection)
                    check(preview == delta, "Preview matches growth")
                    bounded(state, before, delta, "growth")
                    check(state.is_grown(candidates[0]) and state.night_step == "reply", "Word grown at night")
                    check(state.grow(candidates[0], 0).is_empty(), "One growth per night")
                    if candidates.size() > 1:
                        check(state.grow(candidates[1], 0).is_empty(), "Second word cannot grow the same night")
                    grown += 1
                var stress: int = state.stats[0]
                var destination: String = state.after_night
                var resumed = State.new()
                resumed.save_path = backup
                check(resumed.load_game() and resumed.after_night == destination and resumed.night_step == state.night_step, "Night persists")
                state.sleep()
                check(state.stats[0] == clampi(clampi(stress - 4, 0, 100) + (6 if destination == "chapter" else 0), 0, 100), "Sleep lowers stress, a chapter costs some")
                check(state.night_step == "pick" and state.night_word == "", "Night resets after sleeping")
                if destination == "map":
                    check(state.current == "map", "Back to the map")
                elif destination == "chapter":
                    check(state.current.begins_with("main"), "Round leads into a main chapter")
                else:
                    check(state.current == "counseling", "Last chapter leads to the closing counseling")
                continue
            if state.current == "counseling":
                var steps: Array = []
                while state.current == "counseling":
                    steps.append(state.counsel_step)
                    if state.counsel_step == "choice":
                        var before: Array = state.stats.duplicate()
                        var delta: Array = state.interpret(selection)
                        bounded(state, before, delta, "counseling")
                        check(state.counsel_step == "reply", "Answer becomes Yodaka's reply")
                    else:
                        check(state.advance_counseling(), "Counseling advances: " + state.counsel_step)
                check(steps[0] == "opening_doctor" and steps.back() == "farewell", "Counseling opens and closes")
                check(steps.count("recall") == state.collected.size(), "Every word is reviewed once")
                check(steps.count("grown_reply") == grown, "Grown words are told, not asked")
                check(steps.count("choice") == state.collected.size() - grown, "Only ungrown words are asked")
                continue
            var node: Dictionary = state.data.nodes[state.current]
            if node.get("kind") == "main" and (chapters.is_empty() or chapters.back() != node.chapter):
                chapters.append(node.chapter)
            state.finish_line()
            var count: int = state.collected.size()
            var stats_after: Array = state.stats.duplicate()
            state.finish_line()
            check(count == state.collected.size() and stats_after == state.stats, "Duplicate collection or effect")
            var choice: int = selection % node.choices.size() if node.has("choices") else 0
            if not state.can_choose(choice):
                choice = 0
            check(state.choose(choice), "Available choice advances")
        check(chapters.size() == 4 and chapters[0] == "tiktokの女王" and chapters[3] == "溺れる海のあしか", "Four main chapters in order")
        check(outings == 12, "Twelve outings across the rounds")
        check(state.collected.size() >= 6 and state.collected.size() <= state.data.words.size(), "Words collected across outings and chapters: %d" % state.collected.size())
        print("Strategy %d: %d words, %d rests, stats %s" % [selection, state.collected.size(), outings - state.visited.size(), state.stats])
        check(state.answers.size() == state.collected.size(), "Every word interpreted by the end")
        for id in state.collected:
            check(state.gains.has(id) and state.gains[id].size() == 4, "Collection effect recorded")
        check(state.interpret(0).is_empty(), "Cannot answer after the end")
        var restored = State.new()
        restored.save_path = backup
        check(restored.load_game(), "Can restore saved run")
        check(restored.stats == state.stats and restored.current == "result", "Stats persisted")
        check(restored.answers == state.answers and restored.gains == state.gains, "Interpretations persisted")
    # Immediate effects: words, tutorial choices, and resting.
    state.reset()
    state.current = "sushi_10"
    var before_word: Array = state.stats.duplicate()
    check(state.finish_line(), "Marked line collects a word")
    check(state.stats[0] == before_word[0] - 6 and state.stats[2] == before_word[2] + 5, "Receiving a word changes stats at once")
    check(state.gains["praise"] == [-6, 0, 5, 0], "Collection delta recorded")
    state.current = "counsel1_10"
    state.finish_line()
    var before_choice: Array = state.stats.duplicate()
    check(state.choose(1) and state.current == "counsel1_14", "Tutorial choice branches")
    check(state.stats[3] == before_choice[3] + 4 and state.stats[0] == before_choice[0] + 3, "Tutorial choice moves stats")
    check(state.last_delta == [3, 0, 0, 4], "Choice delta reported")
    state.current = "cover_15"
    var before_cover: Array = state.stats.duplicate()
    state.finish_line()
    check(state.stats[1] == before_cover[1] + 4 and state.stats[2] == before_cover[2] + 2, "Wordless fragment gives its insight at the end")
    state.current = "rest_2"
    var before_rest: int = state.stats[0]
    state.finish_line()
    check(state.stats[0] == before_rest - 15, "Resting lowers stress")
    check(state.choose(0) and state.current == "night" and state.outings_done == 1, "Rest counts as an outing")
    # Courage gate and stress lock.
    state.current = "main4_31"
    state.stats[1] = 59
    check(not state.choose(1) and state.current == "main4_31", "Courage 59 cannot unlock choice")
    state.stats[1] = 60
    check(state.choose(1) and state.current == "main4_38", "Courage 60 unlocks choice")
    state.reset()
    state.current = "map"
    state.stats[0] = 80
    check(not state.event_available("park") and state.event_available("rest"), "High stress allows only resting")
    check(not state.select_event("park"), "Locked outing rejected")
    state.stats[0] = 79
    check(state.event_available("park") and not state.event_available("sumika") and not state.event_available("cry"), "Week one pool excludes later events")
    state.round_index = 1
    check(state.event_available("sumika") and not state.event_available("cry"), "Week two unlocks new places")
    state.round_index = 2
    check(state.event_available("cry") and state.event_available("taiko"), "Week three unlocks the rest")
    state.round_index = 1
    state.visited = ["park"]
    check(not state.event_available("park") and state.event_available("rest"), "Visited place closed, rest repeatable")
    var invalid := FileAccess.open(backup, FileAccess.WRITE)
    invalid.store_string("{broken")
    invalid.close()
    check(not state.load_game(), "Corrupt save rejected")
    var old := FileAccess.open(backup, FileAccess.WRITE)
    old.store_string(JSON.stringify({"version": 3, "current": "main4_5", "collected": [], "answers": [], "stats": [65, 40, 45, 40, 35, 35], "history": []}))
    old.close()
    check(not state.load_game(), "Previous flow saves are not loaded")
    DirAccess.remove_absolute(backup)
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
    scene._advance()
    check(scene.completed, "First action reveals complete line")
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
    # Word collection with immediate effect.
    scene.state.current = "sushi_10"
    scene._show_story()
    await dismiss(scene)
    scene._advance()
    check(scene.portraits.has("りあ"), "Mother portrait displayed")
    check(scene.state.collected.size() == 1, "UI collects completed marked word")
    check(scene.overlay_kind == "word", "Collection creates blackout effect")
    var delta_shown := false
    for child in scene.overlay.get_children():
        if child is Label and "ストレス -6" in child.text:
            delta_shown = true
    check(delta_shown, "Collection blackout shows the stat change")
    scene.auto_mode = true
    scene._process(20)
    scene._advance()
    scene._close_overlay()
    check(scene.overlay_kind == "word" and scene.state.current == "sushi_10", "Collection requires a click even on AUTO")
    var restored_pending = State.new()
    restored_pending.save_path = scene.state.save_path
    check(restored_pending.load_game() and restored_pending.pending_word == "praise", "Unacknowledged effect persists")
    await dismiss(scene)
    check(scene.state.pending_word == "", "Click acknowledges collection")
    scene._show_word(scene.state.word_by_id("praise"))
    scene._close_overlay()
    scene.state.current = "main1_28"
    scene._show_story()
    await dismiss(scene)
    check(scene.portraits.has("あしか") and scene.portraits["あしか"].modulate.r == 1.0, "Speaking Ashika uses supplied portrait")
    # MAP, outing, night growth.
    scene.state.reset()
    scene.state.current = "map"
    scene._show_story()
    check(scene.mode == "map", "MAP renders")
    var enabled := 0
    for child in scene.content.get_children():
        if child is Button and child.text.length() > 4 and child.text.substr(0, 2).is_valid_int() and child.text.substr(2, 2) == "  " and not child.disabled:
            enabled += 1
    check(enabled == 8, "Week one offers seven places and rest")
    scene._select_map_event("sumika")
    check(scene.state.current == "map", "Locked place ignored")
    scene._select_map_event("park")
    check(scene.state.current == "park_6" and scene.state.stats[0] == 65, "MAP opens selected event and going out costs stress")
    await dismiss(scene)
    scene.state.current = "park_15"
    scene.state.choose(0)
    check(scene.state.current == "night" and scene.state.after_night == "map", "First outing leads to the night, then back to the map")
    scene.state.collected = ["queen", "praise"]
    scene._show_story()
    check(scene.mode == "night", "Night renders")
    scene._pick_night_word("queen")
    check(scene.preview_labels.size() == 3 and "勇気 +6" in scene.preview_labels[0], "Night growth previews effects")
    scene._grow("queen", 0)
    check(scene.state.is_grown("queen") and scene.state.stats[1] == 41, "UI growth applies interpretation")
    scene._grow("praise", 0)
    check(not scene.state.is_grown("praise"), "Only one word grows per night")
    scene._sleep()
    check(scene.mode == "map" and scene.state.outings_done == 1, "Sleeping returns to the map")
    scene.state.outings_done = 1
    scene.state.outings_done = 2
    scene._select_map_event("cafe")
    scene.state.current = "cafe_14"
    scene.state.choose(0)
    check(scene.state.after_night == "chapter", "Third outing completes the round")
    scene._show_story()
    scene._sleep()
    check(scene.state.current == "main1_5", "Round leads into CHAPTER 1")
    await dismiss(scene)
    # Closing counseling with a grown word and an ungrown word.
    scene.state.current = "counseling"
    scene.state.counsel_step = "opening_doctor"
    scene.state.reviewed = 0
    scene._show_story()
    await dismiss(scene)
    check("どうでしたか" in scene.body.text, "Minato asks about the weeks")
    for step in ["opening_yodaka", "recall", "grown_reply", "response", "recall", "question", "choice"]:
        scene._finish_line()
        scene._advance()
        check(scene.state.counsel_step == step, "Counseling order: " + step)
    scene._finish_line()
    check(scene.preview_labels.size() == 3 and "ストレス -8" in scene.preview_labels[0], "Named effects visible before answering")
    var before_reply: Array = scene.state.preview_interpretation("praise", 0)
    scene._interpret(0)
    scene._interpret(0)
    check(scene.state.answers.size() == 2, "Double click answers once")
    check(scene.state.answers[1].delta == before_reply, "UI preview equals applied delta")
    check(scene.current_dialogue.speaker == "よだか" and "嬉しかった" in scene.body.text, "Choice becomes Yodaka's spoken answer")
    var restored_reply = State.new()
    restored_reply.save_path = scene.state.save_path
    check(restored_reply.load_game() and restored_reply.counsel_step == "reply", "Resume preserves chosen spoken reply")
    for step in ["response", "closing"]:
        scene._finish_line()
        scene._advance()
        check(scene.state.counsel_step == step, "Counseling order: " + step)
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
    check(scene.mode == "result", "End screen follows the farewell")
    scene.state.current = "sumika_6"
    scene._show_story()
    await dismiss(scene)
    check(scene.portraits.has("すみか"), "Sumika portrait displayed")
    scene.state.current = "main4_31"
    scene.state.stats[1] = 59
    scene._show_story()
    await dismiss(scene)
    scene._finish_line()
    var locked := false
    for child in scene.choice_box.get_children():
        if child is Button and "お姫様" in child.text:
            locked = child.disabled
    check(locked, "Locked choice is disabled in UI")
    # Verify the centered dialogue area fits all lines, recaps, replies and counseling text.
    scene.set_process(false)
    scene._render_dialogue(scene.state.data.nodes["counsel0_6"])
    var texts: Array = []
    for node in scene.state.data.nodes.values():
        texts.append(node.text)
    for word in scene.state.data.words:
        texts.append(word.memory)
        texts.append("「%s」……。\n法月さんは、その時どう感じましたか？" % word.word)
        for interpretation in word.interpretations:
            texts.append(interpretation.reply)
    texts.append_array(scene.RESPONSES)
    texts.append("受け取った言葉を飾って、ときには整理して。\n居心地よくいられる時間が、少しでも続きますように。\nでは、お大事にどうぞ。法月さん")
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

func dismiss(scene: Control) -> void:
    if is_instance_valid(scene.interlude_tween) and scene.interlude_tween.is_running():
        await scene.interlude_tween.finished
    scene._dismiss_interlude()
    if is_instance_valid(scene.interlude_tween) and scene.interlude_tween.is_running():
        await scene.interlude_tween.finished
