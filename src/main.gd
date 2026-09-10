extends Control

const State = preload("res://src/story_state.gd")
const Specimen = preload("res://src/specimen.gd")
const WordEffect = preload("res://src/word_effect.gd")
const INK = Color("252c2a")
const MUTED = Color("778078")
const PAPER = Color("fcfbf6")
const MINT = Color("c7e5ba")
const DARK = Color("171e1c")
const ANSWERS = ["嬉しかった", "自分らしくないと思った", "まだ、わからない"]
var state = State.new()
var stage: Control
var content: Control
var bottom: Control
var overlay: Control
var body: RichTextLabel
var next_button: Button
var choice_box: Control
var hint: Label
var status: Label
var count_label: Label
var stat_bars: Array = []
var stat_labels: Array = []
var mode: String = "title"
var elapsed: float = 0.0
var completed: bool = false
var auto_mode: bool = false
var auto_timer: float = 0.0
var feedback: bool = false
var screen_epoch: int = 0
var overlay_kind: String = ""
var interlude_ready: bool = false
var interlude_tween: Tween
var active_scene_key: String = ""
var current_dialogue: Dictionary = {}
var portraits: Dictionary = {}
var portrait_textures: Dictionary = {}
var preview_labels: Array = []

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

func _box(color: Color, border: Color = Color.TRANSPARENT, radius: int = 0) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = color
    box.border_color = border
    box.set_border_width_all(1 if border.a > 0 else 0)
    box.set_corner_radius_all(radius)
    return box

func _panel(parent: Node, rect: Rect2, color: Color, border: Color = Color.TRANSPARENT, radius: int = 0) -> Panel:
    var panel := Panel.new()
    panel.position = rect.position
    panel.size = rect.size
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_theme_stylebox_override("panel", _box(color, border, radius))
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

func _base() -> void:
    screen_epoch += 1
    _clear(stage)
    overlay = null
    overlay_kind = ""
    _image(stage, "res://bg.png", Rect2(0, 0, 1280, 800))
    _panel(stage, Rect2(0, 0, 1280, 800), Color(0.10, 0.15, 0.14, 0.45))
    status = _label(stage, "WEB PROTOTYPE  /  02", Rect2(927, 25, 310, 26), 13, Color("dce5d9"))
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
    _label(content, "誰かにもらった言葉を、わたしの中に。", Rect2(91, 110, 580, 35), 20, MUTED)
    _label(content, "よだか", Rect2(81, 154, 570, 130), 92)
    _label(content, "こ と ば の 標 本", Rect2(93, 295, 500, 45), 28)
    _label(content, "変わった身体。まだ、名前のない気持ち。\n出会った言葉を集めて、ゆっくり自分を考える。", Rect2(94, 361, 580, 72), 20)
    _button(content, "はじめから   →", Rect2(94, 470, 245, 57), _start_new, true)
    var resume := _button(content, "つづきから", Rect2(355, 470, 230, 57), _resume)
    resume.disabled = not state.has_save()
    _label(content, "全6章 ＋ 寄り道とカウンセリング", Rect2(94, 545, 550, 25), 14, MUTED)
    _panel(content, Rect2(870, 530, 320, 40), PAPER)
    _label(content, "法月 よだか  /  主人公", Rect2(895, 534, 275, 30), 17)
    _label(stage, "CLICK / SPACE  文字送り     ·     言葉の標本をクリックすると読み返せます", Rect2(44, 777, 1160, 20), 13, PAPER)

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
        _modal("保存を読み込めませんでした", "保存データの形式を確認できませんでした。\n「はじめから」で新しく遊べます。", "閉じる", _close_overlay)

