extends Control

const State = preload("res://src/story_state.gd")
const Specimen = preload("res://src/specimen.gd")
const WordEffect = preload("res://src/word_effect.gd")
const MindMap = preload("res://src/mind_map.gd")
const Goo = preload("res://src/goo.gd")
const INK = Color("252c2a")
const MUTED = Color("778078")
const PAPER = Color("fcfbf6")
const MINT = Color("c7e5ba")
const DARK = Color("171e1c")
const THORN = Color("2a1f26")
const THORN_EDGE = Color("6e3b4a")
const GOLD = Color("f3d79e")
const FRAME = Rect2(44, 76, 1192, 455)  # the white frame above the row of buttons
const RESPONSES = ["法月さんには、そんなふうに届いたんですね。\nその嬉しさを、覚えておいてもいいと思います。",
    "しっくりこないと感じたことも、\n法月さん自身を知る、大切な手がかりですね。",
    "今、うまく言葉にできなくても大丈夫です。\n法月さんの中で、ゆっくり考えていきましょう。"]
const INSIGHT_RESPONSE = "その言葉は、もう法月さんのものですね。\nそのまま、持っていてください。"
var state = State.new()
var stage: Control
var content: Control
var bottom: Control
var overlay: Control
var peek: Control
var body: RichTextLabel
var next_button: Button
var choice_box: Control
var hint: Label
var status: Label
var exp_label: Label
var stat_bars: Array = []
var stat_labels: Array = []
var mode: String = "title"
var elapsed: float = 0.0
var completed: bool = false
var auto_mode: bool = false
var auto_timer: float = 0.0
var feedback: bool = false
var karte_shown: bool = false
var screen_epoch: int = 0
var overlay_kind: String = ""
var interlude_ready: bool = false
var interlude_tween: Tween
var active_scene_key: String = ""
var current_dialogue: Dictionary = {}
var portraits: Dictionary = {}
var portrait_textures: Dictionary = {}
var preview_labels: Array = []
var peek_id: String = ""
var last_place: String = "自宅_リビング"

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    var ui_theme := Theme.new()
    var font := FontVariation.new()
    font.base_font = load("res://src/assets/NotoSansJP.ttf")
    font.variation_opentype = {2003265652: 400.0}
    ui_theme.default_font = font
    ui_theme.default_font_size = 18
    theme = ui_theme
    stage = Control.new()
    stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
    stage.size = Vector2(1280, 800)
    add_child(stage)
    resized.connect(_resize_stage)
    _resize_stage()
    _show_title()

func _resize_stage() -> void:
    if stage == null:
        return
    var factor := minf(size.x / 1280.0, size.y / 800.0)
    stage.scale = Vector2.ONE * factor
    stage.position = (size - Vector2(1280, 800) * factor) / 2

func _clear(parent: Node) -> void:
    for child in parent.get_children():
        parent.remove_child(child)
        child.queue_free()

func _box(color: Color, border: Color = Color.TRANSPARENT, radius: int = 0, width: int = 1) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = color
    box.border_color = border
    box.set_border_width_all(width if border.a > 0 else 0)
    box.set_corner_radius_all(radius)
    return box

func _panel(parent: Node, rect: Rect2, color: Color, border: Color = Color.TRANSPARENT, radius: int = 0, width: int = 1) -> Panel:
    var panel := Panel.new()
    panel.position = rect.position
    panel.size = rect.size
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_theme_stylebox_override("panel", _box(color, border, radius, width))
    parent.add_child(panel)
    return panel

func _label(parent: Node, text: String, rect: Rect2, font_size: int = 18, color: Color = INK) -> Label:
    var label := Label.new()
    label.position = rect.position
    label.size = rect.size
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label

func _wrapped(parent: Node, text: String, rect: Rect2, font_size: int = 18, color: Color = INK) -> Label:
    var label := _label(parent, text, rect, font_size, color)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return label

func _center_label(parent: Node, text: String, rect: Rect2, font_size: int = 18, color: Color = INK) -> Label:
    var label := _label(parent, text, rect, font_size, color)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    return label

func _button(parent: Node, text: String, rect: Rect2, callback: Callable, accent: bool = false) -> Button:
    var button := Button.new()
    button.position = rect.position
    button.size = rect.size
    button.text = text
    button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    button.add_theme_color_override("font_color", INK)
    button.add_theme_color_override("font_hover_color", INK)
    button.add_theme_color_override("font_pressed_color", INK)
    button.add_theme_color_override("font_disabled_color", MUTED)
    button.add_theme_stylebox_override("normal", _box(MINT if accent else PAPER, Color("c5cbc1"), 3))
    button.add_theme_stylebox_override("hover", _box(Color("e0edd7"), INK, 3))
    button.add_theme_stylebox_override("pressed", _box(Color("b5d8a5"), INK, 3))
    button.add_theme_stylebox_override("disabled", _box(Color("d8dad1"), Color("c5cbc1"), 3))
    button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), Color("59835c"), 3))
    button.pressed.connect(callback)
    parent.add_child(button)
    return button

func _hit(parent: Node, rect: Rect2, callback: Callable) -> Button:
    var hit := Button.new()
    hit.position = rect.position
    hit.size = rect.size
    hit.flat = true
    hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    hit.pressed.connect(callback)
    parent.add_child(hit)
    return hit

func _image(parent: Node, path: String, rect: Rect2, alpha: float = 1.0) -> TextureRect:
    var picture := TextureRect.new()
    picture.texture = load(path)
    picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    picture.position = rect.position
    picture.size = rect.size
    picture.modulate.a = alpha
    picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(picture)
    return picture

func _specimen(parent: Node, rect: Rect2, kind: String, tint: Color, extra: int = 0) -> Control:
    var specimen = Specimen.new()
    specimen.position = rect.position
    specimen.size = rect.size
    parent.add_child(specimen)
    specimen.setup(kind, tint, extra)
    return specimen

func _goo(parent: Node, rect: Rect2, seed_value: int, bright: float = 1.0) -> Control:
    var goo = Goo.new()
    goo.position = rect.position
    goo.size = rect.size
    goo.seed_value = seed_value
    goo.bright = bright
    parent.add_child(goo)
    return goo

func _commas(value: int) -> String:
    var text := str(absi(value))
    var out := ""
    while text.length() > 3:
        out = "," + text.right(3) + out
        text = text.left(text.length() - 3)
    return ("-" if value < 0 else "") + text + out

func _base() -> void:
    screen_epoch += 1
    _clear(stage)
    overlay = null
    peek = null
    peek_id = ""
    overlay_kind = ""
    _image(stage, "res://bg.png", Rect2(0, 0, 1280, 800))
    _panel(stage, Rect2(0, 0, 1280, 800), Color(0.10, 0.15, 0.14, 0.45))
    status = _label(stage, "WEB PROTOTYPE  /  05", Rect2(927, 25, 310, 26), 13, Color("dce5d9"))
    status.visible = false
    content = Control.new()
    content.mouse_filter = Control.MOUSE_FILTER_IGNORE
    stage.add_child(content)
    bottom = Control.new()
    bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
    stage.add_child(bottom)
    _draw_bottom()

