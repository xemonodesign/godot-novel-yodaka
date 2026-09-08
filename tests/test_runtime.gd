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
        while state.current != "counseling":
            guard += 1
            check(guard < 300, "Scenario loop")
            state.finish_line()
            var count: int = state.collected.size()
            state.finish_line()
            check(count == state.collected.size(), "Duplicate collection")
            var node: Dictionary = state.data.nodes[state.current]
            state.choose(selection % node.choices.size() if node.has("choices") else 0)
        check(state.collected.size() == 8, "All words available")
        for i in range(8):
            var before: Array = state.stats.duplicate()
            var delta: Array = state.interpret(selection)
            check(delta.size() == 6, "Six parameter deltas")
            for k in range(6):
                check(state.stats[k] == before[k] + delta[k], "Accurate delta")
                check(state.stats[k] >= 0 and state.stats[k] <= 100, "Bounded stats")
        check(state.interpret(0).is_empty(), "Cannot answer twice")
        var restored = State.new()
        restored.save_path = backup
        check(restored.load_game(), "Can restore saved run")
        check(restored.stats == state.stats, "Stats persisted")
        check(restored.answers == state.answers, "Interpretations persisted")
    var invalid := FileAccess.open(backup, FileAccess.WRITE)
    invalid.store_string("{broken")
    invalid.close()
    check(not state.load_game(), "Corrupt save rejected")
    DirAccess.remove_absolute(backup)
    # Drive actual UI, including modal input suppression and end screen.
    var scene = load("res://src/main.tscn").instantiate()
    root.add_child(scene)
    scene.state.save_path = "/tmp/yodaka-ui-test.json"
    scene.state.reset()
    scene._show_story()
    await process_frame
    check(scene.body.visible_characters >= 0, "Typewriter initially active")
    scene._advance()
    check(scene.completed, "First action reveals complete line")
    var current: String = scene.state.current
    scene._show_history()
    scene._advance()
    check(scene.state.current == current, "Modal prevents advancing")
    scene._close_overlay()
    scene._advance()
    check(scene.state.current != current, "Second action advances")
    scene.state.current = "mother_10"
    scene._show_story()
    scene._advance()
    check(scene.state.collected.size() == 1, "UI collects completed marked word")
    scene._show_word(scene.state.word_by_id("praise"))
    await process_frame
    scene._close_overlay()
    scene.state.current = "counseling"
    scene._show_story()
    scene._interpret(0)
    scene._interpret(0)
    check(scene.state.answers.size() == 1, "Double click answers once")
    scene._show_counseling()
    check(scene.mode == "result", "End screen reached")
    scene.queue_free()
    await process_frame
    DirAccess.remove_absolute("/tmp/yodaka-ui-test.json")
    print("%s: %d runtime checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
    quit(0 if failures == 0 else 1)