func _draw_bottom() -> void:
    _clear(bottom)
    stat_bars.clear()
    stat_labels.clear()
    _panel(bottom, Rect2(44, 612, 224, 155), DARK)
    _label(bottom, "いまの輪郭", Rect2(59, 620, 170, 23), 14, Color("d9e5d3"))
    for i in range(6):
        _label(bottom, State.STAT_NAMES[i], Rect2(60, 650 + i * 18, 78, 18), 12, Color("b9c1b8"))
        var bar := ProgressBar.new()
        bar.position = Vector2(141, 655 + i * 18)
        bar.size = Vector2(76, 6)
        bar.show_percentage = false
        bar.add_theme_font_size_override("font_size", 1)
        bar.value = state.stats[i]
        bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bar.add_theme_stylebox_override("background", _box(Color("36403a")))
        bar.add_theme_stylebox_override("fill", _box(Color("d1b6aa") if i == 0 else MINT))
        bottom.add_child(bar)
        bar.size = Vector2(76, 6)
        stat_bars.append(bar)
        stat_labels.append(_label(bottom, str(int(state.stats[i])), Rect2(225, 647 + i * 18, 32, 20), 12, PAPER))
    _panel(bottom, Rect2(280, 612, 956, 155), DARK)
    _label(bottom, "もらった言葉", Rect2(296, 619, 270, 26), 15, PAPER)
    count_label = _label(bottom, "%02d 個    ·    読んだ言葉 %03d" % [state.collected.size(), state.read_count], Rect2(893, 620, 325, 24), 13, Color("a2b49f"))
    count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var slots: int = maxi(8, state.collected.size())
    var spacing: float = 928.0 / slots
    for i in range(slots):
        var x: float = 294 + i * spacing
        _panel(bottom, Rect2(x, 653, spacing - 7, 103), Color("1e2823"), Color("364338"))
        _label(bottom, "%02d" % (i + 1), Rect2(x + 6, 657, 28, 20), 11, Color("81947f"))
        if i < state.collected.size():
            var word: Dictionary = state.word_by_id(state.collected[i])
            var specimen = Specimen.new()
            specimen.position = Vector2(x + (spacing - 78) / 2, 654)
            specimen.size = Vector2(78, 68)
            bottom.add_child(specimen)
            specimen.setup(word.model, Color(word.color))
            var label := _label(bottom, word.word, Rect2(x + 3, 722, spacing - 13, 32), 11, PAPER)
            label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            var hit := Button.new()
            hit.position = Vector2(x, 653)
            hit.size = Vector2(spacing - 7, 103)
            hit.flat = true
            hit.tooltip_text = "「%s」を読み返す" % word.word
            hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
            hit.pressed.connect(_show_word.bind(word))
            bottom.add_child(hit)
        else:
            _label(bottom, "·", Rect2(x + 49, 675, 20, 30), 28, Color("465344"))
            _label(bottom, "まだない言葉", Rect2(x + 16, 730, 95, 20), 10, Color("637460"))

func _portrait(parent: Node, who: String, rect: Rect2, speaking: bool) -> TextureRect:
    var paths := {"よだか": "yodaka.png", "あしか": "asika.png", "医師": "doctor.png", "りあ": "mother.png", "すみか": "girl.png"}
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

func _center_label(parent: Node, text: String, rect: Rect2, font_size: int = 18, color: Color = INK) -> Label:
    var label := _label(parent, text, rect, font_size, color)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    return label

func _background_path(place: String) -> String:
    if place == "診察室":
        return "res://src/assets/counseling.png"
    var backgrounds := {"廊下": "hallway", "教室": "classroom", "自宅_リビング": "living",
        "リビング": "living", "ファミレス": "restaurant", "ファミレス(昼)": "restaurant",
        "喫茶店": "cafe", "自然公園": "park", "街": "street"}
    return "res://src/assets/backgrounds/%s.png" % backgrounds.get(place, "street")

func _show_map() -> void:
    mode = "map"
    auto_mode = false
    _base()
    _panel(content, Rect2(44, 76, 1192, 516), PAPER)
    _label(content, "MAP  /  放課後の寄り道", Rect2(77, 94, 780, 38), 23)
    _image(content, "res://bg.png", Rect2(76, 148, 730, 409))
    _panel(content, Rect2(830, 148, 374, 409), DARK)
    _label(content, "今日は、どこへ行こう。", Rect2(853, 173, 330, 43), 23, PAPER)
    var note := _label(content, "寄り道は、ひとつだけ。\n\nそのあと診察室で、今週のことを\nドクターに話してみよう。\n\n言葉を振り返ったら、\nCHAPTER 6へ。", Rect2(854, 242, 320, 255), 18, Color("c8d5c5"))
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var positions := [Vector2(105, 210), Vector2(475, 290), Vector2(232, 421)]
    for i in range(state.data.map_events.size()):
        var event: Dictionary = state.data.map_events[i]
        _button(content, "%02d  %s\n%s" % [i + 1, event.label, event.title], Rect2(positions[i], Vector2(286, 79)), _select_map_event.bind(event.id), true)
    _button(content, "タイトル", Rect2(854, 509, 160, 38), _show_title)

func _select_map_event(id: String) -> void:
    if state.select_event(id):
        _show_story()

func _show_story() -> void:
    if state.current == "map":
        _show_map()
        return
    if state.current == "result":
        _show_result()
        return
    if state.current == "counseling":
        _show_counseling()
        return
    mode = "story"
    _render_dialogue(state.data.nodes[state.current])
    _check_interlude()

