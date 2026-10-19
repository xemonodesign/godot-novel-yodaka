extends Control

const State = preload("res://src/story_state.gd")
const Specimen = preload("res://src/specimen.gd")
const WordEffect = preload("res://src/word_effect.gd")
const INK = Color("252c2a")
const MUTED = Color("778078")
const PAPER = Color("fcfbf6")
const MINT = Color("c7e5ba")
const DARK = Color("171e1c")
const NIGHT = Color("10161a")
const ROSE = Color("e0a58f")
const GOLD = Color("f3d79e")
const OPENING_TEXT = {
    "doctor": "では、さっそく「メンタル〇〇」を開いてみましょう。\n……言葉を置く欄が、もう埋まっていますね。\n今日は、この中からひとつだけ、話してみませんか。",
    "yodaka": "……はい。全部、僕がずっと抱えてきたものです。\n言葉を置く場所が、ないみたいだ。",
    "closing": "今日はここまでにしましょう。\n向き合う力は、人と話すたびに少しずつ溜まります。\n次に会う時、また一緒に整理しましょう。",
    "farewell": "では、お大事にどうぞ。法月さん"}
const SESSION_TEXT = {
    "doctor": "こんにちは、法月さん。\nこの数週間は、どうでしたか？",
    "yodaka": "いろんな人と話しました。\n%d個の言葉を、持ち帰ってきました。",
    "yodaka_none": "……あまり、人と話せませんでした。\nでも、少しだけ休めた気がします。",
    "closing": "お話しいただきありがとうございます。\nこちらが、今回の「メンタル〇〇」になります。",
    "farewell": "整理したものも、まだ固いままのものも、法月さんのものです。\nでは、お大事にどうぞ。法月さん",
    "final_farewell": "受け取った言葉を飾って、ときには整理して。\n居心地よくいられる時間が、少しでも続きますように。\nでは、お大事にどうぞ。法月さん"}
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
var session_selected: int = -1
var session_cards: Array = []
var session_result: Dictionary = {}
var slot_buttons: Array = []

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

func _wrap(parent: Node, text: String, rect: Rect2, font_size: int = 18, color: Color = INK) -> Label:
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

func _bar(parent: Node, rect: Rect2, value: float, fill: Color, back: Color) -> ProgressBar:
    var bar := ProgressBar.new()
    bar.position = rect.position
    bar.size = rect.size
    bar.show_percentage = false
    bar.add_theme_font_size_override("font_size", 1)
    bar.value = value
    bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    bar.add_theme_stylebox_override("background", _box(back))
    bar.add_theme_stylebox_override("fill", _box(fill))
    parent.add_child(bar)
    bar.size = rect.size
    return bar

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

func _specimen(parent: Node, entry: String, rect: Rect2) -> Control:
    var specimen = Specimen.new()
    specimen.position = rect.position
    specimen.size = rect.size
    parent.add_child(specimen)
    if entry.begins_with("t:"):
        var trauma: Dictionary = state.trauma_by_id(entry.trim_prefix("t:"))
        specimen.setup("thorn", Color(trauma.color), false, state.hardness(trauma.id))
    else:
        var word: Dictionary = state.word_by_id(entry.trim_prefix("w:"))
        specimen.setup(word.model, Color(word.color), state.word_level(word.id) > 1)
    return specimen

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
    _label(content, "言葉を置く欄は、トラウマで埋まっている。\n人の言葉を集め、カウンセリングで少しずつ、ほぐしていく。", Rect2(94, 361, 580, 72), 20)
    _button(content, "はじめから   →", Rect2(94, 470, 245, 57), _start_new, true)
    var resume := _button(content, "つづきから", Rect2(355, 470, 230, 57), _resume)
    resume.disabled = not state.has_save()
    _label(content, "カウンセリング → 寄り道と本編を%d周 → 途中と最後にカウンセリング" % state.data.rounds.size(), Rect2(94, 545, 600, 25), 14, MUTED)
    _panel(content, Rect2(870, 530, 320, 40), PAPER)
    _label(content, "法月 よだか  /  主人公", Rect2(895, 534, 275, 30), 17)
    _label(stage, "CLICK / SPACE  文字送り     ·     下の欄をクリックすると、トラウマや言葉を読み返せます", Rect2(44, 777, 1160, 20), 13, PAPER)

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

func _format_exp(amount: int) -> String:
    return State._format_exp(amount)

