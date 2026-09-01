class_name DefenderDeterministicRng
extends RefCounted

var _state: int = 1


func _init(seed: int = 1) -> void:
	reseed(seed)


func reseed(seed: int) -> void:
	_state = abs(seed) & 0x7fffffff
	if _state == 0:
		_state = 1


func next_int() -> int:
	_state = int((_state * 1103515245 + 12345) & 0x7fffffff)
	return _state


func range_exclusive(minimum: int, maximum: int) -> int:
	if maximum <= minimum:
		return minimum
	return minimum + (next_int() % (maximum - minimum))


func chance_per_10000(threshold: int) -> bool:
	return (next_int() % 10000) < clampi(threshold, 0, 10000)


func state() -> int:
	return _state