func _render_dialogue(node: Dictionary) -> void:
    completed = false
    elapsed = 0
    auto_timer = 0
    current_dialogue = node
    portraits.clear()
    preview_labels.clear()
    _base()
    _panel(content, Rect2(44, 76, 1192, 516), PAPER)
    var heading: String = "COUNSELING  /  " + node.chapter if mode == "counseling" else "%02d  /  %s" % [node.chapter_index, node.chapter]
    _label(content, heading, Rect2(76, 92, 840, 34), 17, MUTED)
    _label(content, node.place, Rect2(1040, 96, 160, 30), 14, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var room: bool = node.place == "診察室"
    _image(content, _background_path(node.place), Rect2(76, 143, 1128, 385))
    var partner: String = "医師" if room else ""
    if str(node.get("source", {}).get("sheet", "")).begins_with("メイン"):
        if node.chapter_index != 2 or int(node.source.row) >= 8:
            partner = "あしか"
    if node.chapter_index == 1:
        partner = "りあ"
    elif node.chapter_index == 4:
        partner = "すみか"
    partner = node.get("partner", partner)
    _panel(content, Rect2(76, 329, 1128, 199), Color(0.99, 0.986, 0.965, 0.98), Color("c2c9bb"), 8)
    _panel(content, Rect2(515, 299, 250, 36), INK, Color.TRANSPARENT, 3)
    _center_label(content, node.speaker if node.speaker != "" else "よだか  /  心の声", Rect2(525, 302, 230, 30), 17, PAPER)
    body = RichTextLabel.new()
    body.position = Vector2(328, 347)
    body.size = Vector2(624, 164)
    body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    if node.has("choices") or (mode == "counseling" and state.counsel_step == "choice"):
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
    next_button = _button(content, "全文を表示  ▷", Rect2(985, 541, 219, 36), _advance, true)
    hint = _label(content, "CLICK / SPACE", Rect2(79, 549, 180, 24), 12, MUTED)
    _button(content, "読み返す", Rect2(283, 541, 135, 36), _show_history)
    if mode == "story":
        _button(content, "AUTO " + ("ON" if auto_mode else "OFF"), Rect2(428, 541, 136, 36), _toggle_auto)
    _button(content, "文字速度", Rect2(574, 541, 135, 36), _show_settings)
    _button(content, "タイトル", Rect2(719, 541, 135, 36), _show_title)
    status.text = "自動保存  /  " + ("診察室" if room else "言葉を集める日")
    active_scene_key = "%d|%s|%s" % [int(node.chapter_index), node.chapter, node.place]

func _check_interlude() -> void:
    if state.scene_key != active_scene_key:
        _show_interlude("scene")
    elif state.pending_word != "" and mode == "story":
        _show_interlude("word")

func _show_interlude(kind: String) -> void:
    overlay_kind = kind
    interlude_ready = false
    overlay = Control.new()
    overlay.size = Vector2(1280, 800)
    overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    overlay.gui_input.connect(_interlude_input)
    stage.add_child(overlay)
    _panel(overlay, Rect2(0, 0, 1280, 800), Color("0b100e"))
    if kind == "scene":
        content.visible = false
        bottom.visible = false
        var heading: String = "COUNSELING" if mode == "counseling" else "CHAPTER  %02d" % current_dialogue.chapter_index
        if current_dialogue.chapter.begins_with("寄り道"):
            heading = "AFTER SCHOOL"
        _center_label(overlay, heading, Rect2(90, 273, 1100, 40), 15, MINT)
        _center_label(overlay, current_dialogue.chapter, Rect2(90, 336, 1100, 74), 38, PAPER)
        _panel(overlay, Rect2(603, 436, 74, 1), Color("708373"))
        _center_label(overlay, current_dialogue.place.replace("_", " ・ "), Rect2(90, 461, 1100, 40), 20, Color("b5c1b5"))
    else:
        var word: Dictionary = state.word_by_id(state.pending_word)
        _center_label(overlay, "言葉を、ひとつもらった。", Rect2(90, 138, 1100, 42), 18, MINT)
        var effect = WordEffect.new()
        effect.position = Vector2(440, 185)
        effect.size = Vector2(400, 350)
        effect.tint = Color(word.color)
        overlay.add_child(effect)
        var specimen = Specimen.new()
        specimen.position = Vector2(505, 227)
        specimen.size = Vector2(270, 255)
        overlay.add_child(specimen)
        specimen.setup(word.model, Color(word.color))
        _center_label(overlay, "「%s」" % word.word, Rect2(90, 525, 1100, 66), 35, PAPER)
        _center_label(overlay, word.speaker + " から、よだかへ", Rect2(90, 599, 1100, 32), 17, Color("a8b7a8"))
    _center_label(overlay, "クリックして、つづける", Rect2(90, 710, 1100, 32), 15, Color("8d9c8d"))
    overlay.modulate.a = 0
    interlude_tween = create_tween()
    interlude_tween.tween_property(overlay, "modulate:a", 1.0, 0.45)
    interlude_tween.tween_callback(func(): interlude_ready = true)
    # Buttons underneath must not retain keyboard focus during an interlude.
    var focused := get_viewport().gui_get_focus_owner()
    if focused != null:
        focused.release_focus()

func _interlude_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        overlay.accept_event()
        _dismiss_interlude()

func _dismiss_interlude() -> void:
    if not interlude_ready or overlay_kind not in ["scene", "word"]:
        return
    interlude_ready = false
    var kind := overlay_kind
    content.visible = true
    bottom.visible = true
    interlude_tween = create_tween()
    interlude_tween.tween_property(overlay, "modulate:a", 0.0, 0.3)
    interlude_tween.tween_callback(func():
        if kind == "scene":
            state.scene_key = active_scene_key
        else:
            state.pending_word = ""
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
    if mode == "story":
        added = state.finish_line()
    else:
        var id: String = "counsel_%s_%d" % [state.counsel_step, state.answers.size()]
        if state.history.is_empty() or state.history.back().id != id:
            state.history.append({"id": id, "speaker": current_dialogue.speaker, "text": current_dialogue.text})
        state.save_game()
    if added:
        _draw_bottom()
        hint.text = "＋ 言葉をもらった"
    else:
        count_label.text = "%02d 個    ·    読んだ言葉 %03d" % [state.collected.size(), state.read_count]
    if state.last_error != "":
        status.text = state.last_error
    next_button.text = "つづきを読む  →"
    if mode == "counseling" and state.counsel_step == "choice":
        _counsel_choices()
    elif current_dialogue.has("choices"):
        next_button.visible = false
        _panel(choice_box, Rect2(333, 414, 614, 103), PAPER)
        for i in range(current_dialogue.choices.size()):
            var width: float = 614.0 / current_dialogue.choices.size()
            var choice: Dictionary = current_dialogue.choices[i]
            var button := _button(choice_box, choice.text, Rect2(337 + i * width, 424, width - 12, 54), _story_choice.bind(i), true)
            button.add_theme_font_size_override("font_size", 17)
            button.disabled = not state.can_choose(i)
            if choice.has("requires"):
                _center_label(choice_box, "%s %d 必要（現在 %d）" % [choice.requires.stat, choice.requires.min, state.stats[State.STAT_NAMES.find(choice.requires.stat)]], Rect2(337 + i * width, 482, width - 12, 26), 12, MUTED)
    if added:
        _show_interlude("word")

func _advance() -> void:
    if mode not in ["story", "counseling"] or is_instance_valid(overlay):
        return
    if not completed:
        _finish_line()
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
    state.choose(index)
    _show_story()

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
    elif mode == "story" and auto_mode and not current_dialogue.has("choices"):
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
        if Rect2(44, 76, 1192, 450).has_point(stage.get_local_mouse_position()):
            _advance()

func _counsel_word() -> Dictionary:
    var index: int = state.answers.size()
    if state.counsel_step in ["reply", "response"]:
        index -= 1
    return state.word_by_id(state.collected[index])

func _show_counseling() -> void:
    mode = "counseling"
    auto_mode = false
    feedback = false
    if state.answers.size() >= state.collected.size() and state.counsel_step not in ["reply", "response"]:
        state.complete_counseling()
        _show_story()
        return
    var step: String = state.counsel_step
    var speaker := "医師"
    var text := ""
    match step:
        "opening_doctor":
            text = "よだかさん、おかえりなさい。\n今週はどうでしたか？"
        "opening_yodaka":
            speaker = "よだか"
            text = "先輩と、また話しました。\n前に考えたことも、思い出しながら。"
            if state.counsel_return == "main4_5":
                for event in state.data.map_events:
                    if event.id == state.selected_event:
                        text = event.recap
        "recall":
            speaker = "よだか"
            text = _counsel_word().memory
        "question":
            text = "「%s」……。\nよだかさんは、その時どう感じましたか？" % _counsel_word().word
        "choice":
            speaker = "よだか"
            text = "あの時、僕は……。"
        "reply":
            speaker = "よだか"
            text = _counsel_word().interpretations[int(state.answers.back().choice)].reply
        "response":
            var responses := ["よだかさんには、そんなふうに届いたんですね。\nその嬉しさを、覚えておいてもいいと思います。",
                "しっくりこないと感じたことも、\nよだかさん自身を知る、大切な手がかりですね。",
                "今、うまく言葉にできなくても大丈夫です。\nよだかさんの中で、ゆっくり考えていきましょう。"]
            text = responses[int(state.answers.back().choice)]
    _render_dialogue({"speaker": speaker, "text": text, "chapter": "今週、僕に残った言葉",
        "chapter_index": 7, "place": "診察室"})
    status.text = "カウンセリング  /  よだかとドクター"
    if step == "reply":
        body.size.y = 145
        _center_label(content, _delta_text(state.answers.back().delta), Rect2(333, 501, 614, 24), 15, Color("597c51"))
    _check_interlude()

func _advance_counseling() -> void:
    var next_steps := {"opening_doctor": "opening_yodaka", "opening_yodaka": "recall",
        "recall": "question", "question": "choice", "reply": "response", "response": "recall"}
    if not next_steps.has(state.counsel_step):
        return
    state.counsel_step = next_steps[state.counsel_step]
    state.save_game()
    _show_counseling()

func _delta_text(delta: Array) -> String:
    var parts: PackedStringArray = []
    for i in range(6):
        if delta[i] != 0:
            parts.append("%s %s%d" % [State.STAT_NAMES[i], "+" if delta[i] > 0 else "", delta[i]])
    return "   /   ".join(parts) if not parts.is_empty() else "変化なし（上限・下限に達しています）"

func _counsel_choices() -> void:
    next_button.visible = false
    var word := _counsel_word()
    for i in range(3):
        var interpretation: Dictionary = word.interpretations[i]
        var delta: Array = state.preview_effects(i)
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
    if feedback or state.counsel_step != "choice" or not completed or is_instance_valid(overlay):
        return
    feedback = true
    var before: Array = state.stats.duplicate()
    var delta: Array = state.interpret(index)
    if delta.is_empty():
        return
    _show_counseling()
    for i in range(6):
        if delta[i] != 0:
            stat_bars[i].value = before[i]
            create_tween().tween_property(stat_bars[i], "value", float(state.stats[i]), 0.7)

func _show_result() -> void:
    mode = "result"
    body = null
    _base()
    _panel(content, Rect2(44, 76, 1192, 516), PAPER)
    _label(content, "EPILOGUE  /  今日のカウンセリング", Rect2(85, 109, 800, 32), 16, MUTED)
    _label(content, "答えは、まだ途中でいい。", Rect2(80, 164, 1100, 72), 44)
    _label(content, "医師", Rect2(87, 260, 140, 30), 18, MUTED)
    _label(content, "よだかさん自身の言葉で、聞かせてくれましたね。\n受け入れることも、受け入れないことも、今は決めないことも。\nまた言葉が増えたら、一緒に考えましょう。", Rect2(86, 311, 950, 122), 24)
    _label(content, "%d 個の言葉を持ち帰り、%d 個の気持ちを聞きました。" % [state.collected.size(), state.answers.size()], Rect2(86, 450, 1010, 38), 20, MUTED)
    _button(content, "タイトルへ", Rect2(87, 521, 238, 48), _show_title, true)
    _button(content, "振り返りの記録", Rect2(342, 521, 255, 48), _show_reflections)
    _label(content, "END OF PROTOTYPE", Rect2(843, 532, 352, 28), 16, MUTED)

func _new_overlay(title: String) -> Panel:
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
    _label(card, text, Rect2(36, 118, 775, 140), 23)
    _button(card, action, Rect2(35, 520, 300, 44), callback, true)

func _show_word(word: Dictionary) -> void:
    var card := _new_overlay("「%s」" % word.word)
    _label(card, word.speaker + " からもらった言葉", Rect2(36, 82, 740, 32), 18, MUTED)
    _panel(card, Rect2(37, 147, 219, 273), DARK)
    var specimen = Specimen.new()
    specimen.position = Vector2(47, 170)
    specimen.size = Vector2(198, 228)
    card.add_child(specimen)
    specimen.setup(word.model, Color(word.color))
    var quote := _label(card, word.quote, Rect2(291, 162, 520, 252), 23)
    quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var feeling := "この言葉をどう感じたか、最後に医師と振り返ります。"
    for answer in state.answers:
        if answer.word == word.id:
            feeling = "振り返り：" + ANSWERS[int(answer.choice)]
    _label(card, feeling, Rect2(36, 449, 770, 41), 17, MUTED)

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
    for answer in state.answers:
        var word: Dictionary = state.word_by_id(answer.word)
        text += "[color=#6b8563]「%s」 / %s[/color]\n%s\n\n" % [word.word, word.speaker, ANSWERS[int(answer.choice)]]
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
