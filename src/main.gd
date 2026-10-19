extends Control

const State = preload("res://src/story_state.gd")
const Specimen = preload("res://src/specimen.gd")
const WordEffect = preload("res://src/word_effect.gd")
const MindMap = preload("res://src/mind_map.gd")
const INK = Color("252c2a")
const MUTED = Color("778078")
const PAPER = Color("fcfbf6")
const MINT = Color("c7e5ba")
const DARK = Color("171e1c")
const NIGHT = Color("10161a")
const THORN = Color("2a1f26")
const THORN_EDGE = Color("6e3b4a")
const GOLD = Color("f3d79e")
const RESPONSES = ["法月さんには、そんなふうに届いたんですね。\nその嬉しさを、覚えておいてもいいと思います。",
    "しっくりこないと感じたことも、\n法月さん自身を知る、大切な手がかりですね。",
    "今、うまく言葉にできなくても大丈夫です。\n法月さんの中で、ゆっくり考えていきましょう。"]
const INSIGHT_RESPONSE = "その言葉は、もう法月さんのものですね。\nそのまま、持っていてください。"
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
var board_focus: String = ""
var night_intro_seen: bool = false
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

func _wrapped(parent: Node, text: String, rect: Rect2, font_size: int = 18, color: Color = INK) -> Label:
    var label := _label(parent, text, rect, font_size, color)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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

func _hit(parent: Node, rect: Rect2, callback: Callable, tooltip: String = "") -> Button:
    var hit := Button.new()
    hit.position = rect.position
    hit.size = rect.size
    hit.flat = true
    hit.tooltip_text = tooltip
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
    overlay_kind = ""
    _image(stage, "res://bg.png", Rect2(0, 0, 1280, 800))
    _panel(stage, Rect2(0, 0, 1280, 800), Color(0.10, 0.15, 0.14, 0.45))
    status = _label(stage, "WEB PROTOTYPE  /  04", Rect2(927, 25, 310, 26), 13, Color("dce5d9"))
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
    _label(content, "心の棚は、刺さったままの言葉で埋まっている。\n寄り道で言葉を集め、カウンセリングでほどいて、自分を考える。", Rect2(94, 361, 580, 72), 20)
    _button(content, "はじめから   →", Rect2(94, 470, 245, 57), _start_new, true)
    var resume := _button(content, "つづきから", Rect2(355, 470, 230, 57), _resume)
    resume.disabled = not state.has_save()
    _label(content, "カウンセリング %d 回 → 寄り道と本編を %d 周 → 総括" % [State.SESSIONS, state.data.rounds.size()], Rect2(94, 545, 600, 25), 14, MUTED)
    _panel(content, Rect2(870, 530, 320, 40), PAPER)
    _label(content, "法月 よだか  /  主人公", Rect2(895, 534, 275, 30), 17)
    _label(stage, "CLICK / SPACE  文字送り     ·     1タップごとに EXP     ·     下の棚をクリックすると読み返せます", Rect2(44, 777, 1160, 20), 13, PAPER)

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

func _short_debuff(id: String) -> String:
    var debuff: Dictionary = state.trauma_def(id).debuff
    match debuff.kind:
        "half":
            return "%s ½" % debuff.stat
        "cap":
            return "%s 上限%d" % [debuff.stat, state.trauma_cap(debuff.stat)]
        "plus":
            return "%s +%d" % [debuff.stat, int(ceil(float(debuff.value) * state.intensity(id)))]
        "rest_half":
            return "休息 ½"
        "forget_half":
            return "手放しEXP ½"
        "gain_half":
            return "言葉の効果 ½"
        "sleep_half":
            return "眠り ½"
    return ""

func _thorn_tier(id: String) -> int:
    return int(ceil(state.intensity(id) * 5.0))