func _draw_bottom() -> void:
    _clear(bottom)
    stat_bars.clear()
    stat_labels.clear()
    slot_buttons.clear()
    _panel(bottom, Rect2(44, 612, 224, 155), DARK)
    _label(bottom, "いまの輪郭", Rect2(59, 620, 170, 23), 14, Color("d9e5d3"))
    var effective: Array = state.effective_stats()
    for i in range(State.STAT_NAMES.size()):
        _label(bottom, State.STAT_NAMES[i], Rect2(60, 648 + i * 27, 78, 20), 13, Color("b9c1b8"))
        var bar := _bar(bottom, Rect2(141, 656 + i * 27, 76, 7), effective[i], Color("d1b6aa") if i == 0 else MINT, Color("36403a"))
        stat_bars.append(bar)
        var tint := PAPER
        var shift: int = state.stat_offset(i)
        if effective[i] < int(state.stats[i]) or state.stat_cap(i) < 100:
            tint = ROSE
        elif shift > 0:
            tint = Color("d9e5a3")
        stat_labels.append(_label(bottom, str(effective[i]), Rect2(225, 647 + i * 27, 32, 22), 13, tint))
    _panel(bottom, Rect2(280, 612, 956, 155), DARK)
    _label(bottom, "ことばの欄", Rect2(296, 619, 200, 26), 15, PAPER)
    count_label = _label(bottom, _count_text(), Rect2(500, 621, 480, 24), 13, Color("a2b49f"))
    count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    exp_label = _label(bottom, _format_exp(state.exp), Rect2(1000, 616, 220, 30), 20, GOLD)
    exp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var slots: int = state.slots.size()
    var spacing: float = 928.0 / slots
    for i in range(slots):
        var x: float = 294 + i * spacing
        var entry: String = state.slots[i]
        var selected: bool = mode == "session" and session_selected == i
        var border := Color("364338")
        if selected:
            border = GOLD
        elif entry.begins_with("t:"):
            border = Color("5a3a3a")
        _panel(bottom, Rect2(x, 653, spacing - 7, 103), Color("1e2823") if entry != "" else Color("182019"), border)
        _label(bottom, "%02d" % (i + 1), Rect2(x + 6, 657, 28, 20), 11, Color("81947f"))
        if entry.begins_with("t:"):
            var trauma: Dictionary = state.trauma_by_id(entry.trim_prefix("t:"))
            _specimen(bottom, entry, Rect2(x + (spacing - 78) / 2, 652, 78, 62))
            _label(bottom, "固さ %d" % state.hardness(trauma.id), Rect2(x + spacing - 58, 656, 50, 18), 10, ROSE).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
            _bar(bottom, Rect2(x + 8, 716, spacing - 23, 3), state.hardness(trauma.id), Color("9a4b4b"), Color("2b2626"))
            var label := _label(bottom, trauma.name, Rect2(x + 3, 722, spacing - 13, 32), 11, Color("e3c9c9"))
            label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        elif entry.begins_with("w:"):
            var word: Dictionary = state.word_by_id(entry.trim_prefix("w:"))
            _specimen(bottom, entry, Rect2(x + (spacing - 78) / 2, 654, 78, 68))
            _label(bottom, "Lv%d" % state.word_level(word.id), Rect2(x + spacing - 48, 656, 40, 18), 11, GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
            var label := _label(bottom, word.word, Rect2(x + 3, 722, spacing - 13, 32), 11, PAPER)
            label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        else:
            _label(bottom, "·", Rect2(x + 49, 675, 20, 30), 28, Color("465344"))
            _label(bottom, "あいている枠", Rect2(x + 16, 730, 95, 20), 10, Color("8fa38a"))
        var hit := Button.new()
        hit.position = Vector2(x, 653)
        hit.size = Vector2(spacing - 7, 103)
        hit.flat = true
        hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        hit.pressed.connect(_slot_pressed.bind(i))
        bottom.add_child(hit)
        slot_buttons.append(hit)

func _count_text() -> String:
    return "トラウマ %d  ·  言葉 %d  ·  ほどけた %d  ·  読んだ %03d" % [state.active_traumas().size(), state.kept_words().size(), state.resolved.size(), state.read_count]

func _slot_pressed(index: int) -> void:
    if is_instance_valid(overlay):
        return
    var entry: String = state.slots[index]
    if mode == "session":
        if session_selected != index:
            session_cards.clear()
        session_selected = index
        _show_session()
        return
    if entry.begins_with("t:"):
        _show_trauma(state.trauma_by_id(entry.trim_prefix("t:")))
    elif entry.begins_with("w:"):
        _show_word(state.word_by_id(entry.trim_prefix("w:")))

func _animate_stats(before: Array) -> void:
    var effective: Array = state.effective_stats()
    for i in range(State.STAT_NAMES.size()):
        if i < stat_bars.size() and int(before[i]) != effective[i]:
            stat_bars[i].value = before[i]
            create_tween().tween_property(stat_bars[i], "value", float(effective[i]), 0.7)
            stat_labels[i].text = str(effective[i])

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
        "リビング": "living", "ファミレス": "restaurant", "ファミレス(昼)": "restaurant",
        "喫茶店": "cafe", "自然公園": "park", "街": "street"}
    return "res://src/assets/backgrounds/%s.png" % backgrounds.get(place, "street")

func _chapter_title(id: String) -> String:
    for chapter in state.data.chapters:
        if chapter.id == id:
            return chapter.title
    return ""

func _show_map() -> void:
    mode = "map"
    auto_mode = false
    body = null
    _base()
    var round_info: Dictionary = state.current_round()
    var week: int = state.round_index + 1
    var remaining: int = int(round_info.outings) - state.outings_done
    _panel(content, Rect2(44, 76, 1192, 516), PAPER)
    _label(content, "MAP  /  第%d週の寄り道" % week, Rect2(77, 94, 780, 38), 23)
    _image(content, "res://bg.png", Rect2(76, 148, 730, 409))
    _panel(content, Rect2(830, 148, 374, 409), DARK)
    _label(content, "今日は、どこへ行こう。", Rect2(853, 173, 330, 43), 23, PAPER)
    var note_text := "寄り道  %d / %d\n\n" % [state.outings_done + 1, int(round_info.outings)]
    note_text += "あと%d回寄り道すると、\nCHAPTER %02d「%s」へ。\n\n" % [remaining, int(round_info.get("chapter", "main1").trim_prefix("main")), _chapter_title(round_info.chapter)]
    note_text += "出かけるとストレス +%d。\n会話を読むたびに EXP が溜まり、\nもらった言葉は留めるか手放すかを選ぶ。" % int(State.OUTING_EFFECTS["ストレス"])
    if state.stress_locked():
        note_text = "ストレスが %d。\n疲れていて、今日は出かけられない。\n\n家で休んで、ストレスを下げよう。" % state.effective(0)
    _wrap(content, note_text, Rect2(854, 238, 320, 275), 17, Color("c8d5c5"))
    var positions := [Vector2(95, 175), Vector2(465, 175), Vector2(95, 300), Vector2(465, 300), Vector2(95, 425), Vector2(465, 425)]
    for i in range(mini(state.data.map_events.size(), positions.size())):
        var event: Dictionary = state.data.map_events[i]
        var available: bool = state.event_available(event.id)
        var button := _button(content, "%02d  %s\n%s" % [i + 1, event.label, event.title], Rect2(positions[i], Vector2(316, 72)), _select_map_event.bind(event.id), true)
        button.disabled = not available
        var reason := ""
        if state.visited.has(event.id) and not event.get("repeatable", false):
            reason = "行った"
        elif int(event.unlock) > week:
            reason = "第%d週から" % int(event.unlock)
        elif not available and state.stress_locked():
            reason = "疲れていて行けない"
        elif event.get("repeatable", false):
            reason = "ストレス %d" % int(state.data.nodes["rest_2"].effects["ストレス"])
        if reason != "":
            _label(content, reason, Rect2(positions[i] + Vector2(6, 76), Vector2(300, 22)), 12, PAPER)
    _button(content, "カルテ", Rect2(854, 509, 160, 38), _show_karte.bind(Callable()))
    _button(content, "タイトル", Rect2(1030, 509, 160, 38), _show_title)

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
    if node.has("choices"):
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
    _fill_interlude()
    overlay.modulate.a = 0
    interlude_tween = create_tween()
    interlude_tween.tween_property(overlay, "modulate:a", 1.0, 0.45)
    interlude_tween.tween_callback(func(): interlude_ready = true)
    # Buttons underneath must not retain keyboard focus during an interlude.
    var focused := get_viewport().gui_get_focus_owner()
    if focused != null:
        focused.release_focus()

