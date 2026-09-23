extends SceneTree
## Serial --script test: uses isolated automated-app-data, not player saves.
const Art = preload("res://src/presentation/art/game_art.gd")
const Icons = preload("res://src/presentation/art/spell_icons.gd")
const ElementIcon = preload("res://src/presentation/art/element_icon.gd")
const SkillButton = preload("res://src/presentation/gameplay/skill_button.gd")
const Fortress = preload("res://src/presentation/art/fortress_visuals.gd")
const Bank = preload("res://src/infrastructure/audio/sound_bank.gd")
const Audio = preload("res://src/infrastructure/audio/procedural_audio.gd")
const OUTPUT := "res://Builds/fortress-art-review"
var app: Node
var passes := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	app = root.get_node("GameApp")
	app.set_process(false)
	app.get("settings")["auto_fire"] = false
	app.get("settings")["screen_shake"] = false
	app.get("settings")["quality"] = "high"
	if OS.get_cmdline_user_args().has("--verify-pack"):
		_expect(not ResourceLoader.exists("res://tests/fortress_art_acceptance.gd") and not DirAccess.dir_exists_absolute("res://参考"), "diagnostic pack excludes tests and reference images")
	if OS.get_cmdline_user_args().has("--interactive"):
		app.set("profile", _profile(3))
		app.get("profile")["highest_unlocked_stage"] = 30
		app.get("profile")["upgrades"]["wall_repair"] = 100000
		var preview := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
		root.add_child(preview)
		current_scene = preview
		print("[FORTRESS PLAYTEST] Isolated profile; close window to finish.")
		return
	_check_assets()
	_check_audio()
	await _check_ui()
	await _check_scene()
	await _icon_sheet()
	app.get("audio").stop_all()
	for failure in failures:
		push_error("[FORTRESS ART FAIL] " + failure)
	print("[FORTRESS ART] %d passed, %d failed" % [passes, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _profile(tier: int) -> Dictionary:
	var profile: Dictionary = app.call("_default_profile")
	profile["tutorial_complete"] = true
	profile["upgrades"]["mana_capacity"] = 30
	profile["upgrades"]["lava_moat"] = 3
	profile["upgrades"]["magic_tower"] = 3
	for skill in app.get("content").rules["skills"]:
		profile["upgrades"][skill["upgrade_id"]] = 3
		if int(skill["tier"]) == tier:
			profile["equipped_skills"][skill["element"]] = skill["id"]
	return profile


func _check_assets() -> void:
	var signatures := {}
	for element in Icons.ELEMENTS:
		for tier in [1, 2, 3]:
			var icon := Icons.texture(element, tier)
			var image := icon.get_image()
			signatures[hash(image.get_data())] = true
			_expect(icon == Icons.texture(element, tier), element + str(tier) + " caches one distinct atlas region")
			var empty := 0
			var visible := 0
			for y in range(0, image.get_height(), 6):
				for x in range(0, image.get_width(), 6):
					var alpha := image.get_pixel(x, y).a
					if alpha < 0.02: empty += 1
					if alpha > 0.5: visible += 1
			_expect(empty > 60 and visible > 60, element + str(tier) + " has both transparent padding and painted subject")
	_expect(signatures.size() == 9, "all nine spell icons contain different artwork")
	for key in ["spell_icons", "fortress_fx"]:
		var texture := Art.texture(key)
		_expect(texture.get_size() == Vector2(1024, 1024) and texture.get_image().has_mipmaps(), key + " bounded mipmapped atlas")
	for key in ["battle", "lava"]:
		var texture := Art.texture(key)
		_expect(absf(float(texture.get_width()) / texture.get_height() - 16.0 / 9.0) < 0.01, key + " is a full landscape plate, not a portrait crop")
		_expect(texture.get_image().detect_alpha() == Image.ALPHA_NONE and texture.get_image().has_mipmaps(), key + " is opaque and mipmapped")
	_expect(Art.texture("battle").get_size() == Art.texture("lava").get_size(), "paired terrain shares projection and dimensions")
	for uv in [Fortress.LAVA_UV, Fortress.CHIPS_UV]:
		_expect(Art.region("fortress_fx", uv) == Art.region("fortress_fx", uv), "fortress parts share cached regions")


func _check_audio() -> void:
	var hashes := {}
	for kind in Bank.FORTRESS_KINDS + ["ambience"]:
		var clip := Bank.ambience() if kind == "ambience" else Bank.effect(kind)
		var bytes := clip.data
		hashes[hash(bytes)] = true
		var peak := 0
		var energy := 0.0
		for index in range(0, bytes.size(), 2):
			var sample := bytes.decode_s16(index)
			peak = maxi(peak, absi(sample))
			energy += float(sample) * sample
		_expect(peak > 700 and peak < 25000 and sqrt(energy / (bytes.size() / 2)) > 60, kind + " audible PCM with headroom")
		_expect(bytes.decode_s16(0) == 0 and absi(bytes.decode_s16(bytes.size() - 2)) < 20, kind + " click-safe start and end")
		_expect((clip.loop_mode == AudioStreamWAV.LOOP_FORWARD) == (kind == "ambience"), kind + " correct loop mode")
		if OS.get_cmdline_user_args().has("--capture"):
			DirAccess.make_dir_recursive_absolute(OUTPUT)
			clip.save_to_wav(OUTPUT + "/" + kind + ".wav")
	_expect(hashes.size() == 5, "four different fortress cues plus ambient bed")
	_expect(Audio.event_kind({"type": "defense_attack", "defense_id": "magic_tower"}) == "tower", "tower foley follows authoritative attack")
	_expect(Audio.event_kind({"type": "defense_attack", "defense_id": "lava_moat"}) == "moat", "moat foley follows authoritative attack")
	_expect(Audio.event_kind({"type": "wall_damage", "amount": 0}) == "", "fully absorbed wall hit is not a damage sound")
	if DisplayServer.get_name().contains("headless"):
		return
	var mixer: Node = app.get("audio")
	var player: AudioStreamPlayer = mixer.get("_ambience_player")
	mixer.set_ambience(true, 0.8, false)
	_expect(player.playing, "upgraded moat starts ambient bed")
	mixer.set_ambience(true, 0, false)
	_expect(not player.playing, "zero SFX volume stops ambient bed")
	mixer.set_ambience(true, 0.8, true)
	_expect(not player.playing, "pause/result keeps ambience stopped")
	mixer.set_ambience(false, 0.8, false)
	_expect(not player.playing, "ordinary ground never plays lava ambience")
	mixer.set_ambience(true, 0.8, false)
	mixer.stop_all()
	_expect(not player.playing and player.stream == null, "scene cleanup releases ambience")
	mixer.play_event({"type": "defense_attack", "defense_id": "magic_tower"}, 0.8)
	_expect(mixer.get("_defense_player").stream == mixer.get("_sounds")["tower"] and mixer.get("_players").all(func(p: AudioStreamPlayer) -> bool: return p.stream == null), "dedicated defense voice does not steal skill/weapon/alert voices")
	mixer.stop_all()


func _check_ui() -> void:
	for tier in [1, 2, 3]:
		app.set("profile", _profile(tier))
		var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
		root.add_child(menu)
		await _frames(2)
		for element in Icons.ELEMENTS:
			var selector: MenuButton = menu.find_child("SkillSelector_" + element, true, false)
			var emblem: Control = _icons_under(selector)[0]
			_expect(emblem.element == element and emblem.tier == tier and emblem.mouse_filter == Control.MOUSE_FILTER_IGNORE, "loadout shows equipped " + element + str(tier) + " without intercepting clicks")
			var popup := selector.get_popup()
			for index in range(3):
				_expect(popup.get_item_icon(index) == Icons.texture(element, index + 1), "dropdown uses tier-specific " + element + str(index + 1))
		if tier == 3:
			await _capture("menu-tier3")
			menu.call("_show_research_page", "magic", "armageddon")
			await _frames(2)
			for skill in app.get("content").rules["skills"]:
				var node := menu.find_child("Research_" + str(skill["upgrade_id"]), true, false)
				var research_icons := _icons_under(node)
				_expect(research_icons.size() == 1 and research_icons[0].element == skill["element"] and research_icons[0].tier == skill["tier"], str(skill["id"]) + " research node matches spell tier")
			await _capture("research-nine-icons")
		menu.free()


func _check_scene() -> void:
	app.set("profile", _profile(3))
	var game := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.get("session").set_physics_process(false)
	var snapshot: Dictionary = game.get("snapshot")
	var before := JSON.stringify(snapshot)
	game.set("_aim_visual_angle", 0.0)
	game.queue_redraw()
	var idle := await _frame_image()
	game.call("_on_events", [{"type": "shot"}, {"type": "defense_attack", "defense_id": "magic_tower", "x_milli": 750000, "y_milli": 430000}, {"type": "defense_attack", "defense_id": "lava_moat", "x_milli": 420000, "y_milli": 660000}, {"type": "wall_damage", "entity_id": 0, "amount": 1}])
	_expect(game.get("_tower_flash") == 1.0 and game.get("_bow_recoil") == 1.0, "actual events trigger crystal discharge and mechanical recoil")
	paused = true
	game.call("_process", 0.2)
	_expect(game.get("_tower_flash") == 1.0 and game.get("_bow_recoil") == 1.0 and game.get("_elapsed_visual") == 0.0, "pause freezes tower, bow and terrain clocks")
	paused = false
	game.call("_process", 0.035)
	game.set("_aim_visual_angle", 0.0)
	await _frames(2)
	await _capture("fortress-defenses-active")
	var active := await _frame_image()
	if active != null:
		_expect(_changed_pixels(idle, active, Rect2(170, 485, 190, 145)) > 30, "ballista recoil visibly changes the mounting region")
		var crown := preload("res://src/presentation/art/castle_view.gd").magic_origin()
		_expect(_changed_pixels(idle, active, Rect2(crown - Vector2(25, 30), Vector2(50, 60))) > 10, "tower discharge visibly changes its original crystal crown")
	for quality in ["low", "medium", "high"]:
		app.get("settings")["quality"] = quality
		for i in range(25):
			game.call("_process", 1.0 / 30)
		await _capture("fortress-" + quality)
	_expect(game.get("_tower_flash") == 0.0 and game.get("_bow_recoil") == 0.0 and game.get("effects").is_empty(), "event VFX expire and mechanisms return to idle")
	_expect(before == JSON.stringify(snapshot), "fortress animation does not mutate combat snapshot")
	game.set("_aim_visual_angle", 0.0)
	game.queue_redraw()
	var terrain_start := await _frame_image()
	game.call("_process", 0.65)
	game.set("_aim_visual_angle", 0.0)
	game.queue_redraw()
	var terrain_end := await _frame_image()
	if terrain_end != null:
		_expect(_changed_pixels(terrain_start, terrain_end, Rect2(350, 310, 90, 410)) > 10, "moat bubbles and embers visibly animate inside the channel")
		paused = true
		game.call("_process", 0.4)
		var frozen := await _frame_image()
		_expect(_changed_pixels(terrain_end, frozen, Rect2(350, 310, 90, 410)) == 0, "paused moat pixels remain unchanged")
		_expect(not app.get("audio").get("_ambience_player").playing, "game pause stops its ambient loop")
		paused = false
		game.call("_process", 0.0)
		_expect(app.get("audio").get("_ambience_player").playing, "resuming battle restores its ambient loop")
	var hud: Control = game.get("_hud")
	for id in hud.skill_buttons:
		_expect(hud.skill_buttons[id].tier == 3, "battle HUD preserves tier III for " + str(id))
	var ordinary := snapshot.duplicate(true)
	ordinary["defenses"]["lava_moat_level"] = 0
	ordinary["defenses"]["magic_tower_level"] = 0
	game.call("_on_snapshot", ordinary)
	game.call("_process", 0.0)
	game.set("_aim_visual_angle", 0.0)
	await _capture("fortress-ordinary-ground")
	if not DisplayServer.get_name().contains("headless"):
		_expect(not app.get("audio").get("_ambience_player").playing, "ordinary battlefield stops the lava loop through gameplay")
	game.free()
	if not DisplayServer.get_name().contains("headless"):
		_expect(not app.get("audio").get("_ambience_player").playing, "leaving battle stops its ambient loop")


func _icon_sheet() -> void:
	var panel := ColorRect.new()
	panel.color = Color("101b2d")
	panel.size = Vector2(1920, 1080)
	root.add_child(panel)
	for row in range(3):
		for column in range(3):
			var origin := Vector2(250 + column * 515, 150 + row * 260)
			var label := Label.new()
			label.position = origin
			label.text = ["火球", "冰霜", "雷电"][row] + " · " + ["Ⅰ", "Ⅱ", "Ⅲ"][column]
			label.add_theme_font_size_override("font_size", 27)
			panel.add_child(label)
			var button := SkillButton.new()
			button.position = origin + Vector2(0, 50)
			button.size = Vector2(112, 112)
			button.element = Icons.ELEMENTS[row]
			button.tier = column + 1
			button.hotkey = str(row + 1)
			button.mana_cost = 30 + column * 30
			panel.add_child(button)
			var icon := ElementIcon.new()
			icon.element = button.element
			icon.tier = button.tier
			icon.position = origin + Vector2(144, 72)
			icon.size = Vector2(48, 48)
			panel.add_child(icon)
			var recovering := SkillButton.new()
			recovering.element = button.element
			recovering.tier = button.tier
			recovering.position = origin + Vector2(240, 50)
			recovering.size = Vector2(112, 112)
			recovering.set_state(0.55, true, false)
			panel.add_child(recovering)
	await _frames(2)
	await _capture("nine-icons-hud-48px-and-cooldown")
	panel.free()


func _icons_under(node: Node) -> Array:
	var result := []
	if node == null: return result
	for child in node.get_children():
		if child.get_script() == ElementIcon: result.append(child)
		result.append_array(_icons_under(child))
	return result


func _frames(count: int) -> void:
	for ignored in range(count): await process_frame


func _frame_image() -> Image:
	if DisplayServer.get_name().contains("headless"):
		return null
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _changed_pixels(first: Image, second: Image, area: Rect2) -> int:
	var changed := 0
	var scale := Vector2(first.get_size()) / Vector2(1920, 1080)
	for y in range(int(area.position.y), int(area.end.y), 2):
		for x in range(int(area.position.x), int(area.end.x), 2):
			var point := Vector2i(Vector2(x, y) * scale)
			var a := first.get_pixelv(point)
			var b := second.get_pixelv(point)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.025:
				changed += 1
	return changed


func _capture(label: String) -> void:
	if DisplayServer.get_name().contains("headless") or not OS.get_cmdline_user_args().has("--capture"): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png")


func _expect(condition: bool, label: String) -> void:
	if condition: passes += 1
	else: failures.append(label)
