extends Node

## Controls wave-based spawning of enemies with escalating difficulty.
## Place this in the main scene alongside the TargetSpawner.
## It takes over spawning from the TargetSpawner — the spawner just provides
## the spawn position/direction logic.

signal wave_started(wave_number: int, enemy_count: int)
signal wave_completed(wave_number: int)
signal enemy_killed(remaining: int)
signal countdown_tick(seconds_left: float)
signal all_waves_cleared ## Only if you have a finite set and want a "you win" state.

@export_group("Wave Settings")
@export var time_between_waves: float = 8.0 ## Countdown seconds between waves.
@export var spawn_delay: float = 0.8 ## Seconds between each enemy spawn within a wave.
@export var first_wave_delay: float = 5.0 ## Seconds before the first wave starts.

@export_group("References")
@export var target_spawner_path: NodePath ## Path to the TargetSpawner node.

## ═══════════════════════════════════════════════════════════════════════════
## HAND-CRAFTED WAVES — edit these to your liking!
## After these run out, the system switches to procedural generation.
## Each entry: { count, speed, damage, turn_speed, homing_delay }
## ═══════════════════════════════════════════════════════════════════════════
var hand_crafted_waves: Array[Dictionary] = [
	# Wave 1: Easy intro — few slow targets
	{"count": 3, "speed": 5.0, "damage": 5.0, "turn_speed": 1.0, "homing_delay": 2.0},
	# Wave 2: A bit more, slightly faster
	{"count": 5, "speed": 6.0, "damage": 6.0, "turn_speed": 1.2, "homing_delay": 1.8},
	# Wave 3: Getting serious
	{"count": 7, "speed": 7.0, "damage": 7.0, "turn_speed": 1.5, "homing_delay": 1.5},
	# Wave 4: Pressure
	{"count": 9, "speed": 8.0, "damage": 8.0, "turn_speed": 1.8, "homing_delay": 1.3},
	# Wave 5: Mini-boss wave — fewer but tough
	{"count": 5, "speed": 6.0, "damage": 15.0, "turn_speed": 2.5, "homing_delay": 1.0},
	# Wave 6: Swarm
	{"count": 12, "speed": 9.0, "damage": 6.0, "turn_speed": 1.5, "homing_delay": 1.5},
	# Wave 7: Fast flankers
	{"count": 8, "speed": 12.0, "damage": 8.0, "turn_speed": 2.0, "homing_delay": 1.0},
	# Wave 8: Heavy hitters
	{"count": 6, "speed": 7.0, "damage": 18.0, "turn_speed": 2.2, "homing_delay": 1.2},
	# Wave 9: Big swarm
	{"count": 15, "speed": 10.0, "damage": 7.0, "turn_speed": 1.8, "homing_delay": 1.3},
	# Wave 10: Boss wave
	{"count": 8, "speed": 8.0, "damage": 20.0, "turn_speed": 3.0, "homing_delay": 0.8},
]

## ═══════════════════════════════════════════════════════════════════════════
## PROCEDURAL SCALING — used after hand-crafted waves run out
## ═══════════════════════════════════════════════════════════════════════════
@export_group("Procedural Scaling (Endless Mode)")
@export var proc_base_count: int = 10 ## Starting enemy count for procedural waves.
@export var proc_count_increase: int = 2 ## Extra enemies per wave.
@export var proc_base_speed: float = 8.0
@export var proc_speed_increase: float = 0.3 ## Speed increase per wave.
@export var proc_max_speed: float = 20.0
@export var proc_base_damage: float = 8.0
@export var proc_damage_increase: float = 1.0
@export var proc_base_turn_speed: float = 2.0
@export var proc_turn_speed_increase: float = 0.1
@export var proc_max_turn_speed: float = 5.0

# ── Internal state ──────────────────────────────────────────────────────────
var current_wave: int = 0 ## 0 = not started yet, 1 = first wave
var enemies_remaining: int = 0
var enemies_to_spawn: int = 0
var is_spawning: bool = false
var is_countdown: bool = false
var _game_over: bool = false

