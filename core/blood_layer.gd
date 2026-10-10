class_name BloodLayer
extends Node2D
## Persistent floor blood for one scene. Everything is one canvas item and only
## redraws when a splat is added, so thousands of splats stay cheap.

const MAX_SPLATS := 4000

var _positions := PackedVector2Array()
var _radii := PackedFloat32Array()
var _colors := PackedColorArray()


func add_splat(at: Vector2, radius: float, color: Color) -> void:
	if _positions.size() >= MAX_SPLATS:
		_positions.remove_at(0)
		_radii.remove_at(0)
		_colors.remove_at(0)
	_positions.append(at)
	_radii.append(radius)
	_colors.append(color)
	queue_redraw()


func _draw() -> void:
	for i in _positions.size():
		var r := _radii[i]
		draw_circle(_positions[i], r, _colors[i])
		if r > 2.0:
			# Irregular edge so larger pools don't read as perfect circles.
			draw_circle(_positions[i] + Vector2(r * 0.5, r * 0.3), r * 0.6, _colors[i])
			draw_circle(_positions[i] - Vector2(r * 0.4, r * 0.5), r * 0.5, _colors[i])
