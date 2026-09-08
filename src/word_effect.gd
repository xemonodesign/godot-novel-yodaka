extends Control

var tint := Color("c7e5ba")
var time: float = 0.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
    time += delta
    queue_redraw()

func _draw() -> void:
    var center := size / 2.0
    for ring in range(3):
        var progress := fmod(time * 0.24 + ring / 3.0, 1.0)
        draw_arc(center, 35 + progress * 152, 0, TAU, 80,
            Color(tint, (1.0 - progress) * 0.2), 1.0, true)
    for i in range(28):
        var angle := i * 2.39996 + time * 0.06
        var radius := 55 + fmod(i * 19.0 + time * 12, 130)
        var point := center + Vector2(cos(angle), sin(angle)) * radius
        var alpha := (sin(time * 1.5 + i) + 1.0) * 0.25
        draw_circle(point, 1.0 + (i % 3) * 0.5, Color(tint, alpha))