var _spawner: Node3D = null
var _base_node: Node3D = null
var _spawn_timer: float = 0.0
var _countdown_timer: float = 0.0
var _current_wave_data: Dictionary = {}
var _active_targets: Array[Node] = []


func _ready() -> void:
	# Find the target spawner
	if target_spawner_path:
		_spawner = get_node_or_null(target_spawner_path)

	if _spawner == null:
		# Fallback: search by name
		_spawner = get_tree().current_scene.find_child("TargetSpawner", true, false)

	if _spawner == null:
		push_error("WaveManager: No TargetSpawner found!")
		return

	# Disable the spawner's own timer-based spawning — we control it now
	_spawner.set_process(false)

	# Find the base so we can tell it to move between waves
	_base_node = get_tree().current_scene.find_child("Base", true, false)
	if _base_node == null:
		push_warning("WaveManager: No 'Base' found — base won't relocate.")

	# Start the first wave countdown
	_countdown_timer = first_wave_delay
	is_countdown = true

	print("=== WAVE MANAGER INITIALIZED ===")
	print("First wave in %.1f seconds..." % first_wave_delay)


func _process(delta: float) -> void:
	if _game_over:
		return

	if get_tree().paused:
		return

	# In multiplayer, only the server controls wave logic.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# ── Countdown between waves ───────────────────────────────────────────
	if is_countdown:
		_countdown_timer -= delta
		countdown_tick.emit(_countdown_timer)

		# Sync countdown to clients
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_remote_countdown_tick.rpc(_countdown_timer)

		if _countdown_timer <= 0.0:
			is_countdown = false
			_start_next_wave()
		return

	# ── Spawning enemies within a wave ────────────────────────────────────
	if is_spawning:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0 and enemies_to_spawn > 0:
			_spawn_one_enemy()
			_spawn_timer = spawn_delay
		return

	# ── Wave in progress but all spawned — waiting for kills ──────────────
	# (nothing to do, we track via _on_target_destroyed)


func _start_next_wave() -> void:
	current_wave += 1
	_current_wave_data = _get_wave_data(current_wave)

	enemies_to_spawn = _current_wave_data.get("count", 5)
	enemies_remaining = enemies_to_spawn
	is_spawning = true
	_spawn_timer = 0.0 # Spawn first enemy immediately

	wave_started.emit(current_wave, enemies_remaining)

	# Sync to clients
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_remote_wave_started.rpc(current_wave, enemies_remaining)

	print("=== WAVE %d START === (%d enemies, speed=%.1f, dmg=%.1f)" % [
		current_wave, enemies_remaining,
		_current_wave_data.get("speed", 8.0),
		_current_wave_data.get("damage", 10.0)
	])


func _get_wave_data(wave_num: int) -> Dictionary:
	# Use hand-crafted waves first (1-indexed, array is 0-indexed)
	var idx = wave_num - 1
	if idx < hand_crafted_waves.size():
		return hand_crafted_waves[idx]

	# Procedural generation for waves beyond the hand-crafted ones
	var proc_wave = wave_num - hand_crafted_waves.size() # How many waves into procedural
	return {
		"count": proc_base_count + proc_wave * proc_count_increase,
		"speed": min(proc_base_speed + proc_wave * proc_speed_increase, proc_max_speed),
		"damage": proc_base_damage + proc_wave * proc_damage_increase,
		"turn_speed": min(proc_base_turn_speed + proc_wave * proc_turn_speed_increase, proc_max_turn_speed),
		"homing_delay": max(0.5, 1.5 - proc_wave * 0.05),
	}


