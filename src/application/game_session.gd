class_name DefenderGameSession
extends Node

signal events_produced(events: Array)
signal snapshot_changed(snapshot: Dictionary)
signal run_finished(result: Dictionary)

const RunModel = preload("res://src/core/combat/run_model.gd")
const EventHasher = preload("res://src/core/replay/event_hasher.gd")

var _model := RunModel.new()
var _pending_commands: Array = []
var _command_log: Array = []
var _event_log: Array = []
var _started: bool = false
var _finished_emitted: bool = false


func start(config: Dictionary, stage_id: String, seed: int, profile: Dictionary) -> Dictionary:
	var result := _model.setup(config, stage_id, seed, profile)
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
	logged["queued_at_tick"] = _model.tick + 1
	logged["sequence"] = _pending_commands.size()
	_pending_commands.append(logged)
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


func _physics_process(_delta: float) -> void:
	if not _started or _model.status != "running":
		return
	var events := _model.step(_pending_commands)
	_pending_commands.clear()
	if not events.is_empty():
		_event_log.append_array(events)
		events_produced.emit(events)
	var snapshot := _model.snapshot()
	snapshot_changed.emit(snapshot)
	if _model.status != "running" and not _finished_emitted:
		_finished_emitted = true
		run_finished.emit(_model.result())

