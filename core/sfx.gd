extends Node
## Placeholder procedural sound cues (autoload). Real audio replaces these later; the point is
## that every impact and every threat has a distinct, readable sound from day one.

enum Cue { HIT, HIT_HEAVY, BLOCK, HORDE, ELITE, SPECIAL_ARCHER, SPECIAL_GRABBER, SHIELD }

const MIX_RATE := 22050
const POOL_SIZE := 16
const BASE_VOLUME_DB := -8.0

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_streams[Cue.HIT] = _make(0.08, func(t: float) -> float:
		return _noise() * exp(-t * 40.0) * 0.5 + sin(TAU * 120.0 * t) * exp(-t * 30.0) * 0.6)
	_streams[Cue.HIT_HEAVY] = _make(0.2, func(t: float) -> float:
		return _noise() * exp(-t * 18.0) * 0.5 + sin(TAU * 70.0 * t) * exp(-t * 12.0) * 0.8)
	_streams[Cue.BLOCK] = _make(0.14, func(t: float) -> float:
		return (sin(TAU * 900.0 * t) * 0.4 + sin(TAU * 1370.0 * t) * 0.3) * exp(-t * 22.0) + _noise() * exp(-t * 60.0) * 0.3)
	_streams[Cue.SHIELD] = _make(0.12, func(t: float) -> float:
		return (sin(TAU * 520.0 * t) * 0.5 + sin(TAU * 780.0 * t) * 0.3) * exp(-t * 26.0) + _noise() * exp(-t * 50.0) * 0.25)
	_streams[Cue.HORDE] = _make(1.4, func(t: float) -> float:
		var envelope := minf(t / 0.25, 1.0) * exp(-t * 1.2)
		var f := 85.0 + 4.0 * sin(TAU * 5.0 * t)
		return (signf(sin(TAU * f * t)) * 0.25 + sin(TAU * f * 2.0 * t) * 0.25) * envelope)
	_streams[Cue.ELITE] = _make(0.7, func(t: float) -> float:
		var envelope := minf(t / 0.08, 1.0) * exp(-t * 3.0)
		return (sin(TAU * 55.0 * t + sin(TAU * 7.0 * t) * 2.0) * 0.7 + _noise() * 0.15) * envelope)
	_streams[Cue.SPECIAL_ARCHER] = _make(0.35, func(t: float) -> float:
		var phase := TAU * (600.0 * t + 450.0 * t * t)
		return sin(phase) * exp(-t * 6.0) * 0.5)
	_streams[Cue.SPECIAL_GRABBER] = _make(0.6, func(t: float) -> float:
		var rattle := 0.5 + 0.5 * signf(sin(TAU * 16.0 * t))
		return (_noise() * 0.5 * rattle + sin(TAU * (300.0 - 200.0 * t) * t) * 0.3) * exp(-t * 3.5))


func play_cue(cue: Cue, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % POOL_SIZE
	player.stream = _streams[cue]
	player.pitch_scale = pitch * randf_range(0.94, 1.06)
	player.volume_db = BASE_VOLUME_DB + volume_db
	player.play()


func _make(duration: float, sample: Callable) -> AudioStreamWAV:
	var count := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var value := clampf(sample.call(float(i) / MIX_RATE), -1.0, 1.0)
		data.encode_s16(i * 2, int(value * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _noise() -> float:
	return randf_range(-1.0, 1.0)
