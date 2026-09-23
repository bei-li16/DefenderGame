extends RefCounted
## Recorded combat foley, with procedural music/UI/ambient beds.
## Offline source edits and credits: tools/build_combat_audio.py, audio_sources/.
const RATE := 22050
const ELEMENT_KINDS := ["fire", "ice", "lightning", "fire_launch", "ice_launch", "lightning_launch"]
const FORTRESS_KINDS := ["shot", "wall", "tower", "moat"]
const SAMPLED_KINDS := ["shot", "hit", "fire", "ice", "lightning", "fire_launch", "ice_launch", "lightning_launch"]
const VARIANT_COUNT := 3
static var _sample_cache: Dictionary = {}

static func music(mood: String) -> AudioStreamWAV:
	var beat := 0.8 if mood == "menu" else (0.5 if mood == "boss" else 0.625)
	var duration := beat * 16.0
	var samples := int(RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var roots := [45, 41, 48, 43]
	var melody := [12, 19, 24, 19, 15, 19, 22, 19]
	for index in range(samples):
		var t := float(index) / RATE
		var bar := mini(3, int(t / (beat * 4)))
		var local := fmod(t, beat * 4)
		var root := _hz(roots[bar])
		var attack := minf(1.0, local / 0.10) * minf(1.0, (beat * 4 - local) / 0.18)
		var third := root * (1.189207 if bar == 0 else 1.259921)
		var pad := (sin(TAU * root * t) + sin(TAU * third * t) * 0.40 + sin(TAU * root * 1.5 * t) * 0.35) * attack * 0.075
		var step := int(local / (beat * 0.5)) % 8
		var note_t := fmod(local, beat * 0.5)
		var note := _hz(roots[bar] + melody[step])
		var pluck := sin(TAU * note * note_t) * exp(-note_t * 10.0) * minf(1.0, note_t / 0.006) * 0.075
		var bass := sin(TAU * root * 0.5 * t) * attack * 0.05
		var drum := 0.0
		if mood != "menu":
			var pulse := fmod(t, beat)
			drum = sin(TAU * (50.0 * pulse + 3.0 * (1.0 - exp(-pulse * 25)))) * exp(-pulse * 17) * 0.11
			var offbeat := fmod(t + beat * 0.5, beat)
			drum += _noise(index) * exp(-offbeat * 65) * (0.055 if mood == "boss" else 0.025)
		if mood == "boss":
			pluck += sin(TAU * note * 0.5 * note_t) * exp(-note_t * 8) * 0.04
		var edge := minf(1.0, t / 0.01) * minf(1.0, (duration - t) / 0.02)
		_write(bytes, index, (pad + pluck + bass + drum) * edge)
	return _stream(bytes, true)

static func effect(kind: String) -> AudioStreamWAV:
	if kind == "fatal":
		kind = "shot"
	if kind in SAMPLED_KINDS:
		return effect_variants(kind)[0]
	if kind in FORTRESS_KINDS:
		return _fortress_effect(kind)
	var lengths := {"boss": 0.70, "victory": 1.2, "defeat": 1.1, "reject": 0.16, "ui": 0.07}
	var duration := float(lengths.get(kind, 0.1))
	var samples := int(RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	for index in range(samples):
		var t := float(index) / RATE
		var p := t / duration
		var value := 0.0
		match kind:
			"boss": value = (sin(TAU * 65.41 * t) + sin(TAU * 98 * t) * 0.6) * 0.16
			"victory", "defeat":
				var notes := [60, 64, 67, 72] if kind == "victory" else [57, 53, 50, 45]
				var n := mini(3, int(p * 4))
				var nt := fmod(t, duration / 4)
				value = sin(TAU * _hz(notes[n]) * nt) * sin(PI * nt / (duration / 4)) * 0.23
			"ui": value = sin(TAU * 660 * t) * 0.12
			_: value = sin(TAU * 180 * t) * 0.16
		_write(bytes, index, value * pow(1 - p, 1.6) * minf(1.0, t / 0.003))
	return _stream(bytes, false)


static func effect_variants(kind: String) -> Array[AudioStreamWAV]:
	if not _sample_cache.has(kind):
		var clips: Array[AudioStreamWAV] = []
		if kind in SAMPLED_KINDS:
			for variant in range(1, VARIANT_COUNT + 1):
				clips.append(load("res://Gamematerials/Audio/%s-%02d.wav" % [kind, variant]) as AudioStreamWAV)
		else:
			clips.append(effect(kind))
		_sample_cache[kind] = clips
	return _sample_cache[kind]


static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


static func _fortress_effect(kind: String) -> AudioStreamWAV:
	var duration := float({"wall": 0.42, "tower": 0.54, "moat": 0.60}[kind])
	var count := int(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var noise_state := 984357
	var low := 0.0
	var mid := 0.0
	for index in range(count):
		noise_state = (noise_state ^ (noise_state << 13)) & 0xffffffff
		noise_state = (noise_state ^ (noise_state >> 17)) & 0xffffffff
		noise_state = (noise_state ^ (noise_state << 5)) & 0xffffffff
		var noise := float(noise_state & 0xffff) / 32768.0 - 1
		low += (noise - low) * 0.025
		mid += (noise - mid) * 0.18
		var t := float(index) / RATE
		var value := 0.0
		match kind:
			"wall":
				value = sin(TAU * 76 * t) * exp(-t * 21) * 0.2 + mid * exp(-t * 14) * 0.38
				value += (noise - mid) * exp(-t * 38) * 0.11
			"tower":
				value = (sin(TAU * (760 * t - 420 * t * t)) + sin(TAU * 1531 * t) * 0.32) * exp(-t * 9) * 0.13
				value += (noise - mid) * exp(-t * 34) * 0.07
			"moat":
				value = low * exp(-t * 6) * 0.75 + mid * exp(-t * 12) * 0.19
				value += sin(TAU * (92 * t - 55 * t * t)) * exp(-t * 17) * 0.10
		var edge := minf(1, t / 0.003) * minf(1, (duration - t) / 0.08)
		_write(bytes, index, value * edge)
	return _stream(bytes, false)


static func ambience() -> AudioStreamWAV:
	# Quiet, click-safe lava bed, generated once. Private deterministic noise
	# plus sparse bubbling; music and combat cues retain the foreground.
	var duration := 4.0
	var count := int(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var state := 836151
	var low := 0.0
	for index in range(count):
		state = (state ^ (state << 13)) & 0xffffffff
		state = (state ^ (state >> 17)) & 0xffffffff
		state = (state ^ (state << 5)) & 0xffffffff
		var noise := float(state & 0xffff) / 32768.0 - 1
		low += (noise - low) * 0.014
		var t := float(index) / RATE
		var bubble_t := fposmod(t + 0.12, 0.73)
		var bubble := sin(TAU * (95 * bubble_t - 40 * bubble_t * bubble_t)) * exp(-bubble_t * 26) * minf(1, bubble_t * 160)
		var value := low * 0.70 + bubble * 0.042 + sin(TAU * 41 * t) * 0.019
		_write(bytes, index, value * minf(1, t / 0.06) * minf(1, (duration - t) / 0.06))
	return _stream(bytes, true)

static func _noise(index: int) -> float:
	return float(((index * 1103515245 + 12345) & 0x7fffffff) % 65536) / 32768.0 - 1.0

static func _write(bytes: PackedByteArray, index: int, value: float) -> void:
	var sample := clampi(int(value * 32767), -32767, 32767)
	bytes[index * 2] = sample & 0xff
	bytes[index * 2 + 1] = (sample >> 8) & 0xff

static func _stream(bytes: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = bytes.size() / 2
	return stream
