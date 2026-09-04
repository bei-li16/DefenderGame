class_name DefenderProgression
extends RefCounted

# Player level curve behind the "Lv N" xp bars on the Status header, the
# honors page and the settlement panel (参考 Status/Stage Complete screens).
# Level N costs 100 * N xp, so early levels arrive fast while later ones
# still gate long-term play. Level is derived from xp on the fly: profiles
# keep storing raw xp, so old saves need no migration.
const MAX_LEVEL := 99


static func xp_to_next(level: int) -> int:
	return 100 * clampi(level, 1, MAX_LEVEL)


static func level_progress(xp: int) -> Dictionary:
	var remaining := maxi(0, xp)
	var level := 1
	while level < MAX_LEVEL and remaining >= xp_to_next(level):
		remaining -= xp_to_next(level)
		level += 1
	return {"level": level, "into_level": remaining, "needed": xp_to_next(level)}
