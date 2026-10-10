class_name CombatDraw
## Placeholder drawing helpers for attack shapes (telegraphs, swing trails, block arcs).

const SEGMENTS := 16


## Draws a filled circular sector in `canvas`'s local space.
## `from_t`/`to_t` (0..1) draw only part of the arc, for in-progress sweeps.
static func sector(canvas: CanvasItem, facing: Vector2, radius: float, arc_degrees: float,
		color: Color, from_t: float = 0.0, to_t: float = 1.0, inner_radius: float = 0.0) -> void:
	var half := deg_to_rad(arc_degrees) * 0.5
	var start := facing.angle() - half + half * 2.0 * from_t
	var end := facing.angle() - half + half * 2.0 * to_t
	if end <= start:
		return
	var points := PackedVector2Array()
	for i in SEGMENTS + 1:
		var a := lerpf(start, end, float(i) / SEGMENTS)
		points.append(Vector2.from_angle(a) * radius)
	if inner_radius > 0.0:
		for i in range(SEGMENTS, -1, -1):
			var a := lerpf(start, end, float(i) / SEGMENTS)
			points.append(Vector2.from_angle(a) * inner_radius)
	else:
		points.append(Vector2.ZERO)
	canvas.draw_colored_polygon(points, color)


## Sweep-aware partial sector for an attack at `progress` through its active window.
static func swing(canvas: CanvasItem, facing: Vector2, attack: AttackData, progress: float, color: Color) -> void:
	match attack.sweep_direction:
		0:
			sector(canvas, facing, attack.reach, attack.arc_degrees, color)
		1:
			sector(canvas, facing, attack.reach, attack.arc_degrees, color, maxf(0.0, progress - 0.35), progress)
		-1:
			sector(canvas, facing, attack.reach, attack.arc_degrees, color, 1.0 - progress, minf(1.0, 1.35 - progress))