func _fill_interlude() -> void:
    _clear(overlay)
    _panel(overlay, Rect2(0, 0, 1280, 800), Color("0b100e") if overlay_kind != "surfaced" else Color("1a0b0d"))
    match overlay_kind:
        "scene":
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
        "word":
            _fill_word_offer()
        "resolved":
            var trauma: Dictionary = state.trauma_by_id(session_result.id)
            _center_label(overlay, "トラウマがひとつ、ほどけた。", Rect2(90, 150, 1100, 42), 18, MINT)
            var effect = WordEffect.new()
            effect.position = Vector2(440, 190)
            effect.size = Vector2(400, 320)
            effect.tint = MINT
            overlay.add_child(effect)
            _center_label(overlay, "「%s」" % trauma.name, Rect2(90, 300, 1100, 66), 35, PAPER)
            _center_label(overlay, "固さ %d → 0　/　枠がひとつ、空いた。" % session_result.before, Rect2(90, 390, 1100, 32), 18, Color("d9e5a3"))
            _center_label(overlay, _debuff_lines(trauma, false) + " は、もう効いていない。", Rect2(90, 430, 1100, 32), 15, Color("a8b7a8"))
            _center_label(overlay, "クリックして、つづける", Rect2(90, 710, 1100, 32), 15, Color("8d9c8d"))
        "surfaced":
            var deeper: Dictionary = state.trauma_by_id(session_result.surfaced)
            var parent: Dictionary = state.trauma_by_id(session_result.id)
            _center_label(overlay, "……奥に、もっと重いものがいた。", Rect2(90, 150, 1100, 42), 18, ROSE)
            var effect = WordEffect.new()
            effect.position = Vector2(440, 190)
            effect.size = Vector2(400, 320)
            effect.tint = Color("9a4b4b")
            overlay.add_child(effect)
            _center_label(overlay, "「%s」の下から、「%s」" % [parent.name, deeper.name], Rect2(90, 300, 1100, 66), 32, PAPER)
            _center_label(overlay, "固さ 100　/　" + _debuff_lines(deeper, false), Rect2(90, 390, 1100, 32), 18, Color("e3c9c9"))
            _wrap(overlay, deeper.story, Rect2(240, 440, 800, 110), 16, Color("c8b5b5")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            _center_label(overlay, "クリックして、つづける", Rect2(90, 710, 1100, 32), 15, Color("8d9c8d"))

func _fill_word_offer() -> void:
    var word: Dictionary = state.word_by_id(state.pending_word)
    var step: String = state.pending_step
    if step == "forget":
        _center_label(overlay, "枠がない。どの言葉を、忘れる？", Rect2(90, 96, 1100, 42), 22, MINT)
        _center_label(overlay, "忘れた言葉は EXP になり、空いた枠に「%s」を置く。" % word.word, Rect2(90, 142, 1100, 30), 15, Color("a8b7a8"))
        var kept: Array = state.kept_words()
        for i in range(kept.size()):
            var held: Dictionary = state.word_by_id(kept[i])
            var x: float = 180 + (i % 4) * 235
            var y: float = 200 + (i / 4) * 150
            _panel(overlay, Rect2(x, y, 220, 132), Color("141c20"), Color("2c393f"), 4)
            _specimen(overlay, "w:" + held.id, Rect2(x + 10, y + 6, 78, 68))
            _label(overlay, "「%s」 Lv%d" % [held.word, state.word_level(held.id)], Rect2(x + 94, y + 12, 124, 44), 13, PAPER).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            _label(overlay, _passive_text(state.level_data(held.id).passive), Rect2(x + 94, y + 54, 124, 24), 11, Color("a8b7a8"))
            var button := _button(overlay, "忘れる（%s）" % _format_exp(state.release_value(held.id)), Rect2(x + 10, y + 86, 200, 36), _forget_pending.bind(held.id))
            button.add_theme_font_size_override("font_size", 13)
        _button(overlay, "やめる（戻る）", Rect2(500, 560, 280, 44), _cancel_forget)
        return
    _center_label(overlay, "言葉を、ひとつもらった。" if step == "offer" else ("「%s」を、心に留めた。" % word.word if step == "kept" else "「%s」を、手放した。" % word.word), Rect2(90, 70, 1100, 42), 18, MINT)
    var effect = WordEffect.new()
    effect.position = Vector2(140, 110)
    effect.size = Vector2(400, 350)
    effect.tint = Color(word.color)
    overlay.add_child(effect)
    _specimen(overlay, "w:" + word.id, Rect2(205, 150, 270, 255))
    _center_label(overlay, "「%s」" % word.word, Rect2(90, 420, 500, 56), 33, PAPER)
    _center_label(overlay, word.speaker + " から、よだかへ", Rect2(90, 478, 500, 30), 16, Color("a8b7a8"))
    var delta: Array = state.gains.get(word.id, [])
    _center_label(overlay, _delta_text(delta) if not delta.is_empty() else "", Rect2(90, 512, 500, 30), 16, Color("d9e5a3"))
    _panel(overlay, Rect2(640, 130, 540, 300), Color("141c20"), Color("2c393f"), 4)
    _label(overlay, "心に留めると", Rect2(664, 146, 200, 26), 15, GOLD)
    _wrap(overlay, "持っている間：" + _passive_text(state.level_data(word.id, 1).passive), Rect2(664, 178, 494, 50), 15, PAPER)
    _wrap(overlay, "トラウマに重ねると：" + _counsel_text(state.level_data(word.id, 1).counsel), Rect2(664, 232, 494, 50), 15, PAPER)
    _wrap(overlay, "カウンセリングで EXP を使うと育つ（Lv3まで）。\n手放したり忘れたりすると EXP になる。", Rect2(664, 290, 494, 60), 13, Color("a8b7a8"))
    var free: int = state.free_slot()
    _label(overlay, "あいている枠：%s" % (("%02d" % (free + 1)) if free >= 0 else "なし"), Rect2(664, 360, 494, 26), 14, Color("a8b7a8") if free >= 0 else ROSE)
    if free < 0:
        _wrap(overlay, "トラウマで埋まっている枠には置けない。" if state.kept_words().is_empty() else "留めるなら、どれかの言葉を忘れて枠を空ける。", Rect2(664, 388, 494, 36), 13, ROSE)
    if step == "offer":
        var keep := _button(overlay, "心に留める" if free >= 0 else "どれかを忘れて、留める", Rect2(640, 452, 262, 52), _keep_pending, true)
        keep.disabled = free < 0 and state.kept_words().is_empty()
        _button(overlay, "手放す（%s）" % _format_exp(state.release_value(word.id)), Rect2(918, 452, 262, 52), _release_pending)
        _center_label(overlay, "留めるか、手放すかを選ぶ", Rect2(90, 710, 1100, 32), 15, Color("8d9c8d"))
    else:
        var note := "%02d 番目の枠に置いた。" % (state.pending_slot + 1) if step == "kept" else "%s になった。" % _format_exp(state.pending_gain)
        if step == "kept" and state.pending_gain > 0:
            note += "　忘れた言葉は %s になった。" % _format_exp(state.pending_gain)
        _center_label(overlay, note, Rect2(640, 452, 540, 40), 18, Color("d9e5a3"))
        _center_label(overlay, "クリックして、つづける", Rect2(90, 710, 1100, 32), 15, Color("8d9c8d"))

func _keep_pending() -> void:
    if overlay_kind != "word" or not interlude_ready:
        return
    if state.can_keep():
        state.keep_pending()
    else:
        state.request_forget()
    _draw_bottom()
    _fill_interlude()

func _release_pending() -> void:
    if overlay_kind != "word" or not interlude_ready:
        return
    state.release_pending()
    _draw_bottom()
    _fill_interlude()

func _forget_pending(id: String) -> void:
    if overlay_kind != "word" or not interlude_ready:
        return
    state.forget_for_pending(id)
    _draw_bottom()
    _fill_interlude()

func _cancel_forget() -> void:
    if overlay_kind != "word" or not interlude_ready:
        return
    state.cancel_forget()
    _fill_interlude()

func _interlude_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        overlay.accept_event()
        _dismiss_interlude()

func _dismiss_interlude() -> void:
    if not interlude_ready or overlay_kind not in ["scene", "word", "resolved", "surfaced"]:
        return
    if overlay_kind == "word" and state.pending_step not in ["kept", "released"]:
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
            state.acknowledge_word()
        state.save_game()
        overlay_kind = "modal"
        _close_overlay()
        auto_timer = 0
        if kind in ["resolved", "surfaced"]:
            _show_session()
            return
        if kind == "word":
            _draw_bottom()
        _check_interlude())

