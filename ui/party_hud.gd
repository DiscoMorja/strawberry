extends Control
## Placeholder party HUD: one row per member (bottom-left), the current order and key hints.

const ROW_HEIGHT := 16.0
const BAR_WIDTH := 70.0
const MARGIN := 8.0
const FONT_SIZE := 8

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var manager := get_tree().get_first_node_in_group("party_manager") as PartyManager
	if manager == null:
		return
	var y := size.y - MARGIN - 10.0
	_text(Vector2(MARGIN, y + 8.0),
			"ORDER %s   1 follow  2 hold  3 focus  4 regroup   Tab swap   F revive   Ctrl tactical" % PartyManager.Order.keys()[manager.order],
			Color(0.85, 0.85, 0.7))
	y -= 6.0
	for i in range(manager.members.size() - 1, -1, -1):
		var member := manager.members[i]
		if not is_instance_valid(member):
			continue
		y -= ROW_HEIGHT
		_draw_row(member, Vector2(MARGIN, y))


func _draw_row(member: PartyMember, origin: Vector2) -> void:
	var name_color := member.ring_color if member.is_controlled else member.ring_color.darkened(0.35)
	var prefix := "> " if member.is_controlled else "  "
	_text(origin + Vector2(0, 7), prefix + member.display_name, name_color)
	var bar := origin + Vector2(56, 1)
	draw_rect(Rect2(bar, Vector2(BAR_WIDTH, 4)), Color(0, 0, 0, 0.7))
	var fraction := clampf(member.health / member.max_health, 0.0, 1.0)
	draw_rect(Rect2(bar, Vector2(BAR_WIDTH * fraction, 4)), Color(0.75, 0.12, 0.12))
	for p in member.max_stamina:
		var color := Color(0.55, 0.75, 1.0) if p < member.stamina else Color(0.15, 0.18, 0.25)
		draw_rect(Rect2(bar + Vector2(p * 7.0, 6), Vector2(5, 2)), color)
	var status := ""
	match member.state:
		PartyMember.State.DOWNED:
			status = "DOWN %.0fs" % member.bleed_left
		PartyMember.State.DEAD:
			status = "DEAD"
		PartyMember.State.GRABBED:
			status = "GRABBED"
		PartyMember.State.REVIVING:
			status = "reviving"
	if status != "":
		_text(bar + Vector2(BAR_WIDTH + 4, 6), status, Color(1.0, 0.45, 0.35))
	else:
		_text(bar + Vector2(BAR_WIDTH + 4, 6), "kills %d" % member.kills, Color(0.6, 0.6, 0.6))


func _text(at: Vector2, text: String, color: Color) -> void:
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3, Color.BLACK)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
