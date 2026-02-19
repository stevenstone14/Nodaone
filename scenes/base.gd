extends StaticBody3D

## The base that enemies (targets) attack. Defend it!
## Floats around the level, picking a new position each wave.
## Targets will home in on it wherever it goes.

signal health_changed(current_hp: float, max_hp: float)
signal base_destroyed
signal started_moving(target_pos: Vector3) ## Emitted when the base begins moving to a new spot.

@export_group("Health")
@export var max_health: float = 100.0
@export var damage_flash_duration: float = 0.15 ## How long the damage flash lasts.

@export_group("Movement")
@export var move_speed: float = 8.0 ## How fast the base moves to its new position.
@export var hover_height: float = 5.0 ## Height the base floats at above the ground.
@export var hover_bob_amplitude: float = 0.6 ## How much it bobs up and down while floating.
@export var hover_bob_speed: float = 1.5 ## Speed of the hover bobbing animation.
@export var rotation_speed: float = 0.3 ## Slow rotation speed (radians/sec) for visual flair.

@export_group("Movement Bounds")
@export var bounds_min: Vector3 = Vector3(-70, 0, -85) ## Minimum XYZ for random positions.
@export var bounds_max: Vector3 = Vector3(15, 0, -5) ## Maximum XYZ for random positions.
@export var min_move_distance: float = 20.0 ## Minimum distance the base must move each wave.

var current_health: float

# ── Movement state ────────────────────────────────────────────────────────
var _target_position: Vector3 = Vector3.ZERO
var _is_moving: bool = false
var _bob_timer: float = 0.0
var _base_y: float = 0.0 ## The "resting" Y position (hover_height).

# ── Flash state ───────────────────────────────────────────────────────────
var _flash_timer: float = 0.0
var _original_color: Color = Color.WHITE
var _original_emission: Color = Color.BLACK
var _original_emission_enabled: bool = false
var _original_emission_energy: float = 1.0
var _mesh: MeshInstance3D


func _ready() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)

	# Cache the mesh for damage flash effect
	_mesh = get_node_or_null("MeshInstance3D")
	if _mesh and _mesh.mesh:
		# Store original material state so we can restore after flash
		var mat = _mesh.get_active_material(0)
		if mat is StandardMaterial3D:
			_original_color = mat.albedo_color
			_original_emission_enabled = mat.emission_enabled
			_original_emission = mat.emission
			_original_emission_energy = mat.emission_energy_multiplier

	# Set up initial floating position
	_base_y = global_position.y
	if _base_y < hover_height:
		_base_y = hover_height
	_target_position = global_position
	_target_position.y = _base_y


func _process(delta: float) -> void:
	if get_tree().paused:
		return

	# ── Smooth movement toward target position ────────────────────────────
	if _is_moving:
		var flat_current = Vector3(global_position.x, _base_y, global_position.z)
		var flat_target = Vector3(_target_position.x, _base_y, _target_position.z)
		var distance = flat_current.distance_to(flat_target)

		if distance < 0.3:
			# Arrived
			_is_moving = false
			global_position.x = _target_position.x
			global_position.z = _target_position.z
		else:
			# Smooth move — ease out for nice deceleration
			var move_step = move_speed * delta
			var direction = (flat_target - flat_current).normalized()
			global_position.x += direction.x * move_step
			global_position.z += direction.z * move_step

	# ── Hover bob animation ───────────────────────────────────────────────
	_bob_timer += delta * hover_bob_speed
	global_position.y = _base_y + sin(_bob_timer) * hover_bob_amplitude

	# ── Slow rotation for visual flair ────────────────────────────────────
	rotate_y(rotation_speed * delta)

	# ── Handle damage flash fade-out ──────────────────────────────────────
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_reset_material_color()


## Moves the base to a new random position within bounds.
## Called by the WaveManager between/during waves.
## In multiplayer, only the server picks the position and syncs to clients.
func move_to_random_position() -> void:
	var new_pos = _pick_random_position()

	# Make sure it's far enough from current spot
	var attempts = 0
	while new_pos.distance_to(global_position) < min_move_distance and attempts < 20:
		new_pos = _pick_random_position()
		attempts += 1

	_begin_move(new_pos)

	# Sync the chosen position to all clients
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_move_position.rpc(new_pos)