func _show_title() -> void:
    mode = "title"
    auto_mode = false
    body = null
    _base()
    _panel(content, Rect2(44, 76, 1192, 516), PAPER)
    _image(content, "res://bg_near.png", Rect2(702, 76, 534, 516))
    _panel(content, Rect2(702, 76, 534, 516), Color(0.1, 0.17, 0.15, 0.15))
    _portrait(content, "よだか", Rect2(788, 104, 335, 450), true)
    _label(content, "よだか", Rect2(81, 150, 600, 130), 92)
    _label(content, "ガールズモード（仮）", Rect2(88, 290, 600, 70), 44)
    _button(content, "はじめから   →", Rect2(94, 470, 245, 57), _start_new, true)
    var resume := _button(content, "つづきから", Rect2(355, 470, 230, 57), _resume)
    resume.disabled = not state.has_save()
    _label(content, "プロト体験版", Rect2(94, 545, 600, 25), 14, MUTED)
    _panel(content, Rect2(870, 530, 320, 40), PAPER)
    _label(content, "法月 よだか  /  主人公", Rect2(895, 534, 275, 30), 17)

func _start_new() -> void:
    if state.has_save():
        _modal("はじめから読む", "保存中の進行を、新しい物語で上書きします。", "はじめる", func():
            _close_overlay()
            state.reset()
            state.save_game()
            _show_story())
    else:
        state.reset()
        state.save_game()
        _show_story()

func _resume() -> void:
    if state.load_game():
        _show_story()
    else:
        _modal("保存を読み込めませんでした", "以前の流れの保存データか、形式を確認できないデータです。\n「はじめから」で新しい流れを遊べます。", "閉じる", _close_overlay)

# --- The bottom: outline panel with EXP, and the shelf ----------------------

func _draw_bottom() -> void:
    _clear(bottom)
    stat_bars.clear()
    stat_labels.clear()
    var effective: Array = state.effective_stats()
    _panel(bottom, Rect2(44, 612, 224, 155), DARK)
    _label(bottom, "いまの輪郭", Rect2(59, 618, 120, 23), 14, Color("d9e5d3"))
    exp_label = _label(bottom, "EXP " + _commas(state.exp), Rect2(120, 614, 140, 30), 19, GOLD)
    exp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    for i in range(State.STAT_NAMES.size()):
        var y: int = 652 + i * 27
        _label(bottom, State.STAT_NAMES[i], Rect2(60, y, 78, 20), 13, Color("b9c1b8"))
        var bar := ProgressBar.new()
        bar.position = Vector2(141, y + 8)
        bar.size = Vector2(70, 7)
        bar.show_percentage = false
        bar.add_theme_font_size_override("font_size", 1)
        bar.value = effective[i]
        bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bar.add_theme_stylebox_override("background", _box(Color("36403a")))
        bar.add_theme_stylebox_override("fill", _box(Color("d1b6aa") if i == 0 else MINT))
        bottom.add_child(bar)
        bar.size = Vector2(70, 7)
        stat_bars.append(bar)
        var lowered: bool = (i > 0) == (effective[i] < int(state.stats[i]))
        var tinted: bool = effective[i] != int(state.stats[i])
        stat_labels.append(_label(bottom, str(effective[i]), Rect2(218, y - 1, 32, 22), 13, Color("e8b0a0") if tinted and lowered else PAPER))
    _hit(bottom, Rect2(44, 612, 224, 155), _show_karte.bind(Callable()))
    var board: bool = state.on_board() and mode == "counseling"
    _panel(bottom, Rect2(280, 612, 956, 155), DARK, GOLD if board else Color.TRANSPARENT, 0, 2)
    _label(bottom, "心の棚", Rect2(296, 619, 270, 26), 15, GOLD if board else PAPER)
    var spacing: float = 928.0 / State.SLOTS
    for i in range(State.SLOTS):
        var x: float = 294 + i * spacing
        var slot: Dictionary = state.slots[i]
        var rect := Rect2(x, 653, spacing - 7, 103)
        if slot.is_empty():
            _panel(bottom, rect, Color("1e2823"), Color("364338"))
            _label(bottom, "·", Rect2(x + 49, 685, 20, 30), 28, Color("465344"))
        elif slot.kind == "trauma":
            var id: String = slot.id
            var def: Dictionary = state.trauma_def(id)
            if state.trauma_state(id) == "mystery":
                _goo(bottom, rect, i * 7 + 3)
                _panel(bottom, rect, Color.TRANSPARENT, Color("4a2434"))
            else:
                _panel(bottom, rect, THORN, THORN_EDGE)
                _specimen(bottom, Rect2(x + (spacing - 78) / 2, 652, 78, 62), "thorn", Color(def.color), 5)
                var label := _wrapped(bottom, def.word, Rect2(x + 3, 712, spacing - 13, 40), 9 if def.word.length() > 10 else 10, Color("e6d3d8"))
                label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
            var hit := _hit(bottom, rect, _shelf_click.bind(id))
            hit.mouse_entered.connect(_show_peek.bind(id))
            hit.mouse_exited.connect(_hide_peek)
        else:
            var word: Dictionary = state.word_by_id(slot.id)
            var level: int = state.level_of(word.id)
            _panel(bottom, rect, Color("1e2823"), Color("364338"))
            _specimen(bottom, Rect2(x + (spacing - 78) / 2, 654, 78, 68), word.model, Color(word.color), level - 1)
            if level > 1:
                _label(bottom, "Lv%d" % level, Rect2(x + spacing - 44, 656, 36, 20), 11, GOLD if level >= State.MAX_LEVEL else Color("c9b985")).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
            var label := _wrapped(bottom, word.word, Rect2(x + 3, 722, spacing - 13, 32), 11, PAPER)
            label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            var hit := _hit(bottom, rect, _shelf_click.bind(word.id))
            hit.mouse_entered.connect(_show_peek.bind(word.id))
            hit.mouse_exited.connect(_hide_peek)

func _shelf_click(id: String) -> void:
    if is_instance_valid(overlay):
        return
    var slot: int = state.slot_of(id)
    if slot < 0:
        return
    var kind: String = state.slots[slot].kind
    if state.on_board() and mode == "counseling":
        var before: int = state.exp
        var done := false
        if kind == "trauma":
            done = state.appraise(id) if state.trauma_state(id) == "mystery" else state.face(id)
        else:
            done = state.grow(id)
        if done:
            _hide_peek()
            _show_story()
            _animate_exp(before)
        return
    if kind == "trauma":
        _show_trauma(id)
    else:
        _show_word(state.word_by_id(id))

func _peek_action(id: String) -> String:
    # The line under the hovered item: what talking to Minato about it would do.
    var slot: int = state.slot_of(id)
    if slot < 0:
        return ""
    var board: bool = state.on_board() and mode == "counseling"
    if state.slots[slot].kind == "word":
        if not board:
            return ""
        if state.level_of(id) >= State.MAX_LEVEL:
            return "もう、これ以上は育たない"
        var cost: int = state.next_level_cost(id)
        return "強化する？（EXP %s）" % _commas(cost) if state.exp >= cost else "強化には EXP %s（足りない）" % _commas(cost)
    if state.trauma_state(id) == "mystery":
        var open: int = state.appraise_cost(id)
        if not board:
            return "カウンセリングで開ける（EXP %s）" % _commas(open)
        if state.talked:
            return "今日はもう話した"
        return "話してみる？（EXP %s）" % _commas(open) if state.exp >= open else "開くには EXP %s（足りない）" % _commas(open)
    var face: int = state.face_cost(id)
    if board:
        return "向き合う？（EXP %s）" % _commas(face) if state.exp >= face else "向き合うには EXP %s（足りない）" % _commas(face)
    return "向き合うには EXP %s" % _commas(face)