func _finish_line() -> void:
    if completed or is_instance_valid(overlay):
        return
    completed = true
    body.visible_characters = -1
    var added := false
    var before: Array = state.effective_stats()
    if mode == "story":
        added = state.finish_line()
    else:
        var id: String = "counsel_%d_%s_%d" % [state.counsel_session, state.counsel_step, state.talk_index]
        if state.history.is_empty() or state.history.back().id != id:
            state.history.append({"id": id, "speaker": current_dialogue.speaker, "text": current_dialogue.text})
            state.last_exp = state.exp_per_tap()
            state.gain_exp(state.last_exp)
        state.save_game()
    var notes: PackedStringArray = []
    if state.last_exp > 0:
        notes.append("+%d EXP" % state.last_exp)
    if added:
        _draw_bottom()
        _animate_stats(before)
        notes.append("言葉をもらった")
    else:
        count_label.text = _count_text()
        exp_label.text = _format_exp(state.exp)
        if state.has_change(state.last_delta):
            _animate_stats(before)
            notes.append(_delta_text(state.last_delta))
    if not notes.is_empty():
        hint.text = "   /   ".join(notes)
    if state.last_error != "":
        status.text = state.last_error
    next_button.text = "カルテを見る  →" if current_dialogue.get("karte", false) else "つづきを読む  →"
    if current_dialogue.has("choices"):
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
                note = "%s %d 必要（現在 %d）" % [choice.requires.stat, choice.requires.min, state.effective(State.STAT_NAMES.find(choice.requires.stat))]
            elif choice.has("effects"):
                note = _preview_text(choice.effects, state.preview(choice.effects))
                preview_labels.append(note)
            if note != "":
                _center_label(choice_box, note, Rect2(337 + i * width, 482, width - 12, 26), 12, MUTED)
    if added:
        _show_interlude("word")