## RPC: Server tells clients where the base is moving.
@rpc("authority", "call_remote", "reliable")
func _sync_move_position(pos: Vector3) -> void:
	_begin_move(pos)


## Internal: start moving to a specific position.
func _begin_move(new_pos: Vector3) -> void:
	_target_position = new_pos
	_target_position.y = _base_y
	_is_moving = true
	started_moving.emit(_target_position)
	print("Base moving to: (%.1f, %.1f, %.1f)" % [_target_position.x, _base_y, _target_position.z])


## Moves the base to a specific position.
func move_to_position(pos: Vector3) -> void:
	_target_position = pos
	_target_position.y = _base_y
	_is_moving = true
	started_moving.emit(_target_position)


func _pick_random_position() -> Vector3:
	return Vector3(
		randf_range(bounds_min.x, bounds_max.x),
		_base_y,
		randf_range(bounds_min.z, bounds_max.z)
	)


# ── Health ────────────────────────────────────────────────────────────────────

## In multiplayer, damage is applied on the server and synced to clients.
func take_damage(amount: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		# Clients should request damage via RPC to the server.
		_request_damage.rpc_id(1, amount)
		return
	_apply_damage(amount)


@rpc("any_peer", "reliable")
func _request_damage(amount: float) -> void:
	# Server-side: apply the damage.
	_apply_damage(amount)


func _apply_damage(amount: float) -> void:
	if current_health <= 0.0:
		return # Already destroyed

	current_health -= amount
	current_health = max(current_health, 0.0)
	health_changed.emit(current_health, max_health)

	print("Base took %.1f damage! HP: %.1f / %.1f" % [amount, current_health, max_health])

	# Flash red on damage
	_flash_damage()

	# Sync health to all clients
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_health.rpc(current_health, max_health)

	if current_health <= 0.0:
		print(">>> BASE DESTROYED! <<<")
		base_destroyed.emit()


func heal(amount: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_heal.rpc_id(1, amount)
		return
	_apply_heal(amount)


@rpc("any_peer", "reliable")
func _request_heal(amount: float) -> void:
	_apply_heal(amount)


func _apply_heal(amount: float) -> void:
	if current_health <= 0.0:
		return # Can't heal a destroyed base
	if current_health >= max_health:
		return # Already full

	current_health += amount
	current_health = min(current_health, max_health)
	health_changed.emit(current_health, max_health)

	# Flash green briefly
	_flash_heal()

	# Sync health to all clients
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_health.rpc(current_health, max_health)


## Server broadcasts health state to all clients.
@rpc("authority", "call_remote", "reliable")
func _sync_health(hp: float, max_hp: float) -> void:
	current_health = hp
	max_health = max_hp
	health_changed.emit(current_health, max_health)


# ── Visual effects ────────────────────────────────────────────────────────────

func _flash_damage() -> void:
	if _mesh == null:
		return

	_flash_timer = damage_flash_duration

	var mat = _mesh.get_active_material(0)
	if mat is StandardMaterial3D:
		mat.albedo_color = Color(1.0, 0.2, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.1, 0.1)
		mat.emission_energy_multiplier = 3.0
	else:
		var new_mat = StandardMaterial3D.new()
		new_mat.albedo_color = Color(1.0, 0.2, 0.2)
		new_mat.emission_enabled = true
		new_mat.emission = Color(1.0, 0.1, 0.1)
		new_mat.emission_energy_multiplier = 3.0
		_mesh.set_surface_override_material(0, new_mat)


func _flash_heal() -> void:
	if _mesh == null:
		return

	_flash_timer = damage_flash_duration

	var mat = _mesh.get_active_material(0)
	if mat is StandardMaterial3D:
		mat.albedo_color = Color(0.2, 1.0, 0.3)
		mat.emission_enabled = true
		mat.emission = Color(0.1, 1.0, 0.2)
		mat.emission_energy_multiplier = 2.0


func _reset_material_color() -> void:
	if _mesh == null:
		return
	var mat = _mesh.get_active_material(0)
	if mat is StandardMaterial3D:
		mat.albedo_color = _original_color
		mat.emission_enabled = _original_emission_enabled
		mat.emission = _original_emission
		mat.emission_energy_multiplier = _original_emission_energy