func _show_peek(id: String) -> void:
    # The hovered shelf item comes to the middle of the frame with what it costs.
    _hide_peek()
    if is_instance_valid(overlay) or mode == "title" or state.slot_of(id) < 0:
        return
    peek_id = id
    peek = Control.new()
    peek.mouse_filter = Control.MOUSE_FILTER_IGNORE
    stage.add_child(peek)
    var kind: String = state.slots[state.slot_of(id)].kind
    var rect := Rect2(470, 120, 340, 330)
    if kind == "trauma":
        var def: Dictionary = state.trauma_def(id)
        if state.trauma_state(id) == "mystery":
            _panel(peek, rect, Color(0.06, 0.03, 0.05, 0.94), Color("4a2434"), 6)
            _goo(peek, Rect2(rect.position.x + 70, rect.position.y + 30, 200, 170), state.slot_of(id) * 7 + 3, 1.3)
            _center_label(peek, "？？？", Rect2(rect.position.x, rect.position.y + 214, rect.size.x, 40), 28, Color("c48a98"))
            _center_label(peek, "何かが、重い。", Rect2(rect.position.x, rect.position.y + 256, rect.size.x, 26), 14, Color("9a6f7c"))
        else:
            _panel(peek, rect, Color(0.08, 0.05, 0.07, 0.94), THORN_EDGE, 6)
            _specimen(peek, Rect2(rect.position.x + 70, rect.position.y + 24, 200, 180), "thorn", Color(def.color), 5)
            _center_label(peek, "「%s」" % def.word, Rect2(rect.position.x, rect.position.y + 206, rect.size.x, 40), 22, Color("e6d3d8"))
            _center_label(peek, state.debuff_text(id), Rect2(rect.position.x, rect.position.y + 250, rect.size.x, 26), 14, Color("c48a98"))
        _center_label(peek, _peek_action(id), Rect2(rect.position.x, rect.position.y + 288, rect.size.x, 30), 15, GOLD)
    else:
        var word: Dictionary = state.word_by_id(id)
        var data: Dictionary = state.level_data(id)
        _panel(peek, rect, Color(0.07, 0.1, 0.09, 0.94), Color("364338"), 6)
        _specimen(peek, Rect2(rect.position.x + 70, rect.position.y + 24, 200, 180), word.model, Color(word.color), state.level_of(id) - 1)
        _center_label(peek, "「%s」 Lv%d" % [word.word, state.level_of(id)], Rect2(rect.position.x, rect.position.y + 206, rect.size.x, 40), 22, PAPER)
        _center_label(peek, _hold_text(data), Rect2(rect.position.x, rect.position.y + 250, rect.size.x, 26), 14, Color("a2b49f"))
        _center_label(peek, _peek_action(id), Rect2(rect.position.x, rect.position.y + 288, rect.size.x, 30), 15, GOLD)
    peek.modulate.a = 0.0
    create_tween().bind_node(peek).tween_property(peek, "modulate:a", 1.0, 0.15)

func _hide_peek() -> void:
    peek_id = ""
    if is_instance_valid(peek):
        stage.remove_child(peek)
        peek.queue_free()
    peek = null