func _advance() -> void:
    if mode not in ["story", "counseling"] or is_instance_valid(overlay):
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
        state.advance_counseling()
        _show_story()
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
        if mode in ["story", "counseling"] and Rect2(44, 76, 1192, 450).has_point(stage.get_local_mouse_position()):
            _advance()

# --- counseling -------------------------------------------------------------

func _session_title() -> String:
    return "第%d回のカウンセリング" % (state.counsel_session + 1)

func _show_counseling() -> void:
    var step: String = state.counsel_step
    if step == "session":
        _show_session()
        return
    mode = "counseling"
    auto_mode = false
    var speaker := "みなと"
    var text := ""
    var opening: bool = state.counsel_session == 0
    match step:
        "opening_doctor":
            text = OPENING_TEXT.doctor if opening else SESSION_TEXT.doctor
        "opening_yodaka":
            speaker = "よだか"
            if opening:
                text = OPENING_TEXT.yodaka
            elif state.collected.is_empty():
                text = SESSION_TEXT.yodaka_none
            else:
                text = SESSION_TEXT.yodaka % state.collected.size()
        "talk":
            var line: Dictionary = state.talk_line()
            speaker = line.speaker
            text = line.text
        "closing":
            text = OPENING_TEXT.closing if opening else SESSION_TEXT.closing
        "farewell":
            text = OPENING_TEXT.farewell if opening else (SESSION_TEXT.final_farewell if state.final_session() else SESSION_TEXT.farewell)
    _render_dialogue({"speaker": speaker, "text": text, "chapter": _session_title(),
        "chapter_index": 0, "kind": "counsel", "place": "診察室", "partner": "みなと",
        "karte": step == "closing" and not opening})
    status.text = "カウンセリング  /  よだかとみなと"
    if step == "talk":
        _center_label(content, "「%s」について" % state.trauma_by_id(state.counsel_trauma).name, Rect2(333, 501, 614, 24), 15, Color("597c51"))
    _check_interlude()

func _show_session() -> void:
    mode = "session"
    auto_mode = false
    body = null
    preview_labels.clear()
    _base()
    _panel(content, Rect2(44, 76, 1192, 516), NIGHT)
    _label(content, "COUNSELING  /  %s  /  メンタル〇〇" % _session_title(), Rect2(77, 92, 780, 30), 16, Color("8d9c8d"))
    var exp_big := _label(content, _format_exp(state.exp), Rect2(860, 86, 344, 40), 28, GOLD)
    exp_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _panel(content, Rect2(77, 134, 1127, 98), Color("141c20"), Color("2c393f"), 4)
    if state.session_lines.is_empty():
        _wrap(content, "下の欄から、トラウマか言葉を選んでください。\n一回の面談で話せるトラウマはひとつ。話すとほぐれて、EXPで向き合えるようになります。", Rect2(96, 146, 1090, 76), 15, Color("a8b7a8"))
    else:
        for i in range(mini(state.session_lines.size(), 2)):
            var line: Array = state.session_lines[i]
            _label(content, line[0], Rect2(96, 144 + i * 44, 70, 22), 13, GOLD if line[0] == "みなと" else Color("a8b7a8"))
            _wrap(content, line[1].replace("\n", "　"), Rect2(170, 142 + i * 44, 1016, 44), 14, PAPER)
    var talk_note: String = "話す：今日はもう話した" if state.talked else "話す：あと 1 つ"
    _label(content, talk_note, Rect2(77, 528, 400, 26), 14, Color("8d9c8d") if state.talked else GOLD)
    _button(content, "今日はここまで  →", Rect2(944, 518, 260, 46), _end_session, true)
    if session_selected < 0 or session_selected >= state.slots.size():
        _panel(content, Rect2(77, 244, 1127, 262), Color("141c20"), Color("2c393f"), 4)
        _center_label(content, "↓ 下の欄をクリックして、トラウマか言葉を選ぶ", Rect2(77, 244, 1127, 262), 18, Color("8d9c8d"))
        return
    var entry: String = state.slots[session_selected]
    _panel(content, Rect2(77, 244, 600, 262), Color("141c20"), Color("2c393f"), 4)
    _panel(content, Rect2(693, 244, 511, 262), Color("141c20"), Color("2c393f"), 4)
    if entry.begins_with("t:"):
        _session_trauma(state.trauma_by_id(entry.trim_prefix("t:")))
    elif entry.begins_with("w:"):
        _session_word(state.word_by_id(entry.trim_prefix("w:")))
    else:
        _center_label(content, "あいている枠。\n言葉をもらった時に、ここへ置ける。", Rect2(77, 244, 600, 262), 18, Color("8d9c8d"))
        _center_label(content, "—", Rect2(693, 244, 511, 262), 18, Color("8d9c8d"))