func _draw_bottom() -> void:
    _clear(bottom)
    stat_bars.clear()
    stat_labels.clear()
    var effective: Array = state.effective_stats()
    _panel(bottom, Rect2(44, 612, 224, 155), DARK)
    _label(bottom, "いまの輪郭", Rect2(59, 618, 170, 23), 14, Color("d9e5d3"))
    _label(bottom, "カルテ ▸", Rect2(196, 620, 66, 20), 11, Color("81947f")).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    for i in range(State.STAT_NAMES.size()):
        var y: int = 643 + i * 24
        _label(bottom, State.STAT_NAMES[i], Rect2(60, y, 78, 20), 13, Color("b9c1b8"))
        var bar := ProgressBar.new()
        bar.position = Vector2(141, y + 8)
        bar.size = Vector2(66, 7)
        bar.show_percentage = false
        bar.add_theme_font_size_override("font_size", 1)
        bar.value = effective[i]
        bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bar.add_theme_stylebox_override("background", _box(Color("36403a")))
        bar.add_theme_stylebox_override("fill", _box(Color("d1b6aa") if i == 0 else MINT))
        bottom.add_child(bar)
        bar.size = Vector2(66, 7)
        stat_bars.append(bar)
        var tinted: bool = effective[i] != int(state.stats[i])
        stat_labels.append(_label(bottom, str(effective[i]), Rect2(214, y - 1, 32, 22), 13, Color("e8b0a0") if tinted and (i > 0) == (effective[i] < int(state.stats[i])) else PAPER))
        if tinted:
            _label(bottom, "▾" if (i > 0) == (effective[i] < int(state.stats[i])) else "▴", Rect2(246, y - 1, 16, 22), 12, Color("a8827c"))
    exp_label = _label(bottom, "EXP  " + _commas(state.exp), Rect2(60, 740, 200, 22), 14, GOLD)
    _hit(bottom, Rect2(44, 612, 224, 155), _show_karte.bind(Callable()), "カルテを開く")
    _panel(bottom, Rect2(280, 612, 956, 155), DARK)
    _label(bottom, "心の棚", Rect2(296, 619, 270, 26), 15, PAPER)
    count_label = _label(bottom, _count_text(), Rect2(640, 620, 578, 24), 13, Color("a2b49f"))
    count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var spacing: float = 928.0 / State.SLOTS
    for i in range(State.SLOTS):
        var x: float = 294 + i * spacing
        var slot: Dictionary = state.slots[i]
        if slot.is_empty():
            _panel(bottom, Rect2(x, 653, spacing - 7, 103), Color("1e2823"), Color("364338"))
            _label(bottom, "%02d" % (i + 1), Rect2(x + 6, 657, 28, 20), 11, Color("81947f"))
            _label(bottom, "·", Rect2(x + 49, 675, 20, 30), 28, Color("465344"))
            _label(bottom, "あいている枠", Rect2(x + 16, 730, 95, 20), 10, Color("637460"))
        elif slot.kind == "trauma":
            var id: String = slot.id
            var def: Dictionary = state.trauma_def(id)
            _panel(bottom, Rect2(x, 653, spacing - 7, 103), THORN, THORN_EDGE)
            _label(bottom, "%02d" % (i + 1), Rect2(x + 6, 657, 28, 20), 11, Color("9a6f7c"))
            _specimen(bottom, Rect2(x + (spacing - 78) / 2, 652, 78, 62), "thorn", Color(def.color), _thorn_tier(id))
            _label(bottom, str(state.traumas[id].strength), Rect2(x + spacing - 44, 656, 36, 20), 11, Color("d9a3ad")).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
            var label := _wrapped(bottom, def.word, Rect2(x + 3, 710, spacing - 13, 30), 9 if def.word.length() > 10 else 10, Color("e6d3d8"))
            label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
            _label(bottom, _short_debuff(id), Rect2(x + 3, 740, spacing - 13, 16), 9, Color("c48a98")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            _hit(bottom, Rect2(x, 653, spacing - 7, 103), _show_trauma.bind(id), "「%s」を見つめる" % def.word)
        else:
            var word: Dictionary = state.word_by_id(slot.id)
            var level: int = state.level_of(word.id)
            _panel(bottom, Rect2(x, 653, spacing - 7, 103), Color("1e2823"), Color("364338"))
            _label(bottom, "%02d" % (i + 1), Rect2(x + 6, 657, 28, 20), 11, Color("81947f"))
            _specimen(bottom, Rect2(x + (spacing - 78) / 2, 654, 78, 68), word.model, Color(word.color), level - 1)
            _label(bottom, "Lv%d" % level, Rect2(x + spacing - 44, 656, 36, 20), 11, GOLD if level >= State.MAX_LEVEL else Color("c9b985")).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
            var label := _wrapped(bottom, word.word, Rect2(x + 3, 722, spacing - 13, 32), 11, PAPER)
            label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            _hit(bottom, Rect2(x, 653, spacing - 7, 103), _show_word.bind(word), "「%s」を読み返す" % word.word)

func _count_text() -> String:
    var held: int = state.held_words().size()
    var traumas: int = state.held_traumas().size()
    return "言葉 %d　·　トラウマ %d　·　あき %d　·　1タップ EXP +%d　·　読んだ言葉 %03d" % [held, traumas, State.SLOTS - held - traumas, state.exp_per_tap(), state.read_count]

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
    exp_label.text = "EXP  " + _commas(state.exp)
    exp_label.pivot_offset = Vector2(0, exp_label.size.y / 2)
    exp_label.scale = Vector2(1.25, 1.25)
    var pop := create_tween().bind_node(exp_label)
    pop.tween_property(exp_label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _float_text(Vector2(150, 728), "%s%s" % ["+" if change > 0 else "", _commas(change)], GOLD if change > 0 else Color("e8b0a0"))

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

func _center_label(parent: Node, text: String, rect: Rect2, font_size: int = 18, color: Color = INK) -> Label:
    var label := _label(parent, text, rect, font_size, color)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    return label

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
    var note_text := "地図のピンをクリックすると出かけます。\n出かけるとストレス +%d。\n会話を1タップ進めるごとに EXP +%d。" % [int(State.OUTING_EFFECTS["ストレス"]), state.exp_per_tap()]
    if state.stress_locked():
        note_text = "ストレスが %d。\n疲れていて、今日は出かけられない。\n家で休んで、ストレスを下げよう。" % state.effective(0)
        if state.effective(0) != int(state.stats[0]):
            note_text += "\n（トラウマが %d を %d に見せている）" % [int(state.stats[0]), state.effective(0)]
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
        button.tooltip_text = event.title

func _select_map_event(id: String) -> void:
    if state.select_event(id):
        _show_story()

func _show_night() -> void:
    mode = "night"
    auto_mode = false
    body = null
    _base()
    _panel(content, Rect2(44, 76, 1192, 516), NIGHT)
    _label(content, "NIGHT  /  夜、部屋で", Rect2(77, 94, 780, 34), 17, Color("8d9c8d"))
    var next_text := {"map": "眠ると、次の自由行動へ。", "chapter": "眠ると、本編 CHAPTER %02d へ（ストレス +%d）。" % [int(state.current_round().get("chapter", "main1").trim_prefix("main")), int(State.CHAPTER_EFFECTS["ストレス"])], "counseling": "眠ると、カウンセリングへ。トラウマをほぐし、言葉を掘り下げる。"}
    _label(content, "今日も、言葉を読んだ。", Rect2(77, 140, 900, 44), 30, PAPER)
    _label(content, "今日のEXP  +%s　　　持っているEXP  %s" % [_commas(state.exp_day), _commas(state.exp)], Rect2(77, 196, 1000, 30), 20, GOLD)
    var held: Array = state.held_words()
    var lines: PackedStringArray = []
    if held.is_empty():
        lines.append("心に留めている言葉は、まだない。もらった言葉は、留めるか手放してEXPにするかを選べる。")
    else:
        var names: PackedStringArray = []
        for id in held:
            names.append("「%s」Lv%d" % [state.word_by_id(id).word, state.level_of(id)])
        lines.append("留めている言葉：" + "　".join(names))
    var pains: PackedStringArray = []
    for id in state.held_traumas():
        pains.append("「%s」%d" % [state.trauma_def(id).word, state.traumas[id].strength])
    lines.append("まだ刺さっている言葉 %d：" % pains.size() + (" / ".join(pains) if not pains.is_empty() else "なし"))
    lines.append("")
    lines.append("カウンセリングでは、トラウマをひとつ選んで話し、言葉を持ち込んでほぐせる。EXPで言葉を掘り下げることもできる。\nほぐれたトラウマは、EXPを払って向き合うと棚から消える。")
    _wrapped(content, "\n".join(lines), Rect2(77, 246, 1100, 240), 16, Color("c8d5c5"))
    var relief: int = int(state.sleep_effects()["ストレス"])
    _button(content, "眠る（ストレス %d）  →" % relief, Rect2(884, 520, 320, 46), _sleep, true)
    _label(content, next_text[state.after_night], Rect2(77, 530, 800, 26), 14, Color("8d9c8d"))
    if not night_intro_seen:
        _show_interlude("night")

func _sleep() -> void:
    if mode != "night" or is_instance_valid(overlay):
        return
    night_intro_seen = false
    state.sleep()
    _show_story()

func _show_story() -> void:
    match state.current:
        "map":
            _show_map()
            return
        "night":
            _show_night()
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
    overlay_kind = kind
    interlude_ready = false
    overlay = Control.new()
    overlay.size = Vector2(1280, 800)
    overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    overlay.gui_input.connect(_interlude_input)
    stage.add_child(overlay)
    _panel(overlay, Rect2(0, 0, 1280, 800), Color("0b100e"))
    if kind == "night":
        # The day's last place slowly sinks into darkness before the room appears.
        content.visible = false
        bottom.visible = false
        _image(overlay, _background_path(last_place), Rect2(0, 0, 1280, 800))
        var dusk := _panel(overlay, Rect2(0, 0, 1280, 800), Color("06090c"))
        dusk.modulate.a = 0.0
        var moon := _center_label(overlay, "夜", Rect2(90, 330, 1100, 90), 54, PAPER)
        moon.modulate.a = 0.0
        var caption := _center_label(overlay, "部屋に戻って、今日の言葉を思い返す。", Rect2(90, 430, 1100, 36), 18, Color("b5c1b5"))
        caption.modulate.a = 0.0
        var hint_label := _center_label(overlay, "クリックして、つづける", Rect2(90, 710, 1100, 32), 15, Color("8d9c8d"))
        hint_label.modulate.a = 0.0
        overlay.modulate.a = 1.0
        interlude_tween = create_tween()
        interlude_tween.tween_property(dusk, "modulate:a", 0.94, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
        interlude_tween.parallel().tween_property(moon, "modulate:a", 1.0, 1.4).set_delay(1.4)
        interlude_tween.parallel().tween_property(caption, "modulate:a", 1.0, 1.0).set_delay(2.2)
        interlude_tween.parallel().tween_property(hint_label, "modulate:a", 1.0, 0.6).set_delay(2.6)
        interlude_tween.tween_callback(func(): interlude_ready = true)
        var focused_button := get_viewport().gui_get_focus_owner()
        if focused_button != null:
            focused_button.release_focus()
        return
    if kind == "scene":
        content.visible = false
        bottom.visible = false
        var heading: String = "CHAPTER  %02d" % current_dialogue.chapter_index
        if current_dialogue.get("kind", "") == "counsel":
            heading = "COUNSELING"
        elif current_dialogue.get("kind", "") == "outing":
            heading = "AFTER SCHOOL"
        _center_label(overlay, heading, Rect2(90, 273, 1100, 40), 15, MINT)
        _center_label(overlay, current_dialogue.chapter, Rect2(90, 336, 1100, 74), 38, PAPER)
        _panel(overlay, Rect2(603, 436, 74, 1), Color("708373"))
        _center_label(overlay, current_dialogue.place.replace("_", " ・ "), Rect2(90, 461, 1100, 40), 20, Color("b5c1b5"))
        _center_label(overlay, "クリックして、つづける", Rect2(90, 710, 1100, 32), 15, Color("8d9c8d"))
    else:
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
    _wrapped(overlay, "持っていると：" + _hold_text(level) + "\n話に持ち込むと：" + _release_text(level) + "\n手放すと：EXP +%s" % _commas(state.forget_value(word.id)), Rect2(684, 152, 500, 90), 14, Color("c8d5c5"))
    var free: int = state.free_slot()
    if free >= 0:
        _button(overlay, "心に留める（%d番の枠へ）" % (free + 1), Rect2(684, 262, 492, 48), _decide_word.bind("keep", -1), true)
        _button(overlay, "手放して EXP +%s にする" % _commas(state.forget_value(word.id)), Rect2(684, 322, 492, 48), _decide_word.bind("release", -1))
        _wrapped(overlay, "留めた言葉はカウンセリングでトラウマをほぐすのに使えるし、持っているだけで効く。\n手放した言葉は戻らない。", Rect2(684, 386, 500, 80), 13, Color("8d9c8d"))
    else:
        var held: Array = state.held_words()
        if held.is_empty():
            _wrapped(overlay, "棚はトラウマで埋まっていて、留める枠がない。\nカウンセリングでトラウマをほぐし、向き合って枠を空けよう。", Rect2(684, 250, 500, 70), 14, Color("e6d3d8"))
        else:
            _wrapped(overlay, "枠がない。留めるには、どれかを手放す。", Rect2(684, 250, 500, 24), 14, Color("e6d3d8"))
            for i in range(mini(held.size(), 4)):
                var other: Dictionary = state.word_by_id(held[i])
                var button := _button(overlay, "「%s」Lv%d を手放して留める（EXP +%s）" % [other.word, state.level_of(other.id), _commas(state.forget_value(other.id))], Rect2(684, 280 + i * 44, 492, 38), _decide_word.bind("swap", state.slot_of(other.id)))
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
    if not interlude_ready or overlay_kind not in ["scene", "word", "night"]:
        return
    if overlay_kind == "word" and state.pending_word != "":
        return  # the word must be kept or let go with the buttons
    interlude_ready = false
    var kind := overlay_kind
    content.visible = true
    bottom.visible = true
    interlude_tween = create_tween()
    interlude_tween.tween_property(overlay, "modulate:a", 0.0, 0.3)
    interlude_tween.tween_callback(func():
        if kind == "scene":
            state.scene_key = active_scene_key
        elif kind == "night":
            night_intro_seen = true
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
        count_label.text = _count_text()
        _animate_exp(exp_before)
        if state.has_change(state.last_delta):
            _animate_stats(before)
            hint.text = _delta_text(state.last_delta)
    if state.last_error != "":
        status.text = state.last_error
    next_button.text = "カルテを見る  →" if current_dialogue.get("karte", false) else "つづきを読む  →"
    if mode == "counseling" and state.counsel_step == "grow_choice":
        _counsel_choices()
    elif mode == "counseling" and state.counsel_step == "talk_effect":
        _talk_effect_panel()
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
                note = "%s %d 必要（現在 %d" % [choice.requires.stat, choice.requires.min, state.effective(k)]
                note += "、トラウマで抑えられている）" if state.effective(k) < int(state.stats[k]) else "）"
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
    if step == "board":
        _show_board()
        return
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
                text = "……残っている言葉、ですか。\n（八つも、ある）"
            elif state.collected.is_empty():
                text = "……いろいろ言われた気がするのに、\nどれも、うまく思い出せません。"
            else:
                text = "いろんな人と話しました。\n言葉を%d個、持ち帰ってきました。" % state.collected.size()
        "talk_recall":
            speaker = "よだか"
            text = trauma.recall
        "talk_doctor":
            text = trauma.doctor
            var brought: Array = state.talk_result.get("cards", [])
            if not brought.is_empty():
                var names: PackedStringArray = []
                for id in brought:
                    names.append("「%s」" % state.word_by_id(id).word)
                text += "\n%sも、一緒に。" % "".join(names)
        "talk_effect":
            speaker = "よだか"
            text = trauma.loosen
        "talk_emerge":
            speaker = "よだか"
            text = state.trauma_def(state.talk_result.emerged).emerge
        "face_line":
            speaker = "よだか"
            text = trauma.resolve
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

func _talk_effect_panel() -> void:
    # The number of the trauma goes down in front of the dialogue.
    var result: Dictionary = state.talk_result
    var def: Dictionary = state.trauma_def(result.id)
    var card := _panel(content, Rect2(360, 150, 560, 140), Color(0.07, 0.05, 0.07, 0.86), THORN_EDGE, 6)
    _label(card, "「%s」をほぐした" % def.word, Rect2(20, 12, 520, 28), 17, Color("e6d3d8"))
    var strength := _label(card, "強さ  %d" % int(result.before), Rect2(20, 48, 300, 40), 30, Color("d9a3ad"))
    var cost := _label(card, "向き合うEXP  %s" % _commas(int(result.cost_before)), Rect2(20, 96, 520, 26), 15, GOLD)
    var notes: PackedStringArray = []
    if result.get("first", false):
        notes.append("最初のひとつ：向き合うEXPが %d に" % State.FIRST_FACE_COST)
    for id in result.get("resonant", []):
        notes.append("「%s」が響いた（効果2倍）" % state.word_by_id(id).word)
    if result.get("emerged", "") != "":
        notes.append("……奥で、何かが動いた")
    _wrapped(card, "\n".join(notes), Rect2(330, 44, 220, 80), 12, Color("c8d5c5"))
    var tween := create_tween().bind_node(card)
    tween.tween_interval(0.4)
    tween.tween_method(_count_strength.bind(strength), float(result.before), float(result.after), 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.tween_callback(func():
        strength.text = "強さ  %d  →  %d" % [int(result.before), int(result.after)]
        if result.get("emerged", "") != "":
            cost.text = "……奥から「%s」が出てきた" % state.trauma_def(result.emerged).word
        else:
            cost.text = "向き合うEXP  %s  →  %s" % [_commas(int(result.cost_before)), _commas(int(result.cost_after))])

func _count_strength(value: float, label: Label) -> void:
    label.text = "強さ  %d" % int(round(value))

func _show_board() -> void:
    body = null
    portraits.clear()
    preview_labels.clear()
    _base()
    _panel(content, Rect2(44, 76, 1192, 516), PAPER)
    _label(content, "COUNSELING  /  " + _session_title(), Rect2(76, 92, 700, 34), 17, MUTED)
    _label(content, "EXP  " + _commas(state.exp), Rect2(900, 90, 304, 34), 22, Color("8a7a3c")).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var lead := "棚から、ひとつ選んでみなとに話す。言葉を持ち込むとよくほぐれる。言葉はEXPで掘り下げられる。"
    if state.session == 1:
        lead = "みなとに話す言葉を、ひとつ選ぶ。はじめてなので、奥に何かが隠れていない言葉から。"
    elif state.talked:
        lead = "今日はもう話した。言葉を掘り下げたり、ほぐれたトラウマに向き合ったりできる。"
    _wrapped(content, lead, Rect2(76, 124, 1100, 24), 14, MUTED)
    var spacing: float = 1128.0 / State.SLOTS
    for i in range(State.SLOTS):
        var x: float = 76 + i * spacing
        var slot: Dictionary = state.slots[i]
        var selected: bool = not slot.is_empty() and slot.id == board_focus
        if slot.is_empty():
            _panel(content, Rect2(x, 152, spacing - 8, 128), Color("edeee6"), Color("c5cbc1"), 4)
            _center_label(content, "あいている枠", Rect2(x, 200, spacing - 8, 30), 12, MUTED)
        elif slot.kind == "trauma":
            var id: String = slot.id
            var def: Dictionary = state.trauma_def(id)
            _panel(content, Rect2(x, 152, spacing - 8, 128), THORN if not selected else Color("3d2a35"), GOLD if selected else THORN_EDGE, 4)
            _specimen(content, Rect2(x + (spacing - 80) / 2, 150, 72, 58), "thorn", Color(def.color), _thorn_tier(id))
            var caption := _wrapped(content, def.word, Rect2(x + 4, 206, spacing - 16, 34), 10 if def.word.length() > 10 else 11, Color("e6d3d8"))
            caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
            var status_text: String = "強さ %d" % state.traumas[id].strength
            if state.traumas[id].unraveled:
                status_text += "　EXP %s" % _commas(state.face_cost(id))
            else:
                status_text += "　まだ固い"
            _center_label(content, status_text, Rect2(x + 2, 240, spacing - 12, 18), 10, Color("d9a3ad"))
            _center_label(content, _short_debuff(id), Rect2(x + 2, 258, spacing - 12, 18), 10, Color("c48a98"))
            _hit(content, Rect2(x, 152, spacing - 8, 128), _focus_board.bind(id), def.word)
        else:
            var word: Dictionary = state.word_by_id(slot.id)
            var level: int = state.level_of(word.id)
            var chosen: bool = state.cards.has(word.id)
            _panel(content, Rect2(x, 152, spacing - 8, 128), Color("1e2823") if not selected else Color("2a3a30"), GOLD if selected or chosen else Color("364338"), 4)
            _specimen(content, Rect2(x + (spacing - 80) / 2, 150, 72, 62), word.model, Color(word.color), level - 1)
            var caption := _wrapped(content, word.word, Rect2(x + 4, 212, spacing - 16, 30), 11, PAPER)
            caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            _center_label(content, "Lv%d" % level + ("　持ち込む" if chosen else ""), Rect2(x + 2, 244, spacing - 12, 18), 10, GOLD if chosen or level >= State.MAX_LEVEL else Color("c9b985"))
            _center_label(content, state.word_by_id(word.id).tag, Rect2(x + 2, 260, spacing - 12, 18), 10, Color("8d9c8d"))
            _hit(content, Rect2(x, 152, spacing - 8, 128), _focus_board.bind(word.id), word.word)
    _panel(content, Rect2(76, 290, 1128, 238), Color("f4f3ec"), Color("c5cbc1"), 4)
    var focus_slot: int = state.slot_of(board_focus)
    if focus_slot < 0:
        _wrapped(content, "↑ 棚の言葉をクリックすると、ここに詳しく出ます。\n\nトラウマは、話すと弱まり、ほぐれる。ほぐれたトラウマはEXPを払って向き合うと消え、枠が空く。\n言葉は、持っているだけで効果がある。話に持ち込むとトラウマを強くほぐすが、その言葉は使い切ってしまう。\n同じ種類（居場所・身体・恋・家族・過去）の言葉は、トラウマに響いて効果が2倍になる。", Rect2(96, 306, 1090, 200), 15, INK)
    elif state.slots[focus_slot].kind == "trauma":
        _board_trauma(board_focus)
    else:
        _board_word(board_focus)
    _button(content, "今日は、ここまで  →", Rect2(930, 540, 274, 38), _finish_session, true)
    _button(content, "読み返す", Rect2(76, 540, 135, 38), _show_history)
    _button(content, "タイトル", Rect2(221, 540, 135, 38), _show_title)
    status.text = "カウンセリング  /  心の棚"

func _board_trauma(id: String) -> void:
    var def: Dictionary = state.trauma_def(id)
    var trauma: Dictionary = state.traumas[id]
    _label(content, "「%s」　/　%s" % [def.word, def.speaker], Rect2(96, 302, 600, 28), 18, Color("5b3644"))
    _wrapped(content, def.quote, Rect2(96, 334, 440, 70), 13, INK)
    _wrapped(content, "影響：" + state.debuff_text(id) + "\n強さ %d / %d　·　種類：%s" % [trauma.strength, int(def.strength), def.tag], Rect2(96, 404, 440, 50), 13, Color("7a4a5a"))
    var face_note: String = "向き合うには EXP %s（持っている %s）" % [_commas(state.face_cost(id)), _commas(state.exp)]
    if not trauma.unraveled:
        face_note = "まだ固い。話してほぐすと、向き合えるようになる。"
    _wrapped(content, face_note, Rect2(96, 456, 440, 40), 13, Color("8a7a3c"))
    var face := _button(content, "向き合う（EXP %s）" % _commas(state.face_cost(id)), Rect2(96, 488, 240, 34), _face_board.bind(id))
    face.add_theme_font_size_override("font_size", 14)
    face.disabled = not state.can_face(id)
    # Words to bring into the conversation.
    _label(content, "一緒に持ち込む言葉（%d つまで・使い切り）" % State.MAX_CARDS, Rect2(560, 302, 400, 24), 14, MUTED)
    var held: Array = state.held_words()
    if held.is_empty():
        _wrapped(content, "持ち込める言葉がない。みなとと話すだけでも、少しはほぐれる。", Rect2(560, 330, 300, 60), 13, MUTED)
    for i in range(mini(held.size(), 6)):
        var word: Dictionary = state.word_by_id(held[i])
        var chosen: bool = state.cards.has(word.id)
        var resonant: bool = state.resonates(word.id, id)
        var text: String = "%s「%s」Lv%d　%s%s" % ["☑ " if chosen else "☐ ", word.word, state.level_of(word.id), _release_text(state.level_data(word.id)), "　響く!" if resonant else ""]
        var toggle := _button(content, text, Rect2(560, 328 + i * 32, 330, 28), _toggle_board_card.bind(word.id), chosen)
        toggle.add_theme_font_size_override("font_size", 12)
        toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
    var preview: Dictionary = state.talk_preview(id, state.cards)
    _panel(content, Rect2(910, 302, 276, 220), Color("1e2823"), Color("364338"), 4)
    if state.can_talk(id):
        _label(content, "話すと", Rect2(926, 312, 240, 24), 14, Color("a2b49f"))
        _label(content, "強さ %d → %d" % [trauma.strength, int(preview.strength)], Rect2(926, 338, 250, 30), 20, PAPER)
        if preview.emerges:
            _label(content, "向き合うEXP %s → ？" % _commas(state.face_cost(id)), Rect2(926, 370, 250, 24), 13, Color("d9a3ad"))
        else:
            _label(content, "向き合うEXP %s → %s" % [_commas(state.face_cost(id)), _commas(int(preview.face))], Rect2(926, 370, 250, 24), 13, GOLD)
        var warn: String = ""
        if preview.get("first", false):
            warn = "最初のひとつは、小さなEXPで向き合える。"
        if preview.emerges:
            warn = "……奥で何かが動いている。ここまでほぐすと、出てくる。"
        elif def.has("deeper") and trauma.unraveled:
            warn = "この言葉の奥には、まだ何かある気がする。"
        _wrapped(content, warn, Rect2(926, 398, 250, 60), 12, Color("d9a3ad") if preview.emerges else Color("c8d5c5"))
        preview_labels = ["強さ %d → %d" % [trauma.strength, int(preview.strength)]]
        _button(content, "みなとに話す", Rect2(926, 470, 244, 40), _talk_board, true)
    elif state.talked:
        _wrapped(content, "今日はもう、ひとつ話した。\n次のカウンセリングで、また。", Rect2(926, 320, 250, 80), 14, Color("c8d5c5"))
    elif state.session == 1 and def.has("deeper"):
        _wrapped(content, "はじめての今日は、この言葉はまだ重すぎる。\n（奥に何かがある）", Rect2(926, 320, 250, 80), 14, Color("d9a3ad"))
    else:
        _wrapped(content, "この言葉は、今は話せない。", Rect2(926, 320, 250, 80), 14, Color("c8d5c5"))

func _board_word(id: String) -> void:
    var word: Dictionary = state.word_by_id(id)
    var level: int = state.level_of(id)
    var data: Dictionary = state.level_data(id)
    _label(content, "「%s」　/　%s　·　Lv%d　·　%s" % [word.word, word.speaker, level, word.tag], Rect2(96, 302, 700, 28), 18, Color("3f5a3b"))
    _wrapped(content, word.quote, Rect2(96, 334, 520, 70), 13, INK)
    _wrapped(content, "持っていると：" + _hold_text(data) + "\n話に持ち込むと：" + _release_text(data) + "\n手放すと：EXP +%s" % _commas(state.forget_value(id)), Rect2(96, 404, 520, 70), 13, Color("597c51"))
    var answer: Dictionary = state.answer_for(id)
    if not answer.is_empty():
        _wrapped(content, "受け取り方：" + word.interpretations[int(answer.choice)].label, Rect2(96, 476, 520, 24), 13, MUTED)
    _panel(content, Rect2(660, 302, 526, 220), Color("1e2823"), Color("364338"), 4)
    if level < State.MAX_LEVEL:
        var next: Dictionary = state.level_data(id, level + 1)
        _label(content, "掘り下げると Lv%d（EXP %s）" % [level + 1, _commas(state.next_level_cost(id))], Rect2(676, 312, 500, 24), 14, Color("a2b49f"))
        _wrapped(content, "持っていると：" + _hold_text(next) + "\n話に持ち込むと：" + _release_text(next), Rect2(676, 340, 500, 60), 13, PAPER)
        _wrapped(content, "こういう意味だったのか、と気づく。" if level == 1 else "もっと深いところまで、言葉を自分のものにする。", Rect2(676, 404, 500, 40), 12, Color("8d9c8d"))
        var grow := _button(content, "掘り下げる（EXP %s）" % _commas(state.next_level_cost(id)), Rect2(676, 470, 244, 40), _grow_board.bind(id), true)
        grow.disabled = not state.can_grow(id)
    else:
        _wrapped(content, "これ以上は掘り下げられない。\nもう、法月さんの言葉になっている。", Rect2(676, 320, 500, 60), 14, PAPER)
    var forget := _button(content, "手放す（EXP +%s）" % _commas(state.forget_value(id)), Rect2(932, 470, 244, 40), _forget_board.bind(id))
    forget.add_theme_font_size_override("font_size", 14)

func _focus_board(id: String) -> void:
    if not state.on_board() or is_instance_valid(overlay):
        return
    board_focus = id
    if state.slot_of(id) >= 0 and state.slots[state.slot_of(id)].kind == "trauma":
        state.focus_trauma(id)
    _show_board()

func _toggle_board_card(id: String) -> void:
    if not state.on_board() or is_instance_valid(overlay):
        return
    state.toggle_card(id)
    _show_board()

func _talk_board() -> void:
    if not state.on_board() or is_instance_valid(overlay):
        return
    if state.talk():
        board_focus = state.talk_result.get("emerged", "") if state.talk_result.get("emerged", "") != "" else state.focus
        _show_story()

func _face_board(id: String) -> void:
    if not state.on_board() or is_instance_valid(overlay):
        return
    var before: int = state.exp
    if state.face(id):
        board_focus = ""
        _show_story()
        _animate_exp(before)

func _grow_board(id: String) -> void:
    if not state.on_board() or is_instance_valid(overlay):
        return
    var before: int = state.exp
    if state.grow(id):
        _show_story()
        _animate_exp(before)

func _forget_board(id: String) -> void:
    if not state.on_board() or is_instance_valid(overlay):
        return
    var word: Dictionary = state.word_by_id(id)
    _modal("「%s」を手放す" % word.word, "手放すと EXP +%s。棚から消えて、戻らない。" % _commas(state.forget_value(id)), "手放す", func():
        _close_overlay()
        var before: int = state.exp
        if state.forget_word(id) > 0:
            board_focus = ""
            _show_board()
            _animate_exp(before))

func _finish_session() -> void:
    if not state.on_board() or is_instance_valid(overlay):
        return
    board_focus = ""
    state.finish_session()
    _show_story()

func _advance_counseling() -> void:
    if state.counsel_step in ["board", "grow_choice"]:
        return
    var before: Array = state.effective_stats()
    state.advance_counseling()
    _show_story()
    if mode == "counseling" and state.counsel_step == "board":
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
                parts.append("手放す言葉のEXP ×%d" % int(level.hold[key]))
            _:
                parts.append("%s %s%d" % [key, "+" if int(level.hold[key]) > 0 else "", int(level.hold[key])])
    return "、".join(parts) if not parts.is_empty() else "—"

func _release_text(level: Dictionary) -> String:
    var parts: PackedStringArray = []
    if level.release.has("weaken"):
        parts.append("強さ −%d" % int(level.release.weaken))
    if level.release.has("cost_mult"):
        parts.append("必要EXP ×%s" % str(level.release.cost_mult))
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
    var card := _new_overlay("メンタル〇〇（仮）  /  いまのカルテ")
    _label(card, "法月 よだか　　状態：" + _stress_note(), Rect2(36, 74, 400, 30), 15, MUTED)
    var effective: Array = state.effective_stats()
    for i in range(State.STAT_NAMES.size()):
        var y: int = 112 + i * 46
        _label(card, State.STAT_NAMES[i], Rect2(40, y, 100, 30), 19)
        var bar := ProgressBar.new()
        bar.position = Vector2(140, y + 8)
        bar.size = Vector2(190, 14)
        bar.show_percentage = false
        bar.add_theme_font_size_override("font_size", 1)
        bar.value = effective[i]
        bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bar.add_theme_stylebox_override("background", _box(Color("e4e6df")))
        bar.add_theme_stylebox_override("fill", _box(Color("c98f7c") if i == 0 else Color("7fae70")))
        card.add_child(bar)
        bar.size = Vector2(190, 14)
        var number: String = str(effective[i])
        if effective[i] != int(state.stats[i]):
            number += "（素 %d）" % int(state.stats[i])
        _label(card, number, Rect2(340, y, 100, 30), 15)
    var pains: PackedStringArray = []
    for id in state.held_traumas():
        pains.append("「%s」 %s" % [state.trauma_def(id).word, state.debuff_text(id)])
    var notes := "EXP %s（合計 %s）　·　1タップ +%d\n\n刺さっている言葉：\n%s" % [_commas(state.exp), _commas(state.exp_total), state.exp_per_tap(), "\n".join(pains) if not pains.is_empty() else "なし"]
    _wrapped(card, notes, Rect2(40, 300, 390, 200), 12, MUTED)
    # The mental map: darkness that each kept word lights up, wider with every level.
    _label(card, "ことばの地図", Rect2(456, 74, 200, 26), 15, MUTED)
    var held: Array = state.held_words()
    _label(card, "%d 語　·　手放した %d　·　使った %d" % [held.size(), state.forgotten.size(), state.used.size()], Rect2(560, 76, 240, 24), 12, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var map = MindMap.new()
    map.position = Vector2(440, 100)
    map.size = Vector2(375, 412)
    card.add_child(map)
    var count: int = held.size()
    for i in range(count):
        var word: Dictionary = state.word_by_id(held[i])
        map.lit.append({"pos": map.node_position(i, count), "color": Color(word.color), "crystals": (state.level_of(word.id) - 1) * 3})
    var gone: Array = state.forgotten + state.used
    for i in range(gone.size()):
        var word: Dictionary = state.word_by_id(gone[i])
        map.embers.append({"pos": map.node_position(count + i, count + gone.size()) * 0.5 + map.size * 0.25, "color": Color(word.color)})
    map.unknown = maxi(0, state.data.words.size() - count - gone.size())
    for i in range(count):
        var word: Dictionary = state.word_by_id(held[i])
        var level: int = state.level_of(word.id)
        var spot: Vector2 = map.position + map.node_position(i, count)
        _specimen(card, Rect2(spot.x - 30, spot.y - 38, 60, 56), word.model, Color(word.color), level - 1)
        var label := _wrapped(card, word.word, Rect2(spot.x - 55, spot.y + 18, 110, 30), 10, PAPER)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _label(card, "Lv%d" % level, Rect2(spot.x + 14, spot.y - 40, 40, 16), 11, GOLD if level >= State.MAX_LEVEL else Color("c9b985"))
    var footer: String = "まだ暗い場所 %d" % map.unknown if count > 0 else "まだ何も照らされていない。"
    if not gone.is_empty():
        footer += "　·　消えた光 %d" % gone.size()
    _label(card, footer, Rect2(452, 486, 351, 22), 11, Color("8d9c8d")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
    _label(content, "言葉 %d 個をもらい、%d 個を留め、%d 個を手放し、%d 個を話に使った。　トラウマ %d 個と向き合った（残り %d）。　EXP 合計 %s" % [state.collected.size(), state.held_words().size(), state.forgotten.size(), state.used.size(), state.faced_count(), state.held_traumas().size(), _commas(state.exp_total)], Rect2(86, 450, 1100, 38), 15, MUTED)
    _button(content, "タイトルへ", Rect2(87, 521, 238, 48), _show_title, true)
    _button(content, "振り返りの記録", Rect2(342, 521, 255, 48), _show_reflections)
    _button(content, "カルテ", Rect2(614, 521, 160, 48), _show_karte.bind(Callable()))
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
    _wrapped(card, text, Rect2(36, 118, 775, 140), 23)
    _button(card, action, Rect2(35, 520, 300, 44), callback, true)

func _show_word(word: Dictionary) -> void:
    var card := _new_overlay("「%s」" % word.word)
    var level: int = state.level_of(word.id)
    var data: Dictionary = state.level_data(word.id)
    _label(card, "%s からもらった言葉　·　Lv%d　·　%s" % [word.speaker, level, word.tag], Rect2(36, 82, 740, 32), 18, MUTED)
    _panel(card, Rect2(37, 147, 219, 273), DARK)
    _specimen(card, Rect2(47, 170, 198, 228), word.model, Color(word.color), level - 1)
    _label(card, "Lv%d" % level, Rect2(37, 424, 219, 24), 14, Color("8d9c8d")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _wrapped(card, word.quote, Rect2(291, 150, 520, 150), 21)
    var gained: Array = state.gains.get(word.id, [])
    _label(card, "もらった時：" + (_delta_text(gained) if not gained.is_empty() else "—"), Rect2(291, 300, 520, 30), 15, MUTED)
    _wrapped(card, "持っていると：" + _hold_text(data) + "\n話に持ち込むと：" + _release_text(data) + "\n手放すと：EXP +%s" % _commas(state.forget_value(word.id)), Rect2(291, 336, 520, 80), 15, Color("597c51"))
    var answer: Dictionary = state.answer_for(word.id)
    var feeling := "カウンセリングでEXPを使うと掘り下げられる。" if level < State.MAX_LEVEL else "もう、法月さんの言葉になっている。"
    if not answer.is_empty():
        feeling = "受け取り方：%s　（%s）" % [word.interpretations[int(answer.choice)].label, _delta_text(answer.delta)]
    _label(card, feeling, Rect2(36, 449, 770, 41), 16, MUTED)
    if state.slot_of(word.id) >= 0 and mode in ["story", "map", "night", "counseling"]:
        var forget := _button(card, "手放す（EXP +%s）" % _commas(state.forget_value(word.id)), Rect2(291, 521, 240, 42), _confirm_forget.bind(word))
        forget.disabled = state.pending_word != "" or (mode == "counseling" and not state.on_board())

func _confirm_forget(word: Dictionary) -> void:
    _close_overlay()
    _modal("「%s」を手放す" % word.word, "手放すと EXP +%s。棚から消えて、戻らない。" % _commas(state.forget_value(word.id)), "手放す", func():
        _close_overlay()
        var before: int = state.exp
        if state.forget_word(word.id) > 0:
            if mode == "counseling" and state.on_board():
                board_focus = ""
                _show_board()
            else:
                _draw_bottom()
            _animate_exp(before))

func _show_trauma(id: String) -> void:
    var def: Dictionary = state.trauma_def(id)
    var trauma: Dictionary = state.traumas[id]
    var card := _new_overlay("「%s」" % def.word)
    _label(card, "%s の言葉　·　%s" % [def.speaker, def.tag], Rect2(36, 82, 740, 32), 18, MUTED)
    _panel(card, Rect2(37, 147, 219, 273), THORN)
    _specimen(card, Rect2(47, 170, 198, 228), "thorn", Color(def.color), _thorn_tier(id))
    _label(card, "強さ %d / %d" % [trauma.strength, int(def.strength)], Rect2(37, 424, 219, 24), 14, Color("d9a3ad")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _wrapped(card, def.quote, Rect2(291, 150, 520, 150), 21)
    _wrapped(card, "影響：" + state.debuff_text(id), Rect2(291, 300, 520, 30), 15, Color("7a4a5a"))
    var note: String
    if trauma.unraveled:
        note = "ほぐれている。向き合うには EXP %s（持っている %s）。\nカウンセリングでさらにほぐすと、必要なEXPが下がる。" % [_commas(state.face_cost(id)), _commas(state.exp)]
    else:
        note = "まだ固い。カウンセリングでみなとに話すと、ほぐれて向き合えるようになる。"
    if def.has("deeper") and trauma.unraveled:
        note += "\n……この言葉の奥には、まだ何かある気がする。"
    _wrapped(card, note, Rect2(291, 336, 520, 90), 15, MUTED)
    _label(card, "弱まるほど影響は小さくなる。向き合って消すと、棚に枠が空く。", Rect2(36, 449, 770, 41), 16, MUTED)
    if trauma.unraveled:
        var face := _button(card, "向き合う（EXP %s）" % _commas(state.face_cost(id)), Rect2(291, 521, 240, 42), _face_from_shelf.bind(id), true)
        face.disabled = not state.can_face(id)

func _face_from_shelf(id: String) -> void:
    var before: int = state.exp
    if not state.face(id):
        return
    _close_overlay()
    if mode == "counseling" and state.counsel_step == "face_line":
        board_focus = ""
        _show_story()
        _animate_exp(before)
        return
    var effective_before: Array = state.effective_stats()
    _draw_bottom()
    _animate_exp(before)
    _modal("「%s」と向き合った" % state.trauma_def(id).word, "よだか：\n" + state.trauma_def(id).resolve + "\n\n棚に枠がひとつ空いた。", "閉じる", func():
        _close_overlay()
        _animate_stats(effective_before))

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
    for id in state.used:
        var word: Dictionary = state.word_by_id(id)
        text += "[color=#7a8a6a]「%s」 / %s　—　トラウマをほぐすのに使った[/color]\n\n" % [word.word, word.speaker]
    for id in state.forgotten:
        var word: Dictionary = state.word_by_id(id)
        text += "[color=#9a9a9a]「%s」 / %s　—　手放した[/color]\n\n" % [word.word, word.speaker]
    for id in state.traumas:
        var def: Dictionary = state.trauma_def(id)
        var trauma: Dictionary = state.traumas[id]
        var line: String = "向き合って、ほどけた" if trauma.resolved and state.slot_of(id) < 0 and not def.has("deeper") else ("奥から別の言葉が出てきた" if trauma.resolved and def.has("deeper") and state.traumas.has(def.deeper) else ("向き合って、ほどけた" if trauma.resolved else "強さ %d　·　%s" % [trauma.strength, "ほぐれている" if trauma.unraveled else "まだ固い"]))
        text += "[color=#8a5a6a]「%s」 / %s[/color]\n%s\n\n" % [def.word, def.speaker, line]
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
