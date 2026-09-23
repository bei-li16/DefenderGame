class_name DefenderProceduralAudio
extends Node

const Bank = preload("res://src/infrastructure/audio/sound_bank.gd")
const PLAYER_COUNT := 10
const GAPS := {"shot": 65, "hit": 90, "fatal": 120, "fire": 110, "ice": 110, "lightning": 110, "fire_launch": 150, "ice_launch": 150, "lightning_launch": 160, "wall": 170, "tower": 220, "moat": 300, "boss": 450, "reject": 180, "ui": 70}
var _players: Array[AudioStreamPlayer] = []
var _music_players: Array[AudioStreamPlayer] = []
var _music_streams: Dictionary = {}
var _sounds: Dictionary = {}
var _last_play: Dictionary = {}
var _cursor := 0
var _spell_cursor := 0
var _launch_cursor := 0
var _active_music := 0
var _music_volume := 0.65
var _music_mix := 1.0
var _duck := 1.0
var _duck_target := 1.0
var _mood := ""
var _disabled := false
var _ambience_player: AudioStreamPlayer
var _defense_player: AudioStreamPlayer
var _ambience_stream: AudioStreamWAV


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_disabled = DisplayServer.get_name().contains("headless")
	if _disabled:
		return
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "MoatAmbience"
	add_child(_ambience_player)
	_defense_player = AudioStreamPlayer.new()
	_defense_player.name = "DefenseFoley"
	add_child(_defense_player)
	_ambience_stream = Bank.ambience()
	for index in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "Music%d" % index
		add_child(player)
		_music_players.append(player)
	for index in range(PLAYER_COUNT):
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	for kind in ["shot", "hit", "fatal", "wall", "tower", "moat", "boss", "victory", "defeat", "reject", "ui"] + Bank.ELEMENT_KINDS:
		_sounds[kind] = Bank.effect(kind)
	for mood in ["menu", "battle", "boss"]:
		_music_streams[mood] = Bank.music(mood)


func _process(delta: float) -> void:
	if _disabled:
		return
	_music_mix = minf(1.0, _music_mix + delta / 0.8)
	_duck = move_toward(_duck, _duck_target, delta * 2)
	for index in range(2):
		var gain := _music_mix if index == _active_music else 1.0 - _music_mix
		_music_players[index].volume_db = gain_db(_music_volume * gain * _duck)
		if gain == 0 and index != _active_music:
			_music_players[index].stop()


static func gain_db(value: float) -> float:
	return -80.0 if value <= 0.0 else linear_to_db(clampf(value, 0.0001, 1.0))


func play_music(mood: String, volume_linear: float = 0.65) -> void:
	_music_volume = clampf(volume_linear, 0, 1)
	if _disabled or not _music_streams.has(mood) or _mood == mood:
		return
	_mood = mood
	_active_music = 1 - _active_music
	_music_mix = 0.0
	var player := _music_players[_active_music]
	player.stream = _music_streams[mood]
	player.volume_db = -80
	player.play()


func set_music_volume(value: float) -> void:
	_music_volume = clampf(value, 0, 1)


func set_ducked(value: bool) -> void:
	_duck_target = 0.32 if value else 1.0


func stop_all() -> void:
	stop_ambience()
	if _defense_player != null:
		_defense_player.stop()
		_defense_player.stream = null
	for player in _players + _music_players:
		player.stop()
		player.stream = null
	_mood = ""
	_last_play.clear()


func shutdown() -> void:
	stop_all()
	_sounds.clear()
	_music_streams.clear()
	_ambience_stream = null


func set_ambience(moat: bool, volume: float, suspended: bool) -> void:
	if _disabled or _ambience_player == null:
		return
	if not moat or volume <= 0 or suspended:
		stop_ambience()
		return
	_ambience_player.volume_db = gain_db(clampf(volume, 0, 1) * 0.22)
	if not _ambience_player.playing:
		_ambience_player.stream = _ambience_stream
		_ambience_player.play()


func stop_ambience() -> void:
	if _ambience_player != null:
		_ambience_player.stop()
		_ambience_player.stream = null


func play_ui(volume: float) -> void:
	_play("ui", volume)


func play_event(event: Dictionary, volume_linear: float = 1.0) -> void:
	var kind := event_kind(event)
	# Tiny deterministic pitch variations avoid a machine-gun sample loop.
	# They never consume combat randomness or change event timing.
	var variation := int(event.get("x_milli", 0)) / 1000 + int(event.get("tick", 0)) * 7
	var pitch := 0.94 + posmod(variation, 13) * 0.01 if kind in Bank.ELEMENT_KINDS else 1.0
	_play(kind, volume_linear, pitch)


static func event_kind(event: Dictionary) -> String:
	var kind := ""
	match str(event.get("type", "")):
		"shot": kind = "fatal" if bool(event.get("fatal", false)) else "shot"
		"hit": kind = "hit" # damage is not a second copy of the same impact.
		"skill_pulse": kind = str(event.get("element", ""))
		"skill_launch": kind = str(event.get("element", "")) + "_launch"
		"skill_rejected": kind = "reject"
		"wall_damage": kind = "wall" if int(event.get("amount", 0)) > 0 else ""
		"defense_attack": kind = "tower" if str(event.get("defense_id", "")) == "magic_tower" else ("moat" if str(event.get("defense_id", "")) == "lava_moat" else "")
		"boss_warning", "boss_special": kind = "boss"
		"run_end": kind = "victory" if str(event.get("status", "")) == "victory" else "defeat"
	return kind


func _play(kind: String, volume: float, pitch: float = 1.0) -> void:
	if _disabled or volume <= 0.0 or not _sounds.has(kind):
		return
	if not allow_event(kind, Time.get_ticks_msec()):
		return
	# One bounded extra voice: defense cues cannot cut off the bow's pluck.
	if kind in ["tower", "moat"]:
		_defense_player.stream = _sounds[kind]
		_defense_player.volume_db = gain_db(volume * 0.52)
		_defense_player.play()
		return
	# Two reserved voices keep alerts/results audible amid rapid impacts.
	var important := kind in ["boss", "victory", "defeat", "reject"]
	var elemental := kind in Bank.ELEMENT_KINDS
	var index := 8 if kind == "boss" else 9
	if not important:
		# Four impact, two launch and two weapon/UI voices. Incoming whooshes
		# cannot truncate the previous impact's boom/crystal/thunder tail.
		if kind.ends_with("_launch"):
			index = 4 + _launch_cursor
			_launch_cursor = (_launch_cursor + 1) % 2
		elif elemental:
			index = _spell_cursor
			_spell_cursor = (_spell_cursor + 1) % 4
		else:
			index = 6 + _cursor
			_cursor = (_cursor + 1) % 2
	var player := _players[index]
	player.stream = _sounds[kind]
	player.pitch_scale = pitch
	player.volume_db = gain_db(volume * (0.60 if elemental else (0.72 if not important else 1.0)))
	player.play()


func allow_event(kind: String, now_ms: int) -> bool:
	if now_ms - int(_last_play.get(kind, -100000)) < int(GAPS.get(kind, 100)):
		return false
	_last_play[kind] = now_ms
	return true
