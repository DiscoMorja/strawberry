extends Node
## Game-feel helpers (autoload): hit-stop, screen shake, floating text.
## Owns Engine.time_scale so hit-stop and debug slow-motion compose instead of fighting.

const HIT_STOP_SCALE := 0.02
const POPUP_RISE := 14.0
const POPUP_DURATION := 0.55

## Debug/gameplay slow-motion multiplier. Hit-stop is applied on top of this.
var base_time_scale: float = 1.0:
	set(value):
		base_time_scale = value
		_apply_time_scale()

var _hit_stop_until_msec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if _hit_stop_until_msec > 0 and Time.get_ticks_msec() >= _hit_stop_until_msec:
		_hit_stop_until_msec = 0
		_apply_time_scale()


## Freezes the game for `duration` real-time seconds. Overlapping calls extend, never stack.
func hit_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	_hit_stop_until_msec = maxi(_hit_stop_until_msec, Time.get_ticks_msec() + int(duration * 1000.0))
	_apply_time_scale()


func shake(trauma: float) -> void:
	if trauma <= 0.0:
		return
	for camera in get_tree().get_nodes_in_group("game_camera"):
		camera.add_trauma(trauma)


func popup_text(world_position: Vector2, text: String, color: Color = Color.WHITE, font_size: int = 8) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.z_as_relative = false
	label.z_index = ZLayers.POPUP
	label.size = Vector2(80, font_size * 2)
	label.position = world_position - label.size * 0.5 + Vector2(randf_range(-3, 3), 0)
	scene.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - POPUP_RISE, POPUP_DURATION) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, POPUP_DURATION * 0.5).set_delay(POPUP_DURATION * 0.5)
	tween.tween_callback(label.queue_free)


func _apply_time_scale() -> void:
	Engine.time_scale = base_time_scale * (HIT_STOP_SCALE if _hit_stop_until_msec > 0 else 1.0)
