extends Control
## Placeholder HUD: health bar and stamina pips for the controlled character.

const BAR_SIZE := Vector2(80, 5)
const PIP_SIZE := Vector2(8, 4)
const MARGIN := 8.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var hero := get_tree().get_first_node_in_group("player") as Hero
	if hero == null:
		return
	var origin := Vector2(MARGIN, size.y - MARGIN - BAR_SIZE.y - PIP_SIZE.y - 3)
	draw_rect(Rect2(origin, BAR_SIZE), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * maxf(hero.health, 0.0) / hero.max_health, BAR_SIZE.y)), Color(0.75, 0.12, 0.12))
	var pip_origin := origin + Vector2(0, BAR_SIZE.y + 3)
	for i in hero.max_stamina:
		var color := Color(0.55, 0.75, 1.0) if i < hero.stamina else Color(0.15, 0.18, 0.25)
		draw_rect(Rect2(pip_origin + Vector2(i * (PIP_SIZE.x + 2), 0), PIP_SIZE), color)
