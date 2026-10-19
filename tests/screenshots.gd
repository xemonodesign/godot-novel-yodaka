extends SceneTree

# Drives the real scene through the new loop and saves screenshots for docs/.
# Run under a display: xvfb-run godot --path . --resolution 1280x800 --script tests/screenshots.gd

const State = preload("res://src/story_state.gd")
var scene: Control
var out_dir := "res://docs/screenshots"

func _initialize() -> void:
    call_deferred("run")

func shot(name: String) -> void:
    for i in range(6):
        await process_frame
    var image := root.get_viewport().get_texture().get_image()
    image.save_png("%s/%s.png" % [out_dir, name])
    print("saved ", name)

func settle() -> void:
    if is_instance_valid(scene.interlude_tween) and scene.interlude_tween.is_running():
        await scene.interlude_tween.finished

func dismiss() -> void:
    await settle()
    scene._dismiss_interlude()
    await settle()

func run() -> void:
    scene = load("res://src/main.tscn").instantiate()
    root.add_child(scene)
    scene.state.save_path = "/tmp/yodaka-shots.json"
    scene.state.reset()
    scene.state.save_game()
    scene._show_title()
    await shot("title")
    # Tutorial counseling with the trauma-filled slots underneath.
    scene._show_story()
    await dismiss()
    scene._finish_line()
    await shot("counseling")
    scene.state.current = "counsel1_10"
    scene._show_story()
    scene._finish_line()
    await shot("tutorial-choice")
    # Opening session: talk, then face the first trauma.
    var state = scene.state
    state.reset()
    state.gain_exp(37)
    state.current = "counseling"
    state.counsel_step = "session"
    scene.session_selected = 1
    scene._show_story()
    await shot("session-sealed")
    scene._talk("blank")
    await dismiss()
    scene._finish_line()
    await shot("talk")
    for i in range(5):
        scene._finish_line()
        scene._advance()
    scene._slot_pressed(1)
    await shot("session-loosened")
    scene._confront("blank")
    await shot("session-faced")
    # A word offer with full slots, then with a free slot.
    state.current = "sushi_10"
    scene._show_story()
    await dismiss()
    scene._advance()
    await settle()
    await shot("word-offer-full")
    scene._release_pending()
    await shot("word-released")
    await dismiss()
    state.slots[6] = ""
    state.trauma_state.erase("morning")
    state.current = "cafe_7"
    scene._show_story()
    await dismiss()
    scene._advance()
    await settle()
    await shot("word-offer")
    scene._keep_pending()
    await dismiss()
    state.current = "main1_28"
    scene._show_story()
    await dismiss()
    scene._advance()
    await settle()
    scene._keep_pending()
    await shot("word-forget")
    scene._forget_pending("miracle")
    await dismiss()
    # Map.
    state.current = "map"
    state.round_index = 1
    scene._show_story()
    await shot("map")
    # Mid session with words, growth, combination preview and a resolution.
    state.reset()
    state.gain_exp(900)
    state.counsel_session = 1
    state.round_index = 1
    state.current = "counseling"
    state.counsel_step = "session"
    state.talked = true
    state.slots[6] = "w:praise"
    state.levels["praise"] = 2
    state.slots[7] = "w:cute"
    state.levels["cute"] = 1
    state.trauma_state.erase("morning")
    state.trauma_state.erase("stall")
    state.trauma_state["bash"].loosened = true
    state.trauma_state["bash"].cost = 20
    state.trauma_state["bash"].hardness = 40
    state.trauma_state["mirror"].loosened = true
    state.trauma_state["mirror"].cost = 80
    state.collected = ["praise", "cute"]
    state.session_lines = [["みなと", "コートに立たなくても、走れる場所はありますか。"], ["よだか", "朝の学校なら、誰もいないから。……走ってはいないけど、歩くことはしてます。"]]
    scene.session_selected = 6
    scene._show_story()
    await shot("session-word")
    scene._grow("praise")
    await shot("session-grown")
    scene.session_selected = 0
    scene.session_cards = ["praise", "cute"]
    scene._show_session()
    await shot("session-combine")
    scene._confront("bash")
    await settle()
    await shot("resolved")
    await dismiss()
    scene.session_selected = 5
    scene.session_cards = ["cute"]
    scene._show_session()
    scene._confront("mirror")
    scene._confront("mirror")
    await settle()
    await shot("surfaced")
    await dismiss()
    await shot("session-deeper")
    scene._show_karte(Callable())
    await shot("karte")
    scene._close_overlay()
    scene._slot_pressed(5)
    scene._end_session()
    scene._finish_line()
    await shot("closing")
    state.current = "result"
    state.round_index = 4
    state.counsel_session = 3
    scene._show_story()
    await shot("result")
    scene._show_story()
    scene._show_trauma(state.trauma_by_id("nameless"))
    await shot("trauma-card")
    scene._close_overlay()
    scene._show_word(state.word_by_id("praise"))
    await shot("word-card")
    DirAccess.remove_absolute("/tmp/yodaka-shots.json")
    quit(0)
