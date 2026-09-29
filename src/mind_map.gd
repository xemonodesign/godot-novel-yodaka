extends Control

# A mental map: darkness that the collected words light up.
# Each lit node glows wider the more crystals its word carries; forgotten words
# leave a faint ember; words never met stay as dim specks in the dark.
var lit: Array = []  # {pos, color, crystals}
var embers: Array = []  # {pos, color}
var unknown: int = 0
var time: float = 0.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = true

func node_position(index: int, count: int) -> Vector2:
    # Words orbit Yodaka's core in two loose rings.
    var center := size / 2.0
    var angle := -PI / 2 + index * TAU / maxf(count, 1) + (0.35 if index % 2 == 1 else 0.0)
    var distance := 118.0 + (index % 2) * 34.0
    return center + Vector2(cos(angle), sin(angle)) * distance

func _process(delta: float) -> void:
    time += delta
    queue_redraw()

func _draw() -> void:
    var center := size / 2.0
    draw_rect(Rect2(Vector2.ZERO, size), Color("05080a"))
    # Specks for words still out in the dark.
    for i in range(unknown):
        var angle := i * 2.39996 + 0.7
        var radius := 60.0 + fmod(i * 47.0, 150.0)
        var point := center + Vector2(cos(angle), sin(angle)) * radius
        draw_circle(point, 2.0, Color(0.35, 0.4, 0.4, 0.28 + 0.12 * sin(time * 0.8 + i)))
    # Embers of forgotten words.
    for ember in embers:
        draw_circle(ember.pos, 4.0, Color(ember.color, 0.18))
        draw_arc(ember.pos, 9.0, 0, TAU, 24, Color(ember.color, 0.08), 1.0, true)
    # Yodaka's core: brighter with every lit word.
    var core := 0.05 + 0.04 * lit.size()
    for ring in range(5):
        var t := ring / 5.0
        draw_circle(center, 14.0 + (1.0 - t) * 26.0 + sin(time * 1.1) * 2.0, Color(0.85, 0.9, 0.75, core * (1.0 - t) * 0.6))
    draw_circle(center, 6.0, Color(0.95, 0.96, 0.85, 0.7))
    # Light spreading from each word, and the thread that ties it to the core.
    for node in lit:
        var radius: float = 30.0 + float(node.crystals) * 9.0
        var pulse := 1.0 + 0.05 * sin(time * 1.4 + node.pos.x * 0.03)
        draw_line(center, node.pos, Color(node.color, 0.12 + 0.05 * float(node.crystals)), 1.5, true)
        for ring in range(7):
            var t := ring / 7.0
            var alpha := (0.16 - 0.02 * ring) * (1.0 - t) + 0.02
            draw_circle(node.pos, radius * pulse * (1.0 - t * 0.85), Color(node.color, alpha))
        for i in range(mini(node.crystals, 12)):
            var angle := i * 0.52 + time * 0.25
            var point: Vector2 = node.pos + Vector2(cos(angle), sin(angle)) * (radius * 0.55)
            draw_circle(point, 1.6, Color(node.color.lightened(0.5), 0.6))