func _session_trauma(trauma: Dictionary) -> void:
    var id: String = trauma.id
    _specimen(content, "t:" + id, Rect2(92, 256, 110, 96))
    _label(content, trauma.name, Rect2(214, 258, 450, 30), 21, Color("e3c9c9"))
    _wrap(content, trauma.story, Rect2(214, 292, 450, 86), 13, Color("c8d5c5"))
    _label(content, "デバフ", Rect2(92, 372, 100, 22), 12, ROSE)
    _wrap(content, _debuff_lines(trauma, true), Rect2(92, 392, 570, 44), 14, PAPER)
    _label(content, "固さ", Rect2(92, 444, 60, 22), 12, ROSE)
    _bar(content, Rect2(140, 452, 400, 8), state.hardness(id), Color("9a4b4b"), Color("2b2626"))
    _label(content, "%d / 100" % state.hardness(id), Rect2(552, 442, 100, 24), 14, PAPER)
    var cost_text := "向き合うのに必要：%s" % _format_exp(state.trauma_cost(id))
    if not state.is_loosened(id):
        cost_text += "　— まだ固い。話すと、ほぐれる"
    _label(content, cost_text, Rect2(92, 472, 570, 24), 13, GOLD if state.is_loosened(id) else Color("a8b7a8"))
    if not state.is_loosened(id):
        var talk := _button(content, "この傷について、話す", Rect2(716, 268, 465, 52), _talk.bind(id), true)
        talk.disabled = not state.can_talk(id)
        var note: String = "話すと、必要な EXP が大きく下がる。" if not state.talked else "今日はもう話した。次の面談で話せる。"
        _wrap(content, note, Rect2(716, 328, 465, 44), 13, Color("a8b7a8"))
        var face := _button(content, "向き合う", Rect2(716, 390, 465, 48), func(): pass)
        face.disabled = true
        _wrap(content, "ほぐれていないトラウマには、まだ向き合えない。", Rect2(716, 444, 465, 40), 13, Color("8d9c8d"))
        return
    _label(content, "重ねる言葉（最大 %d つ）" % int(state.data.rules.max_cards), Rect2(716, 254, 460, 24), 13, GOLD)
    var kept: Array = state.kept_words()
    if kept.is_empty():
        _wrap(content, "持っている言葉がない。言葉なしでも向き合える。", Rect2(716, 280, 465, 40), 13, Color("8d9c8d"))
    for i in range(mini(kept.size(), 6)):
        var word: Dictionary = state.word_by_id(kept[i])
        var chosen: bool = session_cards.has(word.id)
        var button := _button(content, "%s「%s」 %s" % ["■" if chosen else "□", word.word, _counsel_text(state.level_data(word.id).counsel)], Rect2(716 + (i % 2) * 236, 280 + (i / 2) * 42, 228, 36), _toggle_card.bind(word.id), chosen)
        button.add_theme_font_size_override("font_size", 12)
    var plan: Dictionary = state.confront_preview(id, session_cards)
    var preview := "必要 %s　/　固さ %d → %d" % [_format_exp(plan.cost), plan.before, plan.after]
    if plan.calm:
        preview += "　/　奥のものを抑えたまま"
    preview_labels.append(preview)
    _label(content, preview, Rect2(716, 410, 465, 24), 14, PAPER)
    var face := _button(content, "向き合う（%s）" % _format_exp(plan.cost), Rect2(716, 436, 465, 48), _confront.bind(id), true)
    face.disabled = not plan.affordable
    if not plan.affordable:
        _label(content, "EXP が足りない。会話を読むか、言葉を手放すと溜まる。", Rect2(716, 486, 465, 18), 11, ROSE)

func _session_word(word: Dictionary) -> void:
    var id: String = word.id
    var level: int = state.word_level(id)
    var info: Dictionary = state.level_data(id)
    _specimen(content, "w:" + id, Rect2(92, 256, 110, 96))
    _label(content, "「%s」　Lv%d / %d" % [word.word, level, word.levels.size()], Rect2(214, 258, 450, 30), 21, PAPER)
    _label(content, word.speaker + " からもらった言葉", Rect2(214, 290, 450, 22), 13, Color("a8b7a8"))
    _wrap(content, info.insight, Rect2(214, 314, 450, 64), 13, Color("c8d5c5"))
    _label(content, "持っている間", Rect2(92, 372, 120, 22), 12, GOLD)
    _wrap(content, _passive_text(info.passive), Rect2(92, 392, 570, 24), 14, PAPER)
    _label(content, "トラウマに重ねると", Rect2(92, 420, 160, 22), 12, GOLD)
    _wrap(content, _counsel_text(info.counsel), Rect2(92, 440, 570, 24), 14, PAPER)
    _label(content, "忘れると %s になる" % _format_exp(state.release_value(id)), Rect2(92, 472, 570, 22), 12, Color("a8b7a8"))
    var cost: int = state.grow_cost(id)
    if cost >= 0:
        var next: Dictionary = state.level_data(id, level + 1)
        _label(content, "育てる → Lv%d" % (level + 1), Rect2(716, 254, 460, 24), 13, GOLD)
        _wrap(content, "持っている間：" + _passive_text(next.passive) + "\n重ねると：" + _counsel_text(next.counsel), Rect2(716, 280, 465, 70), 13, PAPER)
        _wrap(content, "掘り下げると、言葉の意味が変わって見える。", Rect2(716, 354, 465, 24), 12, Color("8d9c8d"))
        var grow := _button(content, "育てる（%s）" % _format_exp(cost), Rect2(716, 386, 465, 50), _grow.bind(id), true)
        grow.disabled = not state.can_grow(id)
        if not state.can_grow(id):
            _label(content, "EXP が足りない。", Rect2(716, 438, 465, 20), 11, ROSE)
    else:
        _label(content, "育ちきった言葉", Rect2(716, 254, 460, 24), 13, GOLD)
        _wrap(content, "この言葉は、これ以上は育たない。\nよだかの中で、もう自分の言葉になっている。", Rect2(716, 280, 465, 60), 13, PAPER)
    var forget := _button(content, "忘れる（%s）" % _format_exp(state.release_value(id)), Rect2(716, 462, 465, 36), _forget_in_session.bind(id))
    forget.add_theme_font_size_override("font_size", 13)

func _toggle_card(id: String) -> void:
    if mode != "session" or is_instance_valid(overlay):
        return
    if session_cards.has(id):
        session_cards.erase(id)
    elif session_cards.size() < int(state.data.rules.max_cards):
        session_cards.append(id)
    _show_session()

