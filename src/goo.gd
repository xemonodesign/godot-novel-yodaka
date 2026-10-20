extends Control

# A trauma still unopened: a dark, slowly heaving mass of mottled red-purple.
var seed_value: int = 0
var time: float = 0.0
var bright: float = 1.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = true

func _process(delta: float) -> void:
    time += delta
    queue_redraw()

func _draw() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.11, 0.05, 0.09))
    for i in range(26):
        var anchor := Vector2(rng.randf() * size.x, rng.randf() * size.y)
        var radius: float = (0.12 + rng.randf() * 0.32) * minf(size.x, size.y)
        var phase: float = rng.randf() * TAU
        var drift := Vector2(sin(time * 0.35 + phase), cos(time * 0.27 + phase * 1.7)) * radius * 0.25
        var hue_shift: float = rng.randf()
        var color := Color(0.2 + 0.18 * hue_shift, 0.04 + 0.04 * (1.0 - hue_shift), 0.16 + 0.14 * hue_shift, 0.16 + 0.16 * rng.randf())
        color = color * bright
        color.a = minf(color.a, 0.4)
        draw_circle(anchor + drift, radius * (0.9 + 0.1 * sin(time * 0.6 + phase)), color)
    # Dark veins that keep the mass from reading as a flat tint.
    for i in range(9):
        var start := Vector2(rng.randf() * size.x, rng.randf() * size.y)
        var end := start + Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * size.x * 0.8
        draw_line(start, end, Color(0.05, 0.02, 0.05, 0.35), 1.5 + rng.randf() * 2.0, true)
    # A faint sheen so it looks wet rather than painted.
    var sheen := Vector2(size.x * (0.3 + 0.1 * sin(time * 0.4)), size.y * 0.3)
    draw_circle(sheen, size.x * 0.12, Color(0.55, 0.3, 0.45, 0.08))
