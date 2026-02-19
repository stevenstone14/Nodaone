extends Control

## Draws a small circle crosshair at the center of the screen.

@export var color: Color = Color.WHITE
@export var radius: float = 3.0
@export var thickness: float = 1.5


func _draw() -> void:
	var center = get_viewport_rect().size / 2.0
	draw_arc(center, radius, 0, TAU, 32, color, thickness)


func _process(_delta: float) -> void:
	queue_redraw()
