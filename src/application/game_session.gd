class_name DefenderGameSession
extends Node

signal events_produced(events: Array)
signal snapshot_changed(snapshot: Dictionary)
signal run_finished(result: Dictionary)

const RunModel = preload("res://src/core/combat/run_model.gd")
const EventHasher = preload("res://src/core/replay/event_hasher.gd")
const ReplayService = preload("res://src/application/replay_service.gd")

var _model := RunModel.new()
var _pending_commands: Array = []
var _command_log: Array = []
var _event_log: Array = []
var _started: bool = false
var _finished_emitted: bool = false
var replay_service := ReplayService.new()
# Command and event logs serve replay export only (FR-083: debug builds).
# Release builds skip logging so long sessions do not accumulate entries.
var logging_enabled: bool = OS.is_debug_build()


func start(config: Dictionary, stage_id: String, seed: int, profile: Dictionary, run_instance_id: String = "") -> Dictionary:
	var result := _model.setup(config, stage_id, seed, profile, run_instance_id)
	_started = bool(result.get("ok", false))
	_finished_emitted = false
	_pending_commands.clear()
	_command_log.clear()
	_event_log.clear()
	if _started:
		snapshot_changed.emit(_model.snapshot())
	return result


func queue_command(command: Dictionary) -> void:
	if not _started or _model.status != "running":
		return
	var logged := command.duplicate(true)
	if str(command.get("type", "")) == "aim" and not _pending_commands.is_empty() and str(_pending_commands[-1].get("type", "")) == "aim":
		# Aim commands emit no events and only the final target before a
		# fire/cast command affects the simulation, so same-window aims
		# collapse to the latest one without changing behavior or replay.
		_pending_commands[-1] = logged
		if logging_enabled and not _command_log.is_empty() and str(_command_log[-1].get("type", "")) == "aim":
			_command_log[-1] = logged
		return
	logged["queued_at_tick"] = _model.tick + 1
	logged["sequence"] = _pending_commands.size()
	_pending_commands.append(logged)
	if logging_enabled:
		_command_log.append(logged.duplicate(true))


func current_snapshot() -> Dictionary:
	return _model.snapshot()


func current_result() -> Dictionary:
	return _model.result()


func replay_record() -> Dictionary:
	return {
		"run_id": _model.run_id,
		"stage_id": _model.stage.get("id", ""),
		"seed": _model.seed,
		"config_version": _model.config.get("config_version", 0),
		"commands": _command_log.duplicate(true),
		"event_hash": EventHasher.hash_events(_event_log)
	}


func export_debug_replay() -> Dictionary:
	if not logging_enabled:
		return {"ok": false, "error_code": "debug_only"}
	var record := replay_record()
	record["result"] = _model.result()
	return replay_service.export_record(record)


func _physics_process(_delta: float) -> void:
	if not _started or _model.status != "running":
		return
	var events := _model.step(_pending_commands)
	_pending_commands.clear()
	if not events.is_empty():
		if logging_enabled:
			_event_log.append_array(events)
		events_produced.emit(events)
	var snapshot := _model.snapshot()
	snapshot_changed.emit(snapshot)
	if _model.status != "running" and not _finished_emitted:
		_finished_emitted = true
		run_finished.emit(_model.result())
