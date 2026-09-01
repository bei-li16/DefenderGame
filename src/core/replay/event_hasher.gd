class_name DefenderEventHasher
extends RefCounted


static func hash_events(events: Array) -> String:
	return JSON.stringify(events, "", true).sha256_text()


static func hash_snapshot(snapshot: Dictionary) -> String:
	return JSON.stringify(snapshot, "", true).sha256_text()