func _talk(id: String) -> void:
    if mode != "session" or is_instance_valid(overlay):
        return
    if state.start_talk(id):
        _show_story()

func _confront(id: String) -> void:
    if mode != "session" or is_instance_valid(overlay):
        return
    var before: Array = state.effective_stats()
    var result: Dictionary = state.confront(id, session_cards)
    if result.is_empty():
        return
    session_result = result
    session_cards.clear()
    if result.resolved or result.surfaced != "":
        session_selected = state.slots.find("t:" + result.surfaced) if result.surfaced != "" else -1
        _show_session()
        _show_interlude("resolved" if result.resolved else "surfaced")
        return
    _show_session()
    _animate_stats(before)

func _grow(id: String) -> void:
    if mode != "session" or is_instance_valid(overlay):
        return
    var before: Array = state.effective_stats()
    if state.grow(id).is_empty():
        return
    _show_session()
    _animate_stats(before)

func _forget_in_session(id: String) -> void:
    if mode != "session" or is_instance_valid(overlay):
        return
    _modal("「%s」を忘れる" % state.word_by_id(id).word, "この言葉は %s になり、枠が空きます。\n忘れた言葉は、もう戻ってきません。" % _format_exp(state.release_value(id)), "忘れる", func():
        _close_overlay()
        var before: Array = state.effective_stats()
        if state.forget_in_session(id) > 0:
            session_selected = -1
            session_cards.clear()
            _show_session()
            _animate_stats(before))

func _end_session() -> void:
    if mode != "session" or is_instance_valid(overlay):
        return
    if state.end_session():
        session_selected = -1
        session_cards.clear()
        _show_story()

# --- text helpers -----------------------------------------------------------

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

func _debuff_lines(trauma: Dictionary, with_current: bool) -> String:
    var parts: PackedStringArray = []
    var scaled: Array = state.scaled_debuffs(trauma.id)
    for i in range(trauma.debuffs.size()):
        var debuff: Dictionary = trauma.debuffs[i]
        var now: Dictionary = scaled[i] if i < scaled.size() else debuff
        var text := ""
        match debuff.kind:
            "offset":
                text = "%s 常時 %+d" % [debuff.stat, int(debuff.value)]
                if with_current:
                    text += "（いま %+d）" % int(now.value)
            "cap":
                text = "%s の上限 %d" % [debuff.stat, int(debuff.value)]
                if with_current:
                    text += "（いま %d）" % int(now.value)
            "gain":
                text = "%s の増加 ×%.1f" % [debuff.stat, float(debuff.value)]
                if with_current:
                    text += "（いま ×%.2f）" % float(now.value)
            "exp":
                text = "EXP の溜まり方 ×%.1f" % float(debuff.value)
                if with_current:
                    text += "（いま ×%.2f）" % float(now.value)
            "recovery":
                text = "ストレスの回復 ×%.1f" % float(debuff.value)
                if with_current:
                    text += "（いま ×%.2f）" % float(now.value)
        parts.append(text)
    return "　/　".join(parts)

func _passive_text(list: Array) -> String:
    var parts: PackedStringArray = []
    for passive in list:
        match passive.kind:
            "stat":
                parts.append("%s %+d" % [passive.stat, int(passive.value)])
            "gain":
                parts.append("%s の増加 ×%.1f" % [passive.stat, float(passive.value)])
            "exp":
                parts.append("1タップの EXP ×%d" % int(passive.value))
            "release":
                parts.append("忘れた時の EXP ×%d" % int(passive.value))
    return "　/　".join(parts) if not parts.is_empty() else "—"

func _counsel_text(list: Array) -> String:
    var parts: PackedStringArray = []
    for effect in list:
        match effect.kind:
            "cost":
                var value: float = float(effect.value)
                if is_equal_approx(value, 0.5):
                    parts.append("必要 EXP 半減")
                elif value <= 0.1:
                    parts.append("必要 EXP %d分の1" % roundi(1.0 / value))
                else:
                    parts.append("必要 EXP ×%.2f" % value)
            "soften":
                parts.append("ほぐし +%d" % int(effect.value))
            "calm":
                parts.append("奥のものを抑える")
    return "　/　".join(parts) if not parts.is_empty() else "—"

func _stress_note() -> String:
    var stress: int = state.effective(0)
    if stress < 35:
        return "落ち着いている"
    if stress < 60:
        return "少し疲れている"
    if stress < State.STRESS_LIMIT:
        return "かなり疲れている"
    return "限界が近い。出かける前に休もう"

# --- overlays ---------------------------------------------------------------

func _show_karte(on_close: Callable) -> void:
    var card := _new_overlay("メンタル〇〇（仮）  /  いまのカルテ")
    _label(card, "法月 よだか　　状態：" + _stress_note(), Rect2(36, 76, 600, 32), 18, MUTED)
    _label(card, _format_exp(state.exp), Rect2(600, 72, 212, 36), 24, Color("a2843a")).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var effective: Array = state.effective_stats()
    for i in range(State.STAT_NAMES.size()):
        var y: int = 122 + i * 52
        _label(card, State.STAT_NAMES[i], Rect2(40, y, 140, 30), 20)
        _bar(card, Rect2(170, y + 9, 420, 14), effective[i], Color("c98f7c") if i == 0 else Color("7fae70"), Color("e4e6df"))
        _label(card, str(effective[i]), Rect2(606, y, 60, 30), 20)
        var note := "素の値 %d" % int(state.stats[i])
        var shift: int = state.stat_offset(i)
        if shift != 0:
            note += "　%+d" % shift
        if state.stat_cap(i) < 100:
            note += "　上限 %d" % state.stat_cap(i)
        _label(card, note, Rect2(666, y + 4, 150, 24), 12, MUTED)
    var traumas: PackedStringArray = []
    for id in state.active_traumas():
        traumas.append("%s（固さ %d%s）" % [state.trauma_by_id(id).name, state.hardness(id), "・ほぐれた" if state.is_loosened(id) else ""])
    var words: PackedStringArray = []
    for id in state.kept_words():
        words.append("「%s」Lv%d" % [state.word_by_id(id).word, state.word_level(id)])
    _wrap(card, "トラウマ：" + ("、".join(traumas) if not traumas.is_empty() else "なし"), Rect2(40, 334, 770, 60), 13, INK)
    _wrap(card, "言葉：" + ("、".join(words) if not words.is_empty() else "まだない"), Rect2(40, 396, 770, 40), 13, INK)
    _wrap(card, "表示は、素の値にトラウマと言葉の効果を足したもの。ストレス%d以上で寄り道に出かけられません。会話を読むと EXP が溜まり、カウンセリングで使います。" % State.STRESS_LIMIT, Rect2(40, 440, 770, 50), 13, MUTED)
    _label(card, "ほどけたトラウマ %d　·　手放した言葉 %d　·　これまでに得た %s" % [state.resolved.size(), state.released.size(), _format_exp(state.exp_total)], Rect2(40, 490, 700, 26), 14)
    if on_close.is_valid():
        for child in card.get_children():
            if child is Button:
                child.pressed.connect(on_close)

