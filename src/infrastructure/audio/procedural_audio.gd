class_name DefenderProceduralAudio
extends Node

const SAMPLE_RATE := 22050
const PLAYER_COUNT := 10

var _players: Array[AudioStreamPlayer] = []
var _cursor: int = 0
var _sounds: Dictionary = {}
var _music_player: AudioStreamPlayer
var _music_streams: Dictionary = {}
var _disabled: bool = false


func _ready() -> void:
	_disabled = DisplayServer.get_name().contains("headless")
	if _disabled:
		return
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "Music"
	add_child(_music_player)
	for index in range(PLAYER_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "Voice%d" % index
		add_child(player)
		_players.append(player)
	_sounds = {
		"shot": _tone(760.0, 0.055, 0.22, 0.72),
		"hit": _tone(180.0, 0.07, 0.25, 0.35),
		"fatal": _tone(1040.0, 0.16, 0.32, 0.75),
		"fire": _tone(125.0, 0.34, 0.42, 0.18),
		"ice": _tone(1320.0, 0.28, 0.28, 0.95),
		"lightning": _tone(84.0, 0.30, 0.44, 0.08),
		"wall": _tone(74.0, 0.12, 0.34, 0.12),
		"boss": _tone(56.0, 0.62, 0.45, 0.03),
		"victory": _tone(660.0, 0.55, 0.30, 0.82),
		"defeat": _tone(110.0, 0.58, 0.34, 0.15),
		"reject": _tone(220.0, 0.12, 0.20, 0.02)
	}
	_music_streams = {
		"menu": _music_loop([110.0, 146.83, 164.81], 4.0, 0.11),
		"battle": _music_loop([82.41, 123.47, 164.81], 3.0, 0.13)
	}


func play_music(mood: String, volume_linear: float = 0.6) -> void:
	if _disabled:
		return
	if not _music_streams.has(mood):
		return
	_music_player.volume_db = linear_to_db(clampf(volume_linear, 0.01, 1.0))
	if _music_player.stream != _music_streams[mood]:
		_music_player.stream = _music_streams[mood]
		_music_player.play()
	elif not _music_player.playing:
		_music_player.play()


func set_music_volume(volume_linear: float) -> void:
	if _disabled:
		return
	_music_player.volume_db = linear_to_db(clampf(volume_linear, 0.01, 1.0))


func stop_all() -> void:
	if _disabled:
		return
	if _music_player != null:
		_music_player.stop()
		_music_player.stream = null
	for player in _players:
		player.stop()
		player.stream = null


func shutdown() -> void:
	stop_all()
	_sounds.clear()
	_music_streams.clear()


func play_event(event: Dictionary, volume_linear: float = 1.0) -> void:
	if _disabled:
		return
	var sound_id := ""
	match str(event.get("type", "")):
		"shot":
			sound_id = "fatal" if bool(event.get("fatal", false)) else "shot"
		"hit", "damage":
			sound_id = "hit" if str(event.get("source", "")) == "arrow" or event["type"] == "hit" else ""
		"skill_cast":
			sound_id = str(event.get("element", ""))
			match str(event.get("skill_id", "")):
				"fire_ball": sound_id = "fire"
				"glacial_spike": sound_id = "ice"
				"lightning_strike": sound_id = "lightning"
		"skill_rejected":
			sound_id = "reject"
		"wall_damage":
			sound_id = "wall"
		"boss_warning", "boss_special":
			sound_id = "boss"
		"run_end":
			sound_id = "victory" if str(event.get("status", "")) == "victory" else "defeat"
	if sound_id.is_empty() or not _sounds.has(sound_id):
		return
	var player := _players[_cursor]
	_cursor = (_cursor + 1) % _players.size()
	player.stream = _sounds[sound_id]
	player.volume_db = linear_to_db(clampf(volume_linear, 0.01, 1.0))
	player.play()


func _tone(frequency: float, duration: float, amplitude: float, harmonic: float) -> AudioStreamWAV:
	var sample_count := maxi(1, int(float(SAMPLE_RATE) * duration))
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for sample_index in range(sample_count):
		var time := float(sample_index) / float(SAMPLE_RATE)
		var envelope := pow(1.0 - float(sample_index) / float(sample_count), 2.0)
		var wave := sin(TAU * frequency * time) + harmonic * sin(TAU * frequency * 2.01 * time)
		var sample := clampi(int(wave * envelope * amplitude * 16000.0), -32768, 32767)
		bytes[sample_index * 2] = sample & 0xff
		bytes[sample_index * 2 + 1] = (sample >> 8) & 0xff
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


func _music_loop(frequencies: Array, duration: float, amplitude: float) -> AudioStreamWAV:
	var sample_count := maxi(1, int(float(SAMPLE_RATE) * duration))
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for sample_index in range(sample_count):
		var time := float(sample_index) / float(SAMPLE_RATE)
		var value := 0.0
		for frequency in frequencies:
			value += sin(TAU * float(frequency) * time) * 0.55
			value += sin(TAU * float(frequency) * 0.5 * time) * 0.18
		var pulse := 0.72 + 0.28 * sin(TAU * 0.5 * time)
		var sample := clampi(int(value * pulse * amplitude * 7000.0), -32768, 32767)
		bytes[sample_index * 2] = sample & 0xff
		bytes[sample_index * 2 + 1] = (sample >> 8) & 0xff
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	stream.data = bytes
	return stream
