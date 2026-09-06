class_name DefenderProgression
extends RefCounted

# Player level curve behind the "Lv N" xp bars on the Status header, the
# honors page and the settlement panel (参考 Status/Stage Complete screens).
# Level N costs `player.level_base_xp * N` xp (data-driven, FR-080), so early
# levels arrive fast while later ones still gate long-term play. Level is
# derived from xp on the fly: profiles keep storing raw xp, so old saves need
# no migration.
const MAX_LEVEL := 99
const DEFAULT_BASE_XP := 100


static func level_base_xp(rules: Dictionary) -> int:
	var player: Dictionary = rules.get("player", {}) if rules.get("player", {}) is Dictionary else {}
	return maxi(1, int(player.get("level_base_xp", DEFAULT_BASE_XP)))


static func xp_to_next(rules: Dictionary, level: int) -> int:
	return level_base_xp(rules) * clampi(level, 1, MAX_LEVEL)


static func level_progress(rules: Dictionary, xp: int) -> Dictionary:
	var remaining := maxi(0, xp)
	var level := 1
	while level < MAX_LEVEL and remaining >= xp_to_next(rules, level):
		remaining -= xp_to_next(rules, level)
		level += 1
	return {"level": level, "into_level": remaining, "needed": xp_to_next(rules, level)}