func _animate_stats(before: Array) -> void:
    var effective: Array = state.effective_stats()
    for i in range(State.STAT_NAMES.size()):
        if i >= stat_bars.size() or int(before[i]) == effective[i]:
            continue
        var bar: ProgressBar = stat_bars[i]
        var target := float(effective[i])
        var change: int = effective[i] - int(before[i])
        var up: bool = change > 0
        # The meter lunges past its target, snaps back, and glows while the number pops.
        bar.value = before[i]
        bar.pivot_offset = Vector2(0, bar.size.y / 2)
        var motion := create_tween().bind_node(bar)
        motion.tween_property(bar, "value", clampf(target + (8 if up else -8), 0, 100), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        motion.tween_property(bar, "value", target, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
        var glow := create_tween().bind_node(bar)
        bar.modulate = Color(1.8, 1.8, 1.5)
        bar.scale = Vector2(1.0, 2.4)
        glow.set_parallel(true)
        glow.tween_property(bar, "modulate", Color.WHITE, 0.8)
        glow.tween_property(bar, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        var number: Label = stat_labels[i]
        number.text = str(effective[i])
        number.pivot_offset = number.size / 2
        number.scale = Vector2(1.7, 1.7)
        number.add_theme_color_override("font_color", Color("d9e5a3") if up else Color("e8b0a0"))
        var pop := create_tween().bind_node(number)
        pop.set_parallel(true)
        pop.tween_property(number, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        pop.tween_property(number, "theme_override_colors/font_color", PAPER, 1.2)
        _float_text(bar.position + Vector2(10, -12), "%s%d" % ["+" if up else "", change], Color("d9e5a3") if up else Color("e8b0a0"))

func _float_text(at: Vector2, text: String, color: Color) -> void:
    var floating := _label(bottom, text, Rect2(at.x, at.y, 80, 20), 15, color)
    floating.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    var drift := create_tween().bind_node(floating)
    drift.set_parallel(true)
    drift.tween_property(floating, "position:y", floating.position.y - 22, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    drift.tween_property(floating, "modulate:a", 0.0, 1.1).set_delay(0.3)
    drift.chain().tween_callback(floating.queue_free)

func _animate_exp(before: int) -> void:
    if not is_instance_valid(exp_label) or before == state.exp:
        return
    var change: int = state.exp - before
    exp_label.text = "EXP " + _commas(state.exp)
    exp_label.pivot_offset = Vector2(exp_label.size.x, exp_label.size.y / 2)
    exp_label.scale = Vector2(1.25, 1.25)
    var pop := create_tween().bind_node(exp_label)
    pop.tween_property(exp_label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _float_text(Vector2(200, 598), "%s%s" % ["+" if change > 0 else "", _commas(change)], GOLD if change > 0 else Color("e8b0a0"))

func _portrait(parent: Node, who: String, rect: Rect2, speaking: bool) -> TextureRect:
    var paths := {"よだか": "yodaka.png", "あしか": "asika.png", "医師": "doctor.png", "みなと": "doctor.png", "りあ": "mother.png", "すみか": "girl.png"}
    if who == "すみか" and ResourceLoader.exists("res://images/character/sumika.png"):
        paths[who] = "sumika.png"
    var path: String = "res://src/assets/mother_cutout.png" if who == "りあ" else "res://images/character/" + paths[who]
    var picture := _image(parent, path, rect)
    if not portrait_textures.has(path):
        var source: Texture2D = picture.texture
        var pixels := source.get_image()
        if pixels.is_compressed():
            pixels.decompress()
        var region := Rect2(pixels.get_used_rect())
        # Trim empty margins and frame tall full-body art as an upper-body portrait.
        region.size.y = minf(region.size.y, region.size.x * 1.5)
        var atlas := AtlasTexture.new()
        atlas.atlas = source
        atlas.region = region
        portrait_textures[path] = atlas
    picture.texture = portrait_textures[path]
    picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    picture.modulate = Color.WHITE if speaking else Color(0.43, 0.46, 0.46, 1.0)
    portraits[who] = picture
    return picture

func _background_path(place: String) -> String:
    if place == "診察室":
        return "res://src/assets/counseling.png"
    var backgrounds := {"廊下": "hallway", "教室": "classroom", "自宅_リビング": "living",
        "リビング": "living", "自室": "living", "ファミレス": "restaurant", "ファミレス(昼)": "restaurant",
        "喫茶店": "cafe", "自然公園": "park", "街": "street", "街（夕方）": "street", "路上": "street",
        "歩道橋": "street", "ゲームセンター": "street"}
    return "res://src/assets/backgrounds/%s.png" % backgrounds.get(place, "street")

func _show_map() -> void:
    mode = "map"
    auto_mode = false
    body = null
    _base()
    var round_info: Dictionary = state.current_round()
    var week: int = state.round_index + 1
    var remaining: int = int(round_info.outings) - state.outings_done
    _panel(content, Rect2(44, 76, 1192, 516), PAPER)
    var title := _button(content, "← タイトル", Rect2(60, 92, 96, 26), _show_title)
    title.add_theme_font_size_override("font_size", 12)
    _label(content, "MAP  /  第%d週" % week, Rect2(176, 92, 600, 34), 21)
    _image(content, "res://bg.png", Rect2(76, 148, 730, 409))
    _panel(content, Rect2(76, 148, 730, 409), Color(0.05, 0.1, 0.08, 0.18))
    _panel(content, Rect2(830, 148, 374, 409), DARK)
    _label(content, "今日は、どこへ行こう。", Rect2(853, 173, 330, 43), 23, PAPER)
    _label(content, "自由行動　あと %d 回" % remaining, Rect2(853, 232, 330, 40), 26, MINT)
    var note_text := "出かけるのは自由。\n嫌なことがあると、ストレスが上がる。"
    if state.stress_locked():
        note_text = "ストレスが %d。\n疲れていて、今日は出かけられない。\n家で休もう。" % state.effective(0)
    _wrapped(content, note_text, Rect2(854, 292, 320, 200), 16, Color("c8d5c5"))
    # Only places Yodaka can go today are pinned; everything else stays off the map.
    for i in range(state.data.map_events.size()):
        var event: Dictionary = state.data.map_events[i]
        if not state.event_available(event.id):
            continue
        var pin: Array = event.get("pin", [40 + (i % 3) * 240, 30 + (i / 3) * 65])
        var text: String = "●  " + event.label
        if event.get("repeatable", false):
            var relief: Dictionary = state.data.nodes["rest_2"].effects
            if state.debuff_active("rest_half"):
                relief = state.halved(relief)
            text += "（ストレス %d）" % int(relief["ストレス"])
        var width: float = 24 + text.length() * 13
        var button := _button(content, text, Rect2(76 + float(pin[0]), 148 + float(pin[1]), width, 30), _select_map_event.bind(event.id), true)
        button.add_theme_font_size_override("font_size", 13)
        button.add_theme_stylebox_override("normal", _box(MINT, INK, 15))
        button.add_theme_stylebox_override("hover", _box(Color("e0edd7"), INK, 15))
        button.add_theme_stylebox_override("pressed", _box(Color("b5d8a5"), INK, 15))

func _select_map_event(id: String) -> void:
    if state.select_event(id):
        _show_story()

func _show_story() -> void:
    match state.current:
        "map":
            _show_map()
            return
        "result":
            _show_result()
            return
        "counseling":
            _show_counseling()
            return
    mode = "story"
    _render_dialogue(state.data.nodes[state.current])
    _check_interlude()

func _render_dialogue(node: Dictionary) -> void:
    completed = false
    karte_shown = false
    elapsed = 0
    auto_timer = 0
    current_dialogue = node
    portraits.clear()
    preview_labels.clear()
    _base()
    _panel(content, Rect2(44, 76, 1192, 516), PAPER)
    var heading: String = "%02d  /  %s" % [node.chapter_index, node.chapter]
    if node.get("kind", "") == "counsel":
        heading = "COUNSELING  /  " + node.chapter
    elif node.get("kind", "") == "outing":
        heading = "AFTER SCHOOL  /  " + node.chapter
    _label(content, heading, Rect2(76, 92, 840, 34), 17, MUTED)
    _label(content, node.place, Rect2(1040, 96, 160, 30), 14, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var room: bool = node.place == "診察室"
    _image(content, _background_path(node.place), Rect2(76, 143, 1128, 385))
    var partner: String = node.get("partner", "")
    _panel(content, Rect2(76, 329, 1128, 199), Color(0.99, 0.986, 0.965, 0.98), Color("c2c9bb"), 8)
    _panel(content, Rect2(515, 299, 250, 36), INK, Color.TRANSPARENT, 3)
    _center_label(content, node.speaker if node.speaker != "" else "よだか  /  心の声", Rect2(525, 302, 230, 30), 17, PAPER)
    body = RichTextLabel.new()
    body.position = Vector2(328, 347)
    body.size = Vector2(624, 164)
    body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    if node.has("choices") or (mode == "counseling" and state.counsel_step == "grow_choice"):
        body.size.y = 50
    body.bbcode_enabled = true
    body.add_theme_color_override("default_color", INK)
    body.add_theme_font_size_override("normal_font_size", 24)
    body.add_theme_font_size_override("bold_font_size", 24)
    body.add_theme_constant_override("line_separation", 8)
    body.mouse_filter = Control.MOUSE_FILTER_IGNORE
    body.scroll_active = false
    body.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
    var text: String = node.text
    if node.has("word"):
        var word: Dictionary = state.word_by_id(node.word)
        text = text.replace(word.word, "[color=#507549][b][u]" + word.word + "[/u][/b][/color]")
    body.text = "[center]" + text + "[/center]"
    body.visible_characters = 0
    content.add_child(body)
    # Both characters stand in the foreground at equal size and depth.
    if partner != "":
        _portrait(content, partner, Rect2(57, 143, 276, 385), node.speaker == partner or node.speaker == "？？？")
    _portrait(content, "よだか", Rect2(947, 143, 276, 385), node.speaker in ["よだか", ""])
    choice_box = Control.new()
    choice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    content.add_child(choice_box)
    if mode == "counseling" and state.counsel_step == "board":
        next_button = _button(content, "今日は、ここまで  →", Rect2(985, 541, 219, 36), _finish_session, true)
    else:
        next_button = _button(content, "全文を表示  ▷", Rect2(985, 541, 219, 36), _advance, true)
    hint = _label(content, "CLICK / SPACE", Rect2(79, 549, 180, 24), 12, MUTED)
    _button(content, "読み返す", Rect2(283, 541, 135, 36), _show_history)
    if mode == "story":
        _button(content, "AUTO " + ("ON" if auto_mode else "OFF"), Rect2(428, 541, 136, 36), _toggle_auto)
    _button(content, "文字速度", Rect2(574, 541, 135, 36), _show_settings)
    _button(content, "タイトル", Rect2(719, 541, 135, 36), _show_title)
    status.text = "自動保存  /  " + ("診察室" if room else "言葉を集める日")
    last_place = node.place
    active_scene_key = "%d|%s|%s" % [int(node.chapter_index), node.chapter, node.place]

func _check_interlude() -> void:
    if mode not in ["story", "counseling"]:
        return
    if state.scene_key != active_scene_key:
        _show_interlude("scene")
    elif state.pending_word != "" and mode == "story":
        _show_interlude("word")

func _show_interlude(kind: String) -> void:
    _hide_peek()
    overlay_kind = kind
    interlude_ready = false
    overlay = Control.new()
    overlay.size = Vector2(1280, 800)
    overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    overlay.gui_input.connect(_interlude_input)
    stage.add_child(overlay)
    if kind == "scene":
        # Only the frame above the buttons goes dark; the shelf stays in view.
        _panel(overlay, FRAME, Color("0b100e"))
        var heading: String = "CHAPTER  %02d" % current_dialogue.chapter_index
        if current_dialogue.get("kind", "") == "counsel":
            heading = "COUNSELING"
        elif current_dialogue.get("kind", "") == "outing":
            heading = "AFTER SCHOOL"
        _center_label(overlay, heading, Rect2(44, 190, 1192, 40), 15, MINT)
        _center_label(overlay, current_dialogue.chapter, Rect2(44, 250, 1192, 74), 38, PAPER)
        _panel(overlay, Rect2(603, 350, 74, 1), Color("708373"))
        _center_label(overlay, current_dialogue.place.replace("_", " ・ "), Rect2(44, 372, 1192, 40), 20, Color("b5c1b5"))
        _center_label(overlay, "クリックして、つづける", Rect2(44, 470, 1192, 32), 15, Color("8d9c8d"))
    else:
        _panel(overlay, Rect2(0, 0, 1280, 800), Color("0b100e"))
        _draw_receive()
    overlay.modulate.a = 0
    interlude_tween = create_tween()
    interlude_tween.tween_property(overlay, "modulate:a", 1.0, 0.45)
    interlude_tween.tween_callback(func(): interlude_ready = true)
    # Buttons underneath must not retain keyboard focus during an interlude.
    var focused := get_viewport().gui_get_focus_owner()
    if focused != null:
        focused.release_focus()

func _draw_receive() -> void:
    # A word arrives: keep it on the shelf, or let it go and turn it into EXP.
    var word: Dictionary = state.word_by_id(state.pending_word)
    var level: Dictionary = word.levels[0]
    _center_label(overlay, "言葉を、ひとつもらった。", Rect2(90, 60, 1100, 42), 18, MINT)
    var effect = WordEffect.new()
    effect.position = Vector2(140, 90)
    effect.size = Vector2(400, 350)
    effect.tint = Color(word.color)
    overlay.add_child(effect)
    _specimen(overlay, Rect2(205, 132, 270, 255), word.model, Color(word.color))
    _center_label(overlay, "「%s」" % word.word, Rect2(40, 400, 600, 56), 32, PAPER)
    _center_label(overlay, word.speaker + " から、よだかへ", Rect2(40, 456, 600, 30), 16, Color("a8b7a8"))
    var delta: Array = state.gains.get(word.id, [])
    _center_label(overlay, _delta_text(delta) if not delta.is_empty() else "", Rect2(40, 488, 600, 30), 17, Color("d9e5a3"))
    _panel(overlay, Rect2(660, 100, 540, 430), Color("141c1a"), Color("36453d"), 4)
    _label(overlay, "どうする？", Rect2(684, 116, 400, 30), 20, PAPER)
    _wrapped(overlay, "持っていると：" + _hold_text(level) + "\n手放すと：EXP +%s" % _commas(state.forget_value(word.id)), Rect2(684, 152, 500, 60), 14, Color("c8d5c5"))
    var free: int = state.free_slot()
    if free >= 0:
        _button(overlay, "心に留める", Rect2(684, 262, 492, 48), _decide_word.bind("keep", -1), true)
        _button(overlay, "手放して EXP +%s にする" % _commas(state.forget_value(word.id)), Rect2(684, 322, 492, 48), _decide_word.bind("release", -1))
    else:
        var held: Array = state.held_words()
        if held.is_empty():
            _wrapped(overlay, "棚に空きがない。\nカウンセリングでトラウマと向き合うと、枠が空く。", Rect2(684, 250, 500, 70), 14, Color("e6d3d8"))
        else:
            _wrapped(overlay, "枠がない。留めるには、どれかを手放す。", Rect2(684, 250, 500, 24), 14, Color("e6d3d8"))
            for i in range(mini(held.size(), 4)):
                var other: Dictionary = state.word_by_id(held[i])
                var button := _button(overlay, "「%s」を手放して留める（EXP +%s）" % [other.word, _commas(state.forget_value(other.id))], Rect2(684, 280 + i * 44, 492, 38), _decide_word.bind("swap", state.slot_of(other.id)))
                button.add_theme_font_size_override("font_size", 14)
        _button(overlay, "手放して EXP +%s にする" % _commas(state.forget_value(word.id)), Rect2(684, 468, 492, 44), _decide_word.bind("release", -1), true)

func _decide_word(action: String, slot: int) -> void:
    if overlay_kind != "word" or not interlude_ready or state.pending_word == "":
        return
    var before: int = state.exp
    match action:
        "keep":
            if not state.keep_pending():
                return
        "release":
            state.release_pending()
        "swap":
            if state.swap_pending(slot) == 0:
                return
    _draw_bottom()
    _animate_exp(before)
    _dismiss_interlude()

func _interlude_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        overlay.accept_event()
        if overlay_kind != "word":
            _dismiss_interlude()

func _dismiss_interlude() -> void:
    if not interlude_ready or overlay_kind not in ["scene", "word"]:
        return
    if overlay_kind == "word" and state.pending_word != "":
        return  # the word must be kept or let go with the buttons
    interlude_ready = false
    var kind := overlay_kind
    interlude_tween = create_tween()
    interlude_tween.tween_property(overlay, "modulate:a", 0.0, 0.3)
    interlude_tween.tween_callback(func():
        if kind == "scene":
            state.scene_key = active_scene_key
        state.save_game()
        overlay_kind = "modal"
        _close_overlay()
        auto_timer = 0
        _check_interlude())

func _finish_line() -> void:
    if completed or is_instance_valid(overlay):
        return
    completed = true
    body.visible_characters = -1
    var added := false
    var before: Array = state.effective_stats()
    var exp_before: int = state.exp
    if mode == "story":
        added = state.finish_line()
    else:
        state.read_dynamic("counsel_%d_%s_%s" % [state.session, state.counsel_step, state.focus + state.grow_word], current_dialogue.speaker, current_dialogue.text)
    if added:
        _draw_bottom()
        _animate_stats(before)
        hint.text = "＋ 言葉をもらった"
    else:
        _animate_exp(exp_before)
        if state.has_change(state.last_delta):
            _animate_stats(before)
            hint.text = _delta_text(state.last_delta)
    if state.last_error != "":
        status.text = state.last_error
    if mode == "counseling" and state.counsel_step == "board":
        hint.text = "棚から、ひとつ選ぶ"
    elif current_dialogue.get("karte", false):
        next_button.text = "カルテを見る  →"
    else:
        next_button.text = "つづきを読む  →"
    if mode == "counseling" and state.counsel_step == "grow_choice":
        _counsel_choices()
    elif mode == "counseling" and state.counsel_step == "talk_recall":
        _reveal_panel()
    elif current_dialogue.has("choices"):
        next_button.visible = false
        _panel(choice_box, Rect2(333, 414, 614, 103), PAPER)
        for i in range(current_dialogue.choices.size()):
            var width: float = 614.0 / current_dialogue.choices.size()
            var choice: Dictionary = current_dialogue.choices[i]
            var button := _button(choice_box, choice.text, Rect2(337 + i * width, 424, width - 12, 54), _story_choice.bind(i), true)
            button.add_theme_font_size_override("font_size", 17)
            button.disabled = not state.can_choose(i)
            var note := ""
            if choice.has("requires"):
                var k: int = State.STAT_NAMES.find(choice.requires.stat)
                note = "%s %d 必要（現在 %d）" % [choice.requires.stat, choice.requires.min, state.effective(k)]
            elif choice.has("effects"):
                note = _preview_text(choice.effects, state.preview(choice.effects))
                preview_labels.append(note)
            if note != "":
                _center_label(choice_box, note, Rect2(337 + i * width, 482, width - 12, 26), 12, MUTED)
    if added:
        _show_interlude("word")

func _advance() -> void:
    if mode not in ["story", "counseling"] or is_instance_valid(overlay) or not is_instance_valid(body):
        return
    if not completed:
        _finish_line()
        return
    if current_dialogue.get("karte", false) and not karte_shown:
        _show_karte(func():
            karte_shown = true
            next_button.text = "つづきを読む  →")
        return
    if mode == "counseling":
        _advance_counseling()
        return
    if current_dialogue.has("choices"):
        return
    state.choose(0)
    _show_story()

func _story_choice(index: int) -> void:
    if is_instance_valid(overlay) or mode != "story":
        return
    var before: Array = state.effective_stats()
    if not state.choose(index):
        return
    _show_story()
    if state.has_change(state.last_delta):
        _animate_stats(before)

func _toggle_auto() -> void:
    auto_mode = not auto_mode
    # Rebuild only the button label; do not restart the line being read.
    for child in content.get_children():
        if child is Button and child.text.begins_with("AUTO"):
            child.text = "AUTO " + ("ON" if auto_mode else "OFF")
    auto_timer = 0

func _process(delta: float) -> void:
    if mode not in ["story", "counseling"] or is_instance_valid(overlay) or not is_instance_valid(body):
        return
    if not completed:
        elapsed += delta * state.speed
        body.visible_characters = int(elapsed)
        if body.visible_characters >= body.get_total_character_count():
            _finish_line()
    elif mode == "story" and auto_mode and not current_dialogue.has("choices") and not current_dialogue.get("karte", false):
        auto_timer += delta
        if auto_timer > 2.2 + body.get_total_character_count() * 0.025:
            _advance()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            if is_instance_valid(overlay):
                _close_overlay()
            return
        if event.keycode in [KEY_SPACE, KEY_ENTER]:
            _advance()
            get_viewport().set_input_as_handled()
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if mode in ["story", "counseling"] and is_instance_valid(body) and Rect2(44, 76, 1192, 450).has_point(stage.get_local_mouse_position()):
            _advance()

# --- Counseling -------------------------------------------------------------

func _session_title() -> String:
    match state.session:
        1:
            return "はじめてのカウンセリング"
        State.SESSIONS:
            return "総括のカウンセリング"
    return "%d回目のカウンセリング" % state.session

func _show_counseling() -> void:
    mode = "counseling"
    auto_mode = false
    feedback = false
    var step: String = state.counsel_step
    var speaker := "みなと"
    var text := ""
    var trauma: Dictionary = state.trauma_def(state.focus) if state.focus != "" else {}
    var word: Dictionary = state.word_by_id(state.grow_word) if state.grow_word != "" else {}
    match step:
        "opening_doctor":
            if state.session == 1:
                text = "最後に、ひとつだけ。\n法月さんの中に残っている言葉を、ひとつ聞かせてください。"
            elif state.is_closing():
                text = "こんにちは、法月さん。\n最後の数週間は、どうでしたか？"
            else:
                text = "こんにちは、法月さん。\nこの数週間は、どうでしたか？"
        "opening_yodaka":
            speaker = "よだか"
            if state.session == 1:
                text = "……残っている言葉、ですか。"
            elif state.collected.is_empty():
                text = "……いろいろ言われた気がするのに、\nどれも、うまく思い出せません。"
            else:
                text = "いろんな人と話しました。\n言葉を%d個、持ち帰ってきました。" % state.collected.size()
        "board":
            if state.talked:
                text = "ほかに、話しておきたい言葉はありますか？\n無ければ、今日はここまでにしましょう。"
            elif state.session == 1:
                text = "棚にある言葉を、ひとつ選んでください。\nまだ、何かわからないままでいい。"
            else:
                text = "棚から、ひとつ選んで聞かせてください。\n持っている言葉の話でも構いません。"
        "talk_recall":
            speaker = "よだか"
            text = trauma.recall
        "talk_doctor":
            text = trauma.doctor
        "face_line":
            speaker = "よだか"
            text = trauma.resolve
        "face_response":
            text = trauma.response
        "grow_question":
            text = "「%s」……。\n法月さんは、その時どう感じましたか？" % word.word
        "grow_choice":
            speaker = "よだか"
            text = "あの時、僕は……。"
        "grow_reply":
            speaker = "よだか"
            text = word.interpretations[int(state.answer_for(word.id).choice)].reply
        "grow_insight":
            speaker = "よだか"
            text = state.level_data(word.id).insight
        "grow_response":
            text = INSIGHT_RESPONSE if state.level_of(word.id) >= State.MAX_LEVEL else RESPONSES[int(state.answer_for(word.id).choice)]
        "closing":
            if state.is_closing():
                text = "お話しいただきありがとうございます。\nこちらが、今回の「メンタル〇〇」になります。"
            else:
                text = "お話しいただきありがとうございます。\n今日は、ここまでにしましょう。"
        "farewell":
            if state.is_closing():
                text = "受け取った言葉を飾って、ときには整理して。\n居心地よくいられる時間が、少しでも続きますように。\nでは、お大事にどうぞ。法月さん"
            else:
                text = "受け取った言葉を飾って、ときには整理して。\nでは次回まで、お大事にどうぞ。法月さん"
    _render_dialogue({"speaker": speaker, "text": text, "chapter": _session_title(),
        "chapter_index": 0, "kind": "counsel", "place": "診察室", "partner": "みなと", "karte": step == "closing" and state.is_closing()})
    status.text = "カウンセリング  /  よだかとみなと"
    if step == "grow_reply":
        body.size.y = 145
        _center_label(content, _delta_text(state.answer_for(word.id).delta), Rect2(333, 501, 614, 24), 15, Color("597c51"))
    _check_interlude()

func _reveal_panel() -> void:
    # The mystery opens: its crystal and its words appear in front of the room.
    var def: Dictionary = state.trauma_def(state.focus)
    var card := _panel(content, Rect2(440, 150, 400, 150), Color(0.07, 0.05, 0.07, 0.88), THORN_EDGE, 6)
    _specimen(card, Rect2(8, 4, 140, 140), "thorn", Color(def.color), 5)
    _wrapped(card, "「%s」" % def.word, Rect2(150, 22, 240, 60), 18, Color("e6d3d8"))
    _wrapped(card, state.debuff_text(def.id), Rect2(150, 84, 240, 50), 13, Color("c48a98"))
    card.modulate.a = 0.0
    create_tween().bind_node(card).tween_property(card, "modulate:a", 1.0, 0.8)

func _finish_session() -> void:
    if not state.on_board() or is_instance_valid(overlay):
        return
    _hide_peek()
    state.finish_session()
    _show_story()

func _advance_counseling() -> void:
    if state.counsel_step in ["board", "grow_choice"]:
        return
    var before: Array = state.effective_stats()
    state.advance_counseling()
    _show_story()
    if mode == "counseling":
        _animate_stats(before)

func _delta_text(delta: Array) -> String:
    var parts: PackedStringArray = []
    for i in range(mini(delta.size(), State.STAT_NAMES.size())):
        if delta[i] != 0:
            parts.append("%s %s%d" % [State.STAT_NAMES[i], "+" if delta[i] > 0 else "", delta[i]])
    return "   /   ".join(parts) if not parts.is_empty() else "変化なし（上限・下限に達しています）"

func _preview_text(effects: Dictionary, delta: Array) -> String:
    var parts: PackedStringArray = []
    for stat in effects:
        var k: int = State.STAT_NAMES.find(stat)
        if k < 0:
            continue
        var suffix := ""
        if delta[k] == 0:
            suffix = "（上限）" if int(effects[stat]) > 0 else "（下限）"
        parts.append("%s %s%d%s" % [stat, "+" if delta[k] > 0 else "", delta[k], suffix])
    return "   /   ".join(parts)

func _hold_text(level: Dictionary) -> String:
    var parts: PackedStringArray = []
    for key in level.hold:
        match key:
            "exp_mult":
                parts.append("1タップのEXP ×%d" % int(level.hold[key]))
            "forget_mult":
                parts.append("手放すEXP ×%d" % int(level.hold[key]))
            "cost_mult":
                parts.append("向き合うEXP ×%s" % str(level.hold[key]))
            _:
                parts.append("%s %s%d" % [key, "+" if int(level.hold[key]) > 0 else "", int(level.hold[key])])
    return "、".join(parts) if not parts.is_empty() else "—"

func _counsel_choices() -> void:
    next_button.visible = false
    var word: Dictionary = state.word_by_id(state.grow_word)
    for i in range(3):
        var interpretation: Dictionary = word.interpretations[i]
        var delta: Array = state.preview(interpretation.effects)
        var lines: PackedStringArray = [interpretation.label, ""]
        for stat in interpretation.effects:
            var k: int = State.STAT_NAMES.find(stat)
            var suffix := ""
            if delta[k] == 0:
                suffix = "（上限）" if int(interpretation.effects[stat]) > 0 else "（下限）"
            lines.append("%s %s%d%s" % [stat, "+" if delta[k] > 0 else "", delta[k], suffix])
        var button := _button(choice_box, "\n".join(lines), Rect2(337 + i * 204, 408, 194, 111), _interpret.bind(i), false)
        button.add_theme_font_size_override("font_size", 14)
        preview_labels.append(button.text)
    hint.text = "よだかの気持ちを選ぶ"
    hint.add_theme_font_size_override("font_size", 12)

func _interpret(index: int) -> void:
    if feedback or state.counsel_step != "grow_choice" or not completed or is_instance_valid(overlay):
        return
    feedback = true
    var before: Array = state.effective_stats()
    var delta: Array = state.interpret(index)
    if delta.is_empty():
        feedback = false
        return
    _show_counseling()
    _animate_stats(before)

func _stress_note() -> String:
    var stress: int = state.effective(0)
    if stress < 35:
        return "落ち着いている"
    if stress < 60:
        return "少し疲れている"
    if stress < State.STRESS_LIMIT:
        return "かなり疲れている"
    return "限界が近い。出かける前に休もう"

func _show_karte(on_close: Callable) -> void:
    _hide_peek()
    var card := _new_overlay("メンタル〇〇（仮）  /  いまのカルテ")
    _label(card, "法月 よだか　　状態：" + _stress_note(), Rect2(36, 74, 400, 30), 15, MUTED)
    var effective: Array = state.effective_stats()
    for i in range(State.STAT_NAMES.size()):
        var y: int = 130 + i * 70
        _label(card, State.STAT_NAMES[i], Rect2(40, y, 100, 30), 21)
        var bar := ProgressBar.new()
        bar.position = Vector2(140, y + 9)
        bar.size = Vector2(200, 16)
        bar.show_percentage = false
        bar.add_theme_font_size_override("font_size", 1)
        bar.value = effective[i]
        bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bar.add_theme_stylebox_override("background", _box(Color("e4e6df")))
        bar.add_theme_stylebox_override("fill", _box(Color("c98f7c") if i == 0 else Color("7fae70")))
        card.add_child(bar)
        bar.size = Vector2(200, 16)
        _label(card, str(effective[i]), Rect2(352, y, 80, 30), 21)
    # The mental map: darkness that each kept word lights up, wider with every level.
    var map = MindMap.new()
    map.position = Vector2(440, 100)
    map.size = Vector2(375, 412)
    card.add_child(map)
    var held: Array = state.held_words()
    var count: int = held.size()
    for i in range(count):
        var word: Dictionary = state.word_by_id(held[i])
        map.lit.append({"pos": map.node_position(i, count), "color": Color(word.color), "crystals": (state.level_of(word.id) - 1) * 3})
    for i in range(state.forgotten.size()):
        var word: Dictionary = state.word_by_id(state.forgotten[i])
        map.embers.append({"pos": map.node_position(count + i, count + state.forgotten.size()) * 0.5 + map.size * 0.25, "color": Color(word.color)})
    map.unknown = maxi(0, state.data.words.size() - count - state.forgotten.size())
    for i in range(count):
        var word: Dictionary = state.word_by_id(held[i])
        var spot: Vector2 = map.position + map.node_position(i, count)
        _specimen(card, Rect2(spot.x - 30, spot.y - 38, 60, 56), word.model, Color(word.color), state.level_of(word.id) - 1)
        var label := _wrapped(card, word.word, Rect2(spot.x - 55, spot.y + 18, 110, 30), 10, PAPER)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    if on_close.is_valid():
        for child in card.get_children():
            if child is Button:
                child.pressed.connect(on_close)

func _show_result() -> void:
    mode = "result"
    body = null
    _base()
    _panel(content, Rect2(44, 76, 1192, 516), PAPER)
    _label(content, "EPILOGUE  /  総括のカウンセリング", Rect2(85, 109, 800, 32), 16, MUTED)
    _label(content, "答えは、まだ途中でいい。", Rect2(80, 164, 1100, 72), 44)
    _label(content, "みなと", Rect2(87, 260, 140, 30), 18, MUTED)
    _label(content, "法月さん自身の言葉で、聞かせてくれましたね。\n受け入れることも、受け入れないことも、今は決めないことも。\nまた言葉が増えたら、一緒に考えましょう。", Rect2(86, 311, 950, 122), 24)
    _label(content, "言葉 %d 個をもらい、%d 個を留めた。　向き合ったトラウマ %d。　EXP 合計 %s" % [state.collected.size(), state.held_words().size(), state.accepted_count(), _commas(state.exp_total)], Rect2(86, 450, 1100, 38), 15, MUTED)
    _button(content, "タイトルへ", Rect2(87, 521, 238, 48), _show_title, true)
    _button(content, "振り返りの記録", Rect2(342, 521, 255, 48), _show_reflections)
    _button(content, "カルテ", Rect2(614, 521, 160, 48), _show_karte.bind(Callable()))
    _label(content, "END OF PROTOTYPE", Rect2(843, 532, 352, 28), 16, MUTED)

func _new_overlay(title: String) -> Panel:
    _hide_peek()
    overlay_kind = "modal"
    overlay = Control.new()
    overlay.size = Vector2(1280, 800)
    overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    stage.add_child(overlay)
    _panel(overlay, Rect2(0, 0, 1280, 800), Color(0.05, 0.1, 0.08, 0.78))
    var card := _panel(overlay, Rect2(215, 96, 850, 590), PAPER, Color("b2bcae"), 4)
    card.mouse_filter = Control.MOUSE_FILTER_STOP
    _label(card, title, Rect2(34, 24, 710, 45), 28)
    _button(card, "閉じる  ×", Rect2(665, 521, 146, 42), _close_overlay)
    return card

func _close_overlay() -> void:
    if overlay_kind in ["scene", "word"]:
        return
    if is_instance_valid(overlay):
        stage.remove_child(overlay)
        overlay.queue_free()
        overlay = null
        overlay_kind = ""

func _modal(title: String, text: String, action: String, callback: Callable) -> void:
    var card := _new_overlay(title)
    _wrapped(card, text, Rect2(36, 118, 775, 140), 23)
    _button(card, action, Rect2(35, 520, 300, 44), callback, true)

func _show_word(word: Dictionary) -> void:
    var card := _new_overlay("「%s」" % word.word)
    var level: int = state.level_of(word.id)
    var data: Dictionary = state.level_data(word.id)
    _label(card, "%s からもらった言葉　·　Lv%d" % [word.speaker, level], Rect2(36, 82, 740, 32), 18, MUTED)
    _panel(card, Rect2(37, 147, 219, 273), DARK)
    _specimen(card, Rect2(47, 170, 198, 228), word.model, Color(word.color), level - 1)
    _wrapped(card, word.quote, Rect2(291, 150, 520, 150), 21)
    _wrapped(card, "持っていると：" + _hold_text(data) + "\n手放すと：EXP +%s" % _commas(state.forget_value(word.id)), Rect2(291, 320, 520, 60), 15, Color("597c51"))
    var answer: Dictionary = state.answer_for(word.id)
    if not answer.is_empty():
        _label(card, "受け取り方：%s" % word.interpretations[int(answer.choice)].label, Rect2(291, 390, 520, 30), 15, MUTED)
    if state.slot_of(word.id) >= 0 and mode in ["story", "map", "counseling"]:
        var forget := _button(card, "手放す（EXP +%s）" % _commas(state.forget_value(word.id)), Rect2(291, 521, 240, 42), _confirm_forget.bind(word))
        forget.disabled = state.pending_word != "" or (mode == "counseling" and not state.on_board())

func _confirm_forget(word: Dictionary) -> void:
    _close_overlay()
    _modal("「%s」を手放す" % word.word, "手放すと EXP +%s。棚から消えて、戻らない。" % _commas(state.forget_value(word.id)), "手放す", func():
        _close_overlay()
        var before: int = state.exp
        if state.forget_word(word.id) > 0:
            _draw_bottom()
            _animate_exp(before))

func _show_trauma(id: String) -> void:
    var def: Dictionary = state.trauma_def(id)
    if state.trauma_state(id) == "mystery":
        var card := _new_overlay("？？？")
        _panel(card, Rect2(37, 90, 219, 330), Color("17090f"))
        _goo(card, Rect2(37, 90, 219, 330), state.slot_of(id) * 7 + 3, 1.2)
        _wrapped(card, "何かが、重い。\n何の言葉かは、まだ思い出せない。", Rect2(291, 150, 520, 100), 21)
        _wrapped(card, "カウンセリングでみなとに話すと開く（EXP %s）。\n開いたが最後、もっと大変になるかもしれない。" % _commas(state.appraise_cost(id)), Rect2(291, 300, 520, 80), 15, MUTED)
        return
    var card := _new_overlay("「%s」" % def.word)
    _label(card, "%s の言葉" % def.speaker, Rect2(36, 82, 740, 32), 18, MUTED)
    _panel(card, Rect2(37, 147, 219, 273), THORN)
    _specimen(card, Rect2(47, 170, 198, 228), "thorn", Color(def.color), 5)
    _wrapped(card, def.quote, Rect2(291, 150, 520, 150), 21)
    _wrapped(card, "影響：" + state.debuff_text(id), Rect2(291, 300, 520, 30), 15, Color("7a4a5a"))
    _wrapped(card, "向き合うには EXP %s（持っている %s）。\nカウンセリングで、みなとに話すと向き合える。" % [_commas(state.face_cost(id)), _commas(state.exp)], Rect2(291, 340, 520, 80), 15, MUTED)

func _scroll_text(card: Panel, text: String) -> void:
    var rich := RichTextLabel.new()
    rich.position = Vector2(36, 91)
    rich.size = Vector2(776, 403)
    rich.bbcode_enabled = true
    rich.text = text
    rich.add_theme_color_override("default_color", INK)
    rich.add_theme_font_size_override("normal_font_size", 20)
    rich.add_theme_constant_override("line_separation", 6)
    card.add_child(rich)

func _show_history() -> void:
    var card := _new_overlay("読み返す")
    var text := ""
    for entry in state.history:
        text += "[color=#6b8563]" + (entry.speaker if entry.speaker != "" else "心の声") + "[/color]\n" + entry.text + "\n\n"
    _scroll_text(card, text if text != "" else "読み終えた文章がここに残ります。")

func _show_reflections() -> void:
    var card := _new_overlay("振り返りの記録")
    var text := ""
    for id in state.held_words():
        var word: Dictionary = state.word_by_id(id)
        var answer: Dictionary = state.answer_for(id)
        var line: String = "Lv%d" % state.level_of(id)
        if not answer.is_empty():
            line += "　·　" + word.interpretations[int(answer.choice)].label
        text += "[color=#6b8563]「%s」 / %s[/color]\n%s\n\n" % [word.word, word.speaker, line]
    for id in state.forgotten:
        var word: Dictionary = state.word_by_id(id)
        text += "[color=#9a9a9a]「%s」 / %s　—　手放した[/color]\n\n" % [word.word, word.speaker]
    for id in state.traumas:
        var def: Dictionary = state.trauma_def(id)
        match state.trauma_state(id):
            "mystery":
                text += "[color=#8a5a6a]？？？[/color]\nまだ開いていない\n\n"
            "appraised":
                text += "[color=#8a5a6a]「%s」 / %s[/color]\n開いた。向き合うには EXP %s\n\n" % [def.word, def.speaker, _commas(state.face_cost(id))]
            _:
                text += "[color=#8a5a6a]「%s」 / %s[/color]\n向き合って、受け入れた\n\n" % [def.word, def.speaker]
    text += "自認は、自分の捉え方への納得度です。\n数値は物語の中の気持ちを表す、プロトタイプ用の表現です。"
    _scroll_text(card, text)

func _show_settings() -> void:
    var card := _new_overlay("文字送りの速さ")
    _label(card, "クリック / Space：全文表示 → 次の文章\n選択肢では AUTO も止まります。\n進行と集めた言葉は、このブラウザに自動保存されます。", Rect2(36, 104, 780, 138), 21)
    var slider := HSlider.new()
    slider.position = Vector2(41, 309)
    slider.size = Vector2(730, 44)
    slider.min_value = 12
    slider.max_value = 80
    slider.value = state.speed
    slider.value_changed.connect(func(value):
        state.speed = value
        state.save_game())
    card.add_child(slider)
    _label(card, "ゆっくり                                              はやく", Rect2(37, 373, 770, 35), 20, MUTED)
