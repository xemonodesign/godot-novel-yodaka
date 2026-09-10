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

func run() -> void:
    var state = State.new()
    state.save_path = "/tmp/yodaka-runtime-test.json"
    var backup: String = state.save_path
    for selection in range(3):
        state.reset()
        var guard := 0
        while state.current != "result":
            guard += 1
            check(guard < 350, "Scenario loop")
            if guard >= 350:
                break
            if state.current == "map":
                check(state.select_event(["mother", "cafe", "park"][selection]), "Select one MAP event")
                check(not state.select_event("park"), "Cannot select a second event")
                continue
            if state.current == "counseling":
                while state.answers.size() < state.collected.size():
                    var before: Array = state.stats.duplicate()
                    var preview: Array = state.preview_effects(selection)
                    check(state.stats == before, "Preview never mutates stats")
                    var delta: Array = state.interpret(selection)
                    check(preview == delta, "Preview matches actual effects")
                    check(delta.filter(func(value): return value != 0).size() <= 2, "At most two stats move")
                    for k in range(6):
                        check(state.stats[k] == before[k] + delta[k], "Accurate delta")
                        check(state.stats[k] >= 0 and state.stats[k] <= 100, "Bounded stats")
                var return_id: String = state.counsel_return
                var resumed = State.new()
                resumed.save_path = backup
                check(resumed.load_game() and resumed.counsel_return == return_id, "Counseling destination persists")
                state.complete_counseling()
                check(state.current == return_id, "Counseling returns to its destination")
                continue
            state.finish_line()
            var count: int = state.collected.size()
            state.finish_line()
            check(count == state.collected.size(), "Duplicate collection")
            var node: Dictionary = state.data.nodes[state.current]
            var choice: int = selection % node.choices.size() if node.has("choices") else 0
            if not state.can_choose(choice):
                choice = 0
            check(state.choose(choice), "Available choice advances")
        check(state.collected.size() == (8 if selection == 2 else 9), "All route words available")
        check(state.interpret(0).is_empty(), "Cannot answer twice")
        var restored = State.new()
        restored.save_path = backup
        check(restored.load_game(), "Can restore saved run")
        check(restored.stats == state.stats, "Stats persisted")
        check(restored.answers == state.answers, "Interpretations persisted")
    state.current = "main4_31"
    state.stats[1] = 54
    check(not state.choose(1) and state.current == "main4_31", "Courage 54 cannot unlock choice")
    state.stats[1] = 55
    check(state.choose(1) and state.current == "main4_38", "Courage 55 unlocks choice")
    var invalid := FileAccess.open(backup, FileAccess.WRITE)
    invalid.store_string("{broken")
    invalid.close()
    check(not state.load_game(), "Corrupt save rejected")
    DirAccess.remove_absolute(backup)
    # Old saves still load without resetting collected words or statistics.
    state.reset()
    state.current = "mother_10"
    state.finish_line()
    var legacy = JSON.parse_string(FileAccess.get_file_as_string(backup))
    legacy.version = 1
    legacy.erase("scene_key")
    legacy.erase("pending_word")
    legacy.erase("counsel_step")
    var legacy_file := FileAccess.open(backup, FileAccess.WRITE)
    legacy_file.store_string(JSON.stringify(legacy))
    legacy_file.close()
    check(state.load_game() and state.collected.size() == 1, "Version 1 saves migrate")
    DirAccess.remove_absolute(backup)
    # Drive actual UI, including mandatory interludes, cast, and counseling dialogue.
    var scene = load("res://src/main.tscn").instantiate()
    root.add_child(scene)
    scene.state.save_path = "/tmp/yodaka-ui-test.json"
    scene.state.reset()
    scene._show_story()
    check(scene.overlay_kind == "scene", "Opening chapter card appears")
    var start_id: String = scene.state.current
    scene._process(10)
    scene._advance()
    scene._close_overlay()
    check(scene.state.current == start_id and not scene.completed, "Chapter blocks input and typewriter")
    check(scene.overlay_kind == "scene", "Escape cannot skip chapter acknowledgement")
    await dismiss(scene)
    check(not is_instance_valid(scene.overlay), "Click closes chapter card")
    check(scene.portraits.has("医師") and scene.portraits.has("よだか"), "Counseling cast present")
    check(scene.portraits["医師"].modulate.r == 1.0, "Speaking doctor lit")
    check(scene.portraits["よだか"].modulate.r < 0.6, "Listening Yodaka dimmed")
    check(scene.portraits["医師"].size == scene.portraits["よだか"].size, "Characters have matching size")
    check(scene.portraits["医師"].position.y == scene.portraits["よだか"].position.y, "Characters have matching depth")
    check(scene.portraits["医師"].get_index() > scene.body.get_index(), "Partner in front of dialogue")
    check(is_equal_approx(scene.body.position.x + scene.body.size.x / 2, 640), "Text centered on screen")
    check(not scene.status.visible, "Top status removed")
    check(scene.portraits["よだか"].get_index() > scene.body.get_index(), "Yodaka in front of dialogue")
    scene._advance()
    check(scene.completed, "First action reveals complete line")
    var current: String = scene.state.current
    scene._show_history()
    scene._advance()
    check(scene.state.current == current, "Modal prevents advancing")
    scene._close_overlay()
    scene._advance()
    check(scene.state.current != current, "Second action advances")
    check(not is_instance_valid(scene.overlay), "No card between lines in same scene")
    check(scene.portraits["よだか"].modulate.r == 1.0, "Speaking Yodaka lit")
    check(scene.portraits["医師"].modulate.r < 0.6, "Listening doctor dimmed")
    scene.state.current = "mother_10"
    scene._show_story()
    await dismiss(scene)
    scene._advance()
    check(scene.portraits.has("りあ"), "Mother portrait displayed")
    check(scene.state.collected.size() == 1, "UI collects completed marked word")
    check(scene.overlay_kind == "word", "Collection creates blackout effect")
    scene.auto_mode = true
    scene._process(20)
    scene._advance()
    scene._close_overlay()
    check(scene.overlay_kind == "word" and scene.state.current == "mother_10", "Collection requires a click even on AUTO")
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
    scene.state.current = "counseling"
    scene._show_story()
    await dismiss(scene)
    check("今週はどうでしたか" in scene.body.text, "Doctor asks Yodaka about the week")
    for step in ["opening_yodaka", "recall", "question", "choice"]:
        scene._finish_line()
        scene._advance()
        check(scene.state.counsel_step == step, "Counseling conversation order: " + step)
    scene._finish_line()
    check(scene.preview_labels.size() == 3, "All choices show effect previews")
    check("ストレス -18" in scene.preview_labels[0] and "自認 +16" in scene.preview_labels[0], "Named effects visible before answering")
    var before_reply: Array = scene.state.preview_effects(0)
    scene._interpret(0)
    scene._interpret(0)
    check(scene.state.answers.size() == 1, "Double click answers once")
    check(scene.state.answers[0].delta == before_reply, "UI preview equals applied delta")
    check(scene.current_dialogue.speaker == "よだか" and "嬉しかった" in scene.body.text, "Choice becomes Yodaka's spoken answer")
    var restored_reply = State.new()
    restored_reply.save_path = scene.state.save_path
    check(restored_reply.load_game() and restored_reply.counsel_step == "reply", "Resume preserves chosen spoken reply")
    scene._finish_line()
    scene._advance()
    check(scene.state.counsel_step == "response" and scene.current_dialogue.speaker == "医師", "Doctor responds after Yodaka")
    scene._finish_line()
    scene._advance()
    check(scene.mode == "result", "End screen follows final doctor response")
    scene.state.reset()
    scene.state.current = "map"
    scene._show_story()
    check(scene.mode == "map", "MAP renders after chapter 5")
    scene._select_map_event("park")
    check(scene.state.current == "map_park_6", "MAP opens selected event")
    await dismiss(scene)
    scene.state.current = "map_park_15"
    scene.state.choose(0)
    check(scene.state.current == "counseling" and scene.state.counsel_return == "main4_5", "Event leads to intermediate counseling")
    scene.state.collected = ["queen"]
    scene.state.counsel_step = "choice"
    scene._show_story()
    await dismiss(scene)
    scene._finish_line()
    scene._interpret(0)
    check(scene.state.stats[1] >= 55, "Counseling raises courage above gate")
    scene._finish_line()
    scene._advance()
    scene._finish_line()
    scene._advance()
    check(scene.state.current == "main4_5", "Intermediate counseling proceeds to chapter 6")
    await dismiss(scene)
    scene.state.current = "sumika_6"
    scene._show_story()
    await dismiss(scene)
    check(scene.portraits.has("すみか"), "Sumika portrait displayed")
    scene.state.current = "main4_31"
    scene.state.stats[1] = 54
    scene._show_story()
    await dismiss(scene)
    scene._finish_line()
    var locked := false
    for child in scene.choice_box.get_children():
        if child is Button and "お姫様" in child.text:
            locked = child.disabled
    check(locked, "Locked choice is disabled in UI")
    # Verify the narrowed, centered dialogue area fits all original lines and recaps.
    scene.set_process(false)
    scene._render_dialogue(scene.state.data.nodes["intro_0"])
    var texts: Array = []
    for node in scene.state.data.nodes.values():
        texts.append(node.text)
    for word in scene.state.data.words:
        texts.append(word.memory)
        for interpretation in word.interpretations:
            texts.append(interpretation.reply)
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