func _show_result() -> void:
    mode = "result"
    body = null
    _base()
    _panel(content, Rect2(44, 76, 1192, 516), PAPER)
    _label(content, "EPILOGUE  /  %s" % _session_title(), Rect2(85, 109, 800, 32), 16, MUTED)
    _label(content, "答えは、まだ途中でいい。", Rect2(80, 164, 1100, 72), 44)
    _label(content, "みなと", Rect2(87, 260, 140, 30), 18, MUTED)
    _label(content, "ほどけたものも、まだ固いままのものも、法月さんのものです。\n受け入れることも、受け入れないことも、今は決めないことも。\nまた言葉が増えたら、一緒に整理しましょう。", Rect2(86, 311, 950, 122), 24)
    var effective: Array = state.effective_stats()
    _label(content, "ほどけたトラウマ %d / %d　·　留めている言葉 %d　·　EXP 合計 %s　　ストレス %d　/　勇気 %d　/　自認 %d　/　キラキラ %d" % [state.resolved.size(), state.resolved.size() + state.active_traumas().size(), state.kept_words().size(), _format_exp(state.exp_total), effective[0], effective[1], effective[2], effective[3]], Rect2(86, 450, 1100, 38), 16, MUTED)
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
    if overlay_kind in ["scene", "word", "resolved", "surfaced"]:
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
    var card := _new_overlay("「%s」　Lv%d" % [word.word, state.word_level(word.id)])
    _label(card, word.speaker + " からもらった言葉", Rect2(36, 82, 740, 32), 18, MUTED)
    _panel(card, Rect2(37, 147, 219, 273), DARK)
    _specimen(card, "w:" + word.id, Rect2(47, 170, 198, 228))
    _wrap(card, word.quote, Rect2(291, 150, 520, 120), 20)
    var info: Dictionary = state.level_data(word.id)
    _wrap(card, info.insight, Rect2(291, 272, 520, 70), 15, Color("597c51"))
    _label(card, "持っている間：" + _passive_text(info.passive), Rect2(291, 350, 520, 26), 15, MUTED)
    _label(card, "トラウマに重ねると：" + _counsel_text(info.counsel), Rect2(291, 378, 520, 26), 15, MUTED)
    var gained: Array = state.gains.get(word.id, [])
    _label(card, "もらった時：" + (_delta_text(gained) if not gained.is_empty() else "—"), Rect2(291, 406, 520, 26), 15, MUTED)
    _label(card, "カウンセリングで EXP を使うと育つ。忘れると %s になる。" % _format_exp(state.release_value(word.id)), Rect2(36, 449, 770, 41), 15, MUTED)

func _show_trauma(trauma: Dictionary) -> void:
    var card := _new_overlay("「%s」" % trauma.name)
    _label(card, "トラウマ　/　固さ %d　/　%s" % [state.hardness(trauma.id), "ほぐれている" if state.is_loosened(trauma.id) else "まだ固い"], Rect2(36, 82, 740, 32), 18, MUTED)
    _panel(card, Rect2(37, 147, 219, 273), DARK)
    _specimen(card, "t:" + trauma.id, Rect2(47, 170, 198, 228))
    _wrap(card, trauma.story, Rect2(291, 150, 520, 150), 20)
    _wrap(card, "デバフ：" + _debuff_lines(trauma, true), Rect2(291, 310, 520, 60), 15, Color("9a4b4b"))
    _label(card, "向き合うのに必要：" + _format_exp(state.trauma_cost(trauma.id)), Rect2(291, 378, 520, 26), 15, MUTED)
    _wrap(card, "カウンセリングで話すとほぐれて、必要な EXP が下がる。言葉を重ねて向き合うと固さが減り、デバフが弱まる。固さが 0 になると枠が空く。", Rect2(36, 440, 770, 60), 14, MUTED)

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
    for id in state.resolved:
        text += "[color=#6b8563]ほどけた：「%s」[/color]\n%s\n\n" % [state.trauma_by_id(id).name, state.trauma_by_id(id).soften.resolved[1]]
    for id in state.surfaced:
        text += "[color=#9a4b4b]奥から出てきた：「%s」[/color]\n\n" % state.trauma_by_id(id).name
    for id in state.collected:
        var word: Dictionary = state.word_by_id(id)
        var line: String = "手放した" if state.released.has(id) else ("Lv%d　%s" % [state.word_level(id), state.level_data(id).insight] if state.is_kept(id) else "")
        text += "[color=#6b8563]「%s」 / %s[/color]\n%s\n\n" % [word.word, word.speaker, line]
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
