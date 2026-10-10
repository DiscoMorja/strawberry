extends Combatant
## Immortal, stationary target for testing damage numbers, cleave and stagger.
## Heals to full after a short pause without hits.

const HEAL_DELAY := 1.5

var _since_hit := 0.0


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	damaged.connect(func(_c: Combatant, _h: HitInfo, _a: float) -> void: _since_hit = 0.0)


func _physics_process(delta: float) -> void:
	update_combat_state(delta)
	_since_hit += delta
	if _since_hit >= HEAL_DELAY:
		health = max_health
	queue_redraw()


func die(_hit: HitInfo) -> void:
	health = max_health


func _draw() -> void:
	draw_body()
	draw_line(Vector2(-body_radius, 0), Vector2(body_radius, 0), Color(0.3, 0.2, 0.12), 2.0)
