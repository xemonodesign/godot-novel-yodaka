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
const ANSWERS = ["嬉しかった", "自分らしくないと思った", "まだ、わからない"]
const RESPONSES = ["法月さんには、そんなふうに届いたんですね。\nその嬉しさを、覚えておいてもいいと思います。",
    "しっくりこないと感じたことも、\n法月さん自身を知る、大切な手がかりですね。",
    "今、うまく言葉にできなくても大丈夫です。\n法月さんの中で、ゆっくり考えていきましょう。"]
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
var night_selected: String = ""
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
    status = _label(stage, "WEB PROTOTYPE  /  03", Rect2(927, 25, 310, 26), 13, Color("dce5d9"))
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
    _label(content, "変わった身体。まだ、名前のない気持ち。\n寄り道で言葉を集め、夜に見つめて、自分を考える。", Rect2(94, 361, 580, 72), 20)
    _button(content, "はじめから   →", Rect2(94, 470, 245, 57), _start_new, true)
    var resume := _button(content, "つづきから", Rect2(355, 470, 230, 57), _resume)
    resume.disabled = not state.has_save()
    _label(content, "カウンセリング → 寄り道と本編を%d周 → 総括のカウンセリング" % state.data.rounds.size(), Rect2(94, 545, 600, 25), 14, MUTED)
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
        _modal("保存を読み込めませんでした", "以前の流れの保存データか、形式を確認できないデータです。\n「はじめから」で新しい流れを遊べます。", "閉じる", _close_overlay)

func _draw_bottom() -> void:
    _clear(bottom)
    stat_bars.clear()
    stat_labels.clear()
    _panel(bottom, Rect2(44, 612, 224, 155), DARK)
    _label(bottom, "いまの輪郭", Rect2(59, 620, 170, 23), 14, Color("d9e5d3"))
    _label(bottom, "カルテ ▸", Rect2(196, 622, 66, 20), 11, Color("81947f")).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    for i in range(State.STAT_NAMES.size()):
        _label(bottom, State.STAT_NAMES[i], Rect2(60, 648 + i * 27, 78, 20), 13, Color("b9c1b8"))
        var bar := ProgressBar.new()
        bar.position = Vector2(141, 656 + i * 27)
        bar.size = Vector2(76, 7)
        bar.show_percentage = false
        bar.add_theme_font_size_override("font_size", 1)
        bar.value = state.stats[i]
        bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bar.add_theme_stylebox_override("background", _box(Color("36403a")))
        bar.add_theme_stylebox_override("fill", _box(Color("d1b6aa") if i == 0 else MINT))
        bottom.add_child(bar)
        bar.size = Vector2(76, 7)
        stat_bars.append(bar)
        stat_labels.append(_label(bottom, str(int(state.stats[i])), Rect2(225, 647 + i * 27, 32, 22), 13, PAPER))
    # The whole outline panel opens the karte.
    var karte_hit := Button.new()
    karte_hit.position = Vector2(44, 612)
    karte_hit.size = Vector2(224, 155)
    karte_hit.flat = true
    karte_hit.tooltip_text = "カルテを開く"
    karte_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    karte_hit.pressed.connect(_show_karte.bind(Callable()))
    bottom.add_child(karte_hit)
    _panel(bottom, Rect2(280, 612, 956, 155), DARK)
    _label(bottom, "もらった言葉", Rect2(296, 619, 270, 26), 15, PAPER)
    count_label = _label(bottom, _count_text(), Rect2(793, 620, 425, 24), 13, Color("a2b49f"))
    count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var slots: int = maxi(8, state.collected.size())
    var spacing: float = 928.0 / slots
    for i in range(slots):
        var x: float = 294 + i * spacing
        _panel(bottom, Rect2(x, 653, spacing - 7, 103), Color("1e2823"), Color("364338"))
        _label(bottom, "%02d" % (i + 1), Rect2(x + 6, 657, 28, 20), 11, Color("81947f"))
        if i < state.collected.size():
            var word: Dictionary = state.word_by_id(state.collected[i])
            var crystals: int = state.crystal_count(word.id)
            var specimen = Specimen.new()
            specimen.position = Vector2(x + (spacing - 78) / 2, 654)
            specimen.size = Vector2(78, 68)
            bottom.add_child(specimen)
            specimen.setup(word.model, Color(word.color), crystals)
            if crystals > 0:
                _label(bottom, "★%d" % crystals, Rect2(x + spacing - 40, 656, 32, 20), 12, Color("f3d79e") if crystals >= State.BONUS_EVERY else Color("c9b985")).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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

