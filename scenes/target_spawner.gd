extends Node3D

## Spawns targets at regular intervals that fly across the area.
## Place this node in your scene and point it where you want targets to originate.

@export var target_scene: PackedScene
@export var spawn_interval: float = 10.0 ## Seconds between spawns.
@export var target_speed: float = 5.0 ## How fast the targets fly.
@export var spawn_height_min: float = 3.0 ## Minimum height above this node's Y.
@export var spawn_height_max: float = 10.0 ## Maximum height above this node's Y.
@export var spread: float = 0.0 ## Random offset on the perpendicular axis.

var _timer: float = 0.0


func _process(delta: float) -> void:
	if get_tree().paused:
		return

	# In multiplayer, only the server runs the spawn timer
	# (WaveManager controls it, and WaveManager is server-only).
	# Clients receive spawn events via RPC.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_timer += delta
	if _timer >= spawn_interval:
		_timer = 0.0
		_spawn_target()


func _spawn_target() -> void:
	if target_scene == null:
		return

	var target = target_scene.instantiate()
	get_tree().current_scene.add_child(target)

	# Spawn at this node's position with some random height and spread
	var spawn_pos = global_position
	spawn_pos.y += randf_range(spawn_height_min, spawn_height_max)
	spawn_pos.x += randf_range(-spread, spread)
	target.global_position = spawn_pos

	# Fly along the spawner's forward direction (-Z in local space)
	var dir = - global_transform.basis.z.normalized()
	target.direction = dir
	target.speed = target_speed

	print("Target spawned at ", spawn_pos)

	# In multiplayer, tell all clients to also spawn this target
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_remote_spawn_target.rpc(spawn_pos, dir, target_speed)


## Called via RPC on clients to spawn a matching target.
@rpc("authority", "call_remote", "reliable")
func _remote_spawn_target(pos: Vector3, dir: Vector3, spd: float) -> void:
	if target_scene == null:
		return
	var target = target_scene.instantiate()
	get_tree().current_scene.add_child(target)
	target.global_position = pos
	target.direction = dir
	target.speed = spd
	print("Target spawned (from server) at ", pos)