func _spawn_one_enemy() -> void:
	if _spawner == null or _spawner.target_scene == null:
		return

	enemies_to_spawn -= 1

	var target = _spawner.target_scene.instantiate()
	get_tree().current_scene.add_child(target)

	# Position using spawner's logic
	var spawn_pos = _spawner.global_position
	spawn_pos.y += randf_range(_spawner.spawn_height_min, _spawner.spawn_height_max)
	spawn_pos.x += randf_range(-_spawner.spread, _spawner.spread)
	target.global_position = spawn_pos

	# Set direction from spawner
	var dir = - _spawner.global_transform.basis.z.normalized()
	target.direction = dir

	# Apply wave-specific stats
	var spd = _current_wave_data.get("speed", 8.0)
	var dmg = _current_wave_data.get("damage", 10.0)
	var ts = _current_wave_data.get("turn_speed", 2.0)
	var hd = _current_wave_data.get("homing_delay", 1.5)
	target.speed = spd
	target.damage = dmg
	target.turn_speed = ts
	target.homing_delay = hd

	# Track this target so we know when the wave is cleared
	_active_targets.append(target)
	if target.has_signal("target_destroyed"):
		target.target_destroyed.connect(_on_target_destroyed.bind(target))
	else:
		# Fallback: use tree_exiting signal
		target.tree_exiting.connect(_on_target_destroyed.bind(target))

	if enemies_to_spawn <= 0:
		is_spawning = false

	print("  Spawned enemy %d/%d" % [
		_current_wave_data.get("count", 0) - enemies_to_spawn,
		_current_wave_data.get("count", 0)
	])

	# ── Sync to clients ──────────────────────────────────────────────────
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_remote_spawn_enemy.rpc(spawn_pos, dir, spd, dmg, ts, hd)


func _on_target_destroyed(target: Node) -> void:
	_active_targets.erase(target)
	enemies_remaining -= 1
	enemies_remaining = max(enemies_remaining, 0)

	enemy_killed.emit(enemies_remaining)

	# Sync to clients
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_remote_enemy_killed.rpc(enemies_remaining)

	if enemies_remaining <= 0 and not is_spawning:
		_wave_clear()


func _wave_clear() -> void:
	wave_completed.emit(current_wave)
	print("=== WAVE %d CLEARED! ===" % current_wave)

	# Sync to clients
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_remote_wave_completed.rpc(current_wave)

	# Tell the base to relocate for the next wave
	if _base_node and is_instance_valid(_base_node) and _base_node.has_method("move_to_random_position"):
		_base_node.move_to_random_position()

	# Start countdown to next wave
	_countdown_timer = time_between_waves
	is_countdown = true


## Call this from the base when it's destroyed to stop spawning.
func stop() -> void:
	_game_over = true
	is_spawning = false
	is_countdown = false
	print("=== WAVE MANAGER STOPPED (Game Over) ===")


# ── Multiplayer RPCs ─────────────────────────────────────────────────────────

## Server tells clients to spawn a matching enemy.
@rpc("authority", "call_remote", "reliable")
func _remote_spawn_enemy(pos: Vector3, dir: Vector3, spd: float, dmg: float, ts: float, hd: float) -> void:
	if _spawner == null or _spawner.target_scene == null:
		return
	var target = _spawner.target_scene.instantiate()
	get_tree().current_scene.add_child(target)
	target.global_position = pos
	target.direction = dir
	target.speed = spd
	target.damage = dmg
	target.turn_speed = ts
	target.homing_delay = hd


## Server tells clients a wave has started.
@rpc("authority", "call_remote", "reliable")
func _remote_wave_started(wave_num: int, enemy_count: int) -> void:
	current_wave = wave_num
	enemies_remaining = enemy_count
	wave_started.emit(wave_num, enemy_count)


## Server tells clients an enemy was killed.
@rpc("authority", "call_remote", "unreliable_ordered")
func _remote_enemy_killed(remaining: int) -> void:
	enemies_remaining = remaining
	enemy_killed.emit(remaining)


## Server tells clients a wave was completed.
@rpc("authority", "call_remote", "reliable")
func _remote_wave_completed(wave_num: int) -> void:
	wave_completed.emit(wave_num)


## Server sends countdown ticks to clients.
@rpc("authority", "call_remote", "unreliable_ordered")
func _remote_countdown_tick(seconds_left: float) -> void:
	countdown_tick.emit(seconds_left)