func _count_text() -> String:
    var total := 0
    for id in state.collected:
        total += state.crystal_count(id)
    return "%02d 個    ·    結晶 %02d    ·    読んだ言葉 %03d" % [state.collected.size(), total, state.read_count]

func _animate_stats(before: Array) -> void:
    for i in range(State.STAT_NAMES.size()):
        if i >= stat_bars.size() or int(before[i]) == int(state.stats[i]):
            continue
        var bar: ProgressBar = stat_bars[i]
        var target := float(state.stats[i])
        var change: int = int(state.stats[i]) - int(before[i])
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
        number.text = str(int(state.stats[i]))
        number.pivot_offset = number.size / 2
        number.scale = Vector2(1.7, 1.7)
        number.add_theme_color_override("font_color", Color("d9e5a3") if up else Color("e8b0a0"))
        var pop := create_tween().bind_node(number)
        pop.set_parallel(true)
        pop.tween_property(number, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        pop.tween_property(number, "theme_override_colors/font_color", PAPER, 1.2)
        var floating := _label(bottom, "%s%d" % ["+" if up else "", change], Rect2(bar.position.x + 20, bar.position.y - 12, 60, 20), 15, Color("d9e5a3") if up else Color("e8b0a0"))
        floating.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        var drift := create_tween().bind_node(floating)
        drift.set_parallel(true)
        drift.tween_property(floating, "position:y", floating.position.y - 22, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
        drift.tween_property(floating, "modulate:a", 0.0, 1.1).set_delay(0.3)
        drift.chain().tween_callback(floating.queue_free)
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
    var note_text := "地図のピンをクリックすると出かけます。\n出かけるとストレス +%d。" % int(State.OUTING_EFFECTS["ストレス"])
    if state.stress_locked():
        note_text = "ストレスが %d。\n疲れていて、今日は出かけられない。\n家で休んで、ストレスを下げよう。" % int(state.stats[0])
    var note := _label(content, note_text, Rect2(854, 292, 320, 200), 16, Color("c8d5c5"))
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    # Only places Yodaka can go today are pinned; everything else stays off the map.
    for i in range(state.data.map_events.size()):
        var event: Dictionary = state.data.map_events[i]
        if not state.event_available(event.id):
            continue
        var pin: Array = event.get("pin", [40 + (i % 3) * 240, 30 + (i / 3) * 65])
        var text: String = "●  " + event.label
        if event.get("repeatable", false):
            text += "（ストレス %d）" % int(state.data.nodes["rest_2"].effects["ストレス"])
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
    var candidates: Array = state.grow_candidates()
    var next_text := {"map": "眠ると、次の自由行動へ。", "chapter": "眠ると、本編 CHAPTER %02d へ（ストレス +%d）。" % [int(state.current_round().get("chapter", "main1").trim_prefix("main")), int(State.CHAPTER_EFFECTS["ストレス"])], "counseling": "眠ると、総括のカウンセリングへ。一度も見つめなかった言葉は忘れてしまう。"}
    if state.night_step == "reply":
        var word: Dictionary = state.word_by_id(state.night_word)
        var answer: Dictionary = state.answer_for(word.id)
        var count: int = state.crystal_count(word.id)
        _label(content, "「%s」を見つめた。" % word.word, Rect2(77, 140, 900, 44), 30, PAPER)
        var specimen = Specimen.new()
        specimen.position = Vector2(80, 200)
        specimen.size = Vector2(240, 240)
        content.add_child(specimen)
        specimen.setup(word.model, Color(word.color), count)
        _label(content, "よだか", Rect2(360, 206, 200, 26), 15, Color("a8b7a8"))
        var reply := _label(content, word.interpretations[int(answer.choice)].reply, Rect2(360, 240, 820, 130), 22, PAPER)
        reply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _label(content, _delta_text(answer.delta), Rect2(360, 380, 820, 30), 16, Color("d9e5a3"))
        var note_line: String = "結晶が %d 個になった。" % count
        if answer.get("bonus", false):
            note_line += "　結晶 %d 個のボーナス！" % count
        else:
            note_line += "　あと %d 個でボーナス。" % (State.BONUS_EVERY - count % State.BONUS_EVERY)
        _label(content, note_line, Rect2(360, 420, 820, 30), 16, Color("f3d79e"))
        _button(content, "眠る（ストレス %d）  →" % int(State.SLEEP_EFFECTS["ストレス"]), Rect2(884, 520, 320, 46), _sleep, true)
        _label(content, next_text[state.after_night], Rect2(77, 530, 800, 26), 14, Color("8d9c8d"))
        return
    if candidates.is_empty():
        _label(content, "見つめる言葉は、まだない。", Rect2(77, 140, 900, 44), 30, PAPER)
        _label(content, "自由行動や本編で言葉をもらうと、夜にひとつ選んで見つめられます。\n見つめるたびに結晶が増え、よだかの輪郭を動かします。", Rect2(77, 210, 1000, 80), 18, Color("c8d5c5"))
    else:
        _label(content, "もらった言葉を、ひとつ見つめる。", Rect2(77, 140, 900, 44), 30, PAPER)
        _label(content, "一晩にひとつ、結晶がひとつ。結晶 %d 個ごとに大きなボーナス。一度も見つめなかった言葉は総括の前に忘れてしまう。" % State.BONUS_EVERY, Rect2(77, 190, 1100, 26), 15, Color("8d9c8d"))
        for i in range(mini(candidates.size(), 14)):
            var word: Dictionary = state.word_by_id(candidates[i])
            var count: int = state.crystal_count(word.id)
            var x: float = 80 + (i % 7) * 88
            var y: float = 228 + (i / 7) * 132
            var selected: bool = word.id == night_selected
            _panel(content, Rect2(x, y, 84, 122), Color("1c262b") if selected else Color("141c20"), Color("f3d79e") if selected else Color("2c393f"), 4)
            var specimen = Specimen.new()
            specimen.position = Vector2(x + 3, y + 4)
            specimen.size = Vector2(78, 68)
            content.add_child(specimen)
            specimen.setup(word.model, Color(word.color), count)
            if count > 0:
                _label(content, "★%d" % count, Rect2(x + 46, y + 4, 36, 16), 11, Color("f3d79e") if count >= State.BONUS_EVERY else Color("c9b985")).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
            var label := _label(content, word.word, Rect2(x + 3, y + 74, 78, 44), 11, PAPER)
            label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            var hit := Button.new()
            hit.position = Vector2(x, y)
            hit.size = Vector2(84, 122)
            hit.flat = true
            hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
            hit.pressed.connect(_pick_night_word.bind(word.id))
            content.add_child(hit)
        if night_selected != "" and candidates.has(night_selected):
            var word: Dictionary = state.word_by_id(night_selected)
            var answer: Dictionary = state.answer_for(word.id)
            _panel(content, Rect2(700, 224, 504, 286), Color("1c262b"), Color("2c393f"), 4)
            var crystal_note: String = "結晶 %d" % state.crystal_count(word.id) + ("　·　次でボーナス！" if state.bonus_pending(word.id) else "")
            _label(content, "「%s」  /  %s　　%s" % [word.word, word.speaker, crystal_note], Rect2(716, 234, 470, 28), 17, Color("f3d79e"))
            var quote := _label(content, word.quote, Rect2(716, 264, 472, 80), 13, Color("c8d5c5"))
            quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            preview_labels.clear()
            for i in range(3):
                var interpretation: Dictionary = word.interpretations[i]
                var delta: Array = state.preview_interpretation(word.id, i)
                var current_mark: String = "（いまの受け取り方）" if not answer.is_empty() and int(answer.choice) == i else ""
                var text: String = interpretation.label + current_mark + "\n" + _preview_text(state.interpretation_effects(word.id, i), delta)
                var button := _button(content, text, Rect2(716, 350 + i * 52, 472, 46), _grow.bind(word.id, i), false)
                button.add_theme_font_size_override("font_size", 14)
                preview_labels.append(button.text)
        else:
            _label(content, "← 言葉を選ぶと、\n  3つの受け取り方が出ます。", Rect2(716, 250, 470, 60), 16, Color("8d9c8d"))
    _button(content, "今夜は眠る（ストレス %d）  →" % int(State.SLEEP_EFFECTS["ストレス"]), Rect2(884, 520, 320, 46), _sleep, true)
    _label(content, next_text[state.after_night], Rect2(77, 530, 800, 26), 14, Color("8d9c8d"))
    if not night_intro_seen and state.night_step == "pick":
        _show_interlude("night")
func _pick_night_word(id: String) -> void:
    night_selected = id
    _show_night()

func _grow(id: String, index: int) -> void:
    if mode != "night" or is_instance_valid(overlay):
        return
    var before: Array = state.stats.duplicate()
    if state.grow(id, index).is_empty():
        return
    night_selected = ""
    _show_night()
    _animate_stats(before)

func _sleep() -> void:
    if mode != "night" or is_instance_valid(overlay):
        return
    night_selected = ""
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
        var caption := _center_label(overlay, "部屋に戻って、今日もらった言葉を見つめる。", Rect2(90, 430, 1100, 36), 18, Color("b5c1b5"))
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
    else:
        var word: Dictionary = state.word_by_id(state.pending_word)
        _center_label(overlay, "言葉を、ひとつもらった。", Rect2(90, 118, 1100, 42), 18, MINT)
        var effect = WordEffect.new()
        effect.position = Vector2(440, 165)
        effect.size = Vector2(400, 350)
        effect.tint = Color(word.color)
        overlay.add_child(effect)
        var specimen = Specimen.new()
        specimen.position = Vector2(505, 207)
        specimen.size = Vector2(270, 255)
        overlay.add_child(specimen)
        specimen.setup(word.model, Color(word.color))
        _center_label(overlay, "「%s」" % word.word, Rect2(90, 500, 1100, 66), 35, PAPER)
        _center_label(overlay, word.speaker + " から、よだかへ", Rect2(90, 572, 1100, 32), 17, Color("a8b7a8"))
        var delta: Array = state.gains.get(word.id, [])
        _center_label(overlay, _delta_text(delta) if not delta.is_empty() else "", Rect2(90, 618, 1100, 32), 18, Color("d9e5a3"))
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
    if not interlude_ready or overlay_kind not in ["scene", "word", "night"]:
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
        elif kind == "word":
            state.pending_word = ""
        else:
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
    var before: Array = state.stats.duplicate()
    if mode == "story":
        added = state.finish_line()
    else:
        var id: String = "counsel_%s_%d" % [state.counsel_step, state.reviewed]
        if state.history.is_empty() or state.history.back().id != id:
            state.history.append({"id": id, "speaker": current_dialogue.speaker, "text": current_dialogue.text})
        state.save_game()
    if added:
        _draw_bottom()
        _animate_stats(before)
        hint.text = "＋ 言葉をもらった"
    else:
        count_label.text = _count_text()
        if state.has_change(state.last_delta):
            _animate_stats(before)
            hint.text = _delta_text(state.last_delta)
    if state.last_error != "":
        status.text = state.last_error
    next_button.text = "カルテを見る  →" if current_dialogue.get("karte", false) else "つづきを読む  →"
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
            var note := ""
            if choice.has("requires"):
                note = "%s %d 必要（現在 %d）" % [choice.requires.stat, choice.requires.min, state.stats[State.STAT_NAMES.find(choice.requires.stat)]]
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
    var before: Array = state.stats.duplicate()
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
        if mode in ["story", "counseling"] and Rect2(44, 76, 1192, 450).has_point(stage.get_local_mouse_position()):
            _advance()

func _show_counseling() -> void:
    mode = "counseling"
    auto_mode = false
    feedback = false
    var step: String = state.counsel_step
    var speaker := "みなと"
    var text := ""
    var word: Dictionary = state.review_word()
    if step == "forget":
        _show_forgetting()
        return
    match step:
        "opening_doctor":
            text = "こんにちは、法月さん。\nこの数週間は、どうでしたか？"
        "opening_yodaka":
            speaker = "よだか"
            text = "いろんな人と話しました。\n%d個の言葉を、持ち帰ってきました。" % state.collected.size()
            if not state.forgotten.is_empty() and not state.collected.is_empty():
                text = "いろんな人と話しました。\n忘れてしまった言葉もあるけど、\n%d個は、持ち帰ってこられました。" % state.collected.size()
            if state.collected.is_empty():
                text = "……いろいろ言われた気がするのに、\nどれも、うまく思い出せません。"
        "recall":
            speaker = "よだか"
            text = word.memory
        "grown_reply", "reply":
            speaker = "よだか"
            text = word.interpretations[int(state.answer_for(word.id).choice)].reply
        "question":
            text = "「%s」……。\n法月さんは、その時どう感じましたか？" % word.word
        "choice":
            speaker = "よだか"
            text = "あの時、僕は……。"
        "response":
            text = RESPONSES[int(state.answer_for(word.id).choice)]
        "closing":
            text = "お話しいただきありがとうございます。\nこちらが、今回の「メンタル〇〇」になります。"
        "farewell":
            text = "受け取った言葉を飾って、ときには整理して。\n居心地よくいられる時間が、少しでも続きますように。\nでは、お大事にどうぞ。法月さん"
    _render_dialogue({"speaker": speaker, "text": text, "chapter": "総括のカウンセリング",
        "chapter_index": 0, "kind": "counsel", "place": "診察室", "partner": "みなと", "karte": step == "closing"})
    status.text = "カウンセリング  /  よだかとみなと"
    if step in ["reply", "grown_reply"]:
        body.size.y = 145
        var answer: Dictionary = state.answer_for(word.id)
        var line: String = _delta_text(answer.delta) if step == "reply" else "夜に見つめた言葉　/　" + ANSWERS[int(answer.choice)]
        _center_label(content, line, Rect2(333, 501, 614, 24), 15, Color("597c51"))
    _check_interlude()

func _show_forgetting() -> void:
    body = null
    _base()
    _panel(content, Rect2(44, 76, 1192, 516), NIGHT)
    _label(content, "COUNSELING  /  診察室へ向かう朝", Rect2(77, 94, 780, 34), 17, Color("8d9c8d"))
    _label(content, "結晶が足りなかった言葉は、こぼれ落ちてしまった。", Rect2(77, 140, 1000, 44), 28, PAPER)
    _label(content, "一度も見つめなかった言葉は、診察室に着くころには思い出せない。\n残った言葉だけを、みなとに話す。", Rect2(77, 192, 1000, 60), 16, Color("c8d5c5"))
    for i in range(mini(state.forgotten.size(), 10)):
        var word: Dictionary = state.word_by_id(state.forgotten[i])
        var x: float = 80 + (i % 5) * 200
        var y: float = 262 + (i / 5) * 122
        var specimen = Specimen.new()
        specimen.position = Vector2(x + 50, y)
        specimen.size = Vector2(90, 78)
        content.add_child(specimen)
        specimen.setup(word.model, Color(word.color), state.crystal_count(word.id))
        var label := _label(content, "「%s」　結晶 %d" % [word.word, state.crystal_count(word.id)], Rect2(x, y + 82, 190, 24), 13, Color("8d9c8d"))
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        var fade := create_tween().bind_node(specimen)
        fade.tween_property(specimen, "modulate:a", 0.18, 2.4).set_delay(0.3 + i * 0.2)
    _label(content, "残った言葉 %d 個" % state.collected.size(), Rect2(77, 530, 600, 26), 15, Color("f3d79e"))
    _button(content, "診察室へ  →", Rect2(884, 520, 320, 46), _advance_counseling, true)

func _advance_counseling() -> void:
    if state.counsel_step == "choice":
        return
    state.advance_counseling()
    _show_story()

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

func _counsel_choices() -> void:
    next_button.visible = false
    var word: Dictionary = state.review_word()
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
    if feedback or state.counsel_step != "choice" or not completed or is_instance_valid(overlay):
        return
    feedback = true
    var before: Array = state.stats.duplicate()
    var delta: Array = state.interpret(index)
    if delta.is_empty():
        feedback = false
        return
    _show_counseling()
    _animate_stats(before)

func _stress_note() -> String:
    var stress: int = int(state.stats[0])
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
    for i in range(State.STAT_NAMES.size()):
        var y: int = 118 + i * 54
        _label(card, State.STAT_NAMES[i], Rect2(40, y, 100, 30), 19)
        var bar := ProgressBar.new()
        bar.position = Vector2(140, y + 8)
        bar.size = Vector2(210, 14)
        bar.show_percentage = false
        bar.add_theme_font_size_override("font_size", 1)
        bar.value = state.stats[i]
        bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bar.add_theme_stylebox_override("background", _box(Color("e4e6df")))
        bar.add_theme_stylebox_override("fill", _box(Color("c98f7c") if i == 0 else Color("7fae70")))
        card.add_child(bar)
        bar.size = Vector2(210, 14)
        _label(card, str(int(state.stats[i])), Rect2(362, y, 60, 30), 19)
    var notes := "ストレス：出かけると+%d、本編で+%d。%d以上で外出できず、休むと下がる。\n勇気：本編の選択肢に必要。　自認：自分の捉え方への納得度。　キラキラ：人前での輝き。\n\n夜に見つめた言葉には結晶がつき、%d 個ごとにボーナス。一度も見つめなかった言葉は総括の前に忘れてしまう。" % [int(State.OUTING_EFFECTS["ストレス"]), int(State.CHAPTER_EFFECTS["ストレス"]), State.STRESS_LIMIT, State.BONUS_EVERY]
    var note := _label(card, notes, Rect2(40, 340, 385, 150), 13, MUTED)
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    # The mental map: darkness that each kept word lights up, wider with every crystal.
    _label(card, "ことばの地図", Rect2(456, 74, 200, 26), 15, MUTED)
    var total := 0
    for id in state.collected:
        total += state.crystal_count(id)
    _label(card, "%d 語　·　結晶 %d" % [state.collected.size(), total], Rect2(620, 76, 180, 24), 12, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var map = MindMap.new()
    map.position = Vector2(440, 100)
    map.size = Vector2(375, 412)
    card.add_child(map)
    var count: int = state.collected.size()
    for i in range(count):
        var word: Dictionary = state.word_by_id(state.collected[i])
        map.lit.append({"pos": map.node_position(i, count), "color": Color(word.color), "crystals": state.crystal_count(word.id)})
    for i in range(state.forgotten.size()):
        var word: Dictionary = state.word_by_id(state.forgotten[i])
        map.embers.append({"pos": map.node_position(count + i, count + state.forgotten.size()) * 0.5 + map.size * 0.25, "color": Color(word.color)})
    map.unknown = maxi(0, state.data.words.size() - count - state.forgotten.size())
    for i in range(count):
        var word: Dictionary = state.word_by_id(state.collected[i])
        var crystals: int = state.crystal_count(word.id)
        var spot: Vector2 = map.position + map.node_position(i, count)
        var specimen = Specimen.new()
        specimen.position = spot - Vector2(30, 38)
        specimen.size = Vector2(60, 56)
        card.add_child(specimen)
        specimen.setup(word.model, Color(word.color), crystals)
        var label := _label(card, word.word, Rect2(spot.x - 55, spot.y + 18, 110, 30), 10, PAPER)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        if crystals > 0:
            _label(card, "★%d" % crystals, Rect2(spot.x + 14, spot.y - 40, 40, 16), 11, Color("f3d79e") if crystals >= State.BONUS_EVERY else Color("c9b985"))
    var footer: String = "まだ暗い場所 %d" % map.unknown if count > 0 else "まだ何も照らされていない。"
    if not state.forgotten.is_empty():
        footer += "　·　消えた光 %d" % state.forgotten.size()
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
    _label(content, "%d 個の言葉が残り、%d 個を忘れました。　ストレス %d　/　勇気 %d　/　自認 %d　/　キラキラ %d" % [state.collected.size(), state.forgotten.size(), state.stats[0], state.stats[1], state.stats[2], state.stats[3]], Rect2(86, 450, 1100, 38), 18, MUTED)
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
    specimen.setup(word.model, Color(word.color), state.crystal_count(word.id))
    _label(card, "結晶 %d" % state.crystal_count(word.id), Rect2(37, 424, 219, 24), 14, Color("8d9c8d")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    var quote := _label(card, word.quote, Rect2(291, 162, 520, 200), 23)
    quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var gained: Array = state.gains.get(word.id, [])
    _label(card, "もらった時：" + (_delta_text(gained) if not gained.is_empty() else "—"), Rect2(291, 372, 520, 30), 15, MUTED)
    var feeling := "まだ見つめていない言葉。夜に見つめると結晶がつきます。"
    var answer: Dictionary = state.answer_for(word.id)
    if not answer.is_empty():
        feeling = "いまの受け取り方：%s　（前回 %s）" % [ANSWERS[int(answer.choice)], _delta_text(answer.delta)]
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
    for id in state.collected:
        var word: Dictionary = state.word_by_id(id)
        var answer: Dictionary = state.answer_for(id)
        var line: String = "まだ見つめていない"
        if not answer.is_empty():
            line = ANSWERS[int(answer.choice)] + "　·　結晶 %d" % state.crystal_count(id)
        text += "[color=#6b8563]「%s」 / %s[/color]\n%s\n\n" % [word.word, word.speaker, line]
    for id in state.forgotten:
        var word: Dictionary = state.word_by_id(id)
        text += "[color=#9a9a9a]「%s」 / %s　—　忘れてしまった（結晶 %d）[/color]\n\n" % [word.word, word.speaker, state.crystal_count(id)]
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
