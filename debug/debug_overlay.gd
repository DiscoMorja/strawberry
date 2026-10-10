extends CanvasLayer
## Global debug HUD and dev hotkeys (autoload).
## ` toggle HUD · F2 cycle base resolution · F3 toggle stretch mode · [ ] \ time scale · F4 spawn dummy
## (F5-F8 are avoided: the Godot editor uses them for run/pause/stop.)

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(640, 360),
	Vector2i(960, 540),
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
]
const TIME_SCALES: Array[float] = [0.1, 0.25, 0.5, 1.0, 1.5, 2.0]
const DEFAULT_TIME_SCALE_INDEX := 3

var _label: Label
var _resolution_index := 0
var _time_scale_index := DEFAULT_TIME_SCALE_INDEX


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.position = Vector2(4, 4)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	var current := get_window().content_scale_size
	_resolution_index = maxi(0, RESOLUTIONS.find(current))
	_update_font_size()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		_label.visible = not _label.visible
	elif event.is_action_pressed("debug_resolution"):
		_resolution_index = (_resolution_index + 1) % RESOLUTIONS.size()
		get_window().content_scale_size = RESOLUTIONS[_resolution_index]
		_update_font_size()
	elif event.is_action_pressed("debug_stretch"):
		var window := get_window()
		if window.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS:
			window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		else:
			window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	elif event.is_action_pressed("debug_time_slower"):
		_set_time_scale_index(_time_scale_index - 1)
	elif event.is_action_pressed("debug_time_faster"):
		_set_time_scale_index(_time_scale_index + 1)
	elif event.is_action_pressed("debug_time_reset"):
		_set_time_scale_index(DEFAULT_TIME_SCALE_INDEX)
	elif event.is_action_pressed("debug_zoom_in") or event.is_action_pressed("debug_zoom_out"):
		var step := 0.25 if event.is_action_pressed("debug_zoom_in") else -0.25
		for camera in get_tree().get_nodes_in_group("game_camera"):
			camera.set_zoom_level(camera.zoom_level + step)


func _process(_delta: float) -> void:
	if not _label.visible:
		return
	var window := get_window()
	var stretch := "canvas_items" if window.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS else "viewport"
	_label.text = "\n".join([
		"FPS %d   frame %.2f ms   physics %.2f ms" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		],
		"draw calls %d   nodes %d   enemies %d" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			get_tree().get_node_count_in_group("enemies"),
		],
		"base %s   window %s   stretch %s" % [window.content_scale_size, window.size, stretch],
		"time scale x%.2f   zoom x%.2f   %s" % [Juice.base_time_scale, _camera_zoom(), _director_status()],
		"` hud  F2 res  F3 stretch  [ ] \\ time  - = zoom  F4 dummy  Z trash  X elite  C clear  N archer  M grabber  V director  B +50",
	])


func _director_status() -> String:
	var director := get_tree().get_first_node_in_group("director") as Director
	if director == null or not director.enabled:
		return "director off"
	return "director %s %.0fs" % [director.phase_name(), director.phase_time]


func _camera_zoom() -> float:
	var camera := get_tree().get_first_node_in_group("game_camera") as Camera2D
	return camera.zoom.x if camera else 1.0


func _set_time_scale_index(index: int) -> void:
	_time_scale_index = clampi(index, 0, TIME_SCALES.size() - 1)
	Juice.base_time_scale = TIME_SCALES[_time_scale_index]


## Keeps the HUD roughly the same on-screen size across base resolutions.
func _update_font_size() -> void:
	_label.add_theme_font_size_override("font_size", maxi(8, RESOLUTIONS[_resolution_index].y / 40))
