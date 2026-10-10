extends Control
## Screen-edge arrows pointing at off-screen priority targets (specials), in each special's color.
## Fresh spawns pulse larger for a moment so the player registers the new threat.

const EDGE_MARGIN := 10.0
const ARROW_SIZE := 5.0
const FRESH_TIME := 1.5

var _first_seen: Dictionary = {}


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var canvas := get_viewport().get_canvas_transform()
	var screen := Rect2(Vector2.ZERO, size)
	var inner := screen.grow(-EDGE_MARGIN)
	var center := screen.get_center()
	var now := Time.get_ticks_msec() / 1000.0
	var alive: Dictionary = {}
	for node in get_tree().get_nodes_in_group("priority"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead:
			continue
		var id := enemy.get_instance_id()
		alive[id] = true
		if not _first_seen.has(id):
			_first_seen[id] = now
		var screen_pos := canvas * enemy.global_position
		if screen.has_point(screen_pos):
			continue
		var direction := (screen_pos - center).normalized()
		var edge := _clamp_to_rect(center, direction, inner)
		var fresh := clampf(1.0 - (now - _first_seen[id]) / FRESH_TIME, 0.0, 1.0)
		var pulse := 1.0 + fresh * (0.6 + 0.4 * sin(now * 20.0))
		var s := ARROW_SIZE * pulse
		var side := direction.orthogonal()
		draw_colored_polygon(PackedVector2Array([edge + direction * s, edge - direction * s * 0.6 + side * s * 0.8,
				edge - direction * s * 0.6 - side * s * 0.8]), enemy.priority_color)
		draw_circle(edge - direction * s * 1.6, 1.5 * pulse, enemy.priority_color)
	for id in _first_seen.keys():
		if not alive.has(id):
			_first_seen.erase(id)


## Point where a ray from `origin` along `direction` leaves `rect`.
func _clamp_to_rect(origin: Vector2, direction: Vector2, rect: Rect2) -> Vector2:
	var t := INF
	if direction.x > 0.0:
		t = minf(t, (rect.end.x - origin.x) / direction.x)
	elif direction.x < 0.0:
		t = minf(t, (rect.position.x - origin.x) / direction.x)
	if direction.y > 0.0:
		t = minf(t, (rect.end.y - origin.y) / direction.y)
	elif direction.y < 0.0:
		t = minf(t, (rect.position.y - origin.y) / direction.y)
	return origin + direction * t
