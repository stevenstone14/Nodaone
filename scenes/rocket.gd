extends Area3D

@export var speed: float = 30.0
@export var lifetime: float = 20.0

## ── Rocket Boost (Quake-style) ──────────────────────────────────────────────
@export_group("Rocket Boost")
@export var blast_radius: float = 8.0 ## How far the explosion reaches.
@export var blast_force: float = 22.0 ## Maximum horizontal boost speed.
@export var blast_vertical_force: float = 14.0 ## Maximum upward boost.
@export var self_boost_multiplier: float = 1.0 ## Multiplier for self-damage boost (1.0 = full).

var _timer: float = 0.0
var _explode_stream: AudioStream = null
var _has_exploded: bool = false

## The peer_id of the player who fired this rocket (set by GoldGdt_Pawn).
var owner_peer_id: int = -1


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Preload the explosion sound
	_explode_stream = load("res://sounds/explode.wav")
	if _explode_stream == null:
		push_warning("Rocket: Could not load explode.wav")


func _process(delta: float) -> void:
	# Move forward along +Z (the mesh faces +Z, and the root is rotated 180°
	# at spawn so +Z aligns with the camera's forward direction)
	global_position += global_transform.basis.z * speed * delta

	_timer += delta
	if _timer >= lifetime:
		print("Rocket expired (%.1fs)" % lifetime)
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	print("Rocket hit body: ", body.name, " (", body.get_class(), ")")
	_explode()


func _on_area_entered(area: Area3D) -> void:
	print("Rocket hit area: ", area.name, " (", area.get_class(), ")")

	# Destroy whatever we hit
	if area.has_method("_destroy"):
		area._destroy()
	else:
		area.queue_free()

	_explode()


## Handles the explosion: plays sound, applies blast boost to nearby players,
## and frees the rocket.
func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true

	var explosion_pos = global_position

	# Play explosion sound at impact position
	_play_explosion_at(explosion_pos)

	# Apply rocket boost to all players in blast radius
	_apply_blast_to_nearby_players(explosion_pos)

	queue_free()


## Finds all GoldGdt_Body nodes in the scene and applies a velocity boost
## to any within the blast radius. The boost direction goes FROM the explosion
## TO the player, with a slight upward bias (like Quake).
func _apply_blast_to_nearby_players(explosion_pos: Vector3) -> void:
	var bodies = _find_all_player_bodies(get_tree().current_scene)

	for body in bodies:
		if not is_instance_valid(body):
			continue

		# Distance from explosion to the player's feet/center
		var player_pos = body.global_position
		var dist = explosion_pos.distance_to(player_pos)

		if dist > blast_radius:
			continue

		# Calculate falloff (1.0 at center, 0.0 at edge)
		var falloff = 1.0 - (dist / blast_radius)
		falloff = clampf(falloff, 0.0, 1.0)
		# Quadratic falloff feels more natural
		falloff = falloff * falloff

		# Direction from explosion to player (the "push" direction)
		var push_dir: Vector3
		if dist < 0.01:
			# Rocket exploded right on the player — push straight up
			push_dir = Vector3.UP
		else:
			push_dir = (player_pos - explosion_pos).normalized()

		# Add a strong upward bias for that classic rocket-jump feel
		push_dir.y = max(push_dir.y, 0.4)
		push_dir = push_dir.normalized()

		# Calculate the boost impulse
		var horizontal_boost = blast_force * falloff
		var vertical_boost = blast_vertical_force * falloff

		var impulse = Vector3(
			push_dir.x * horizontal_boost,
			push_dir.y * vertical_boost,
			push_dir.z * horizontal_boost
		)

		# Apply self-boost multiplier if this is the shooter's own body
		if _is_owners_body(body):
			impulse *= self_boost_multiplier

		# Apply the boost — only the authority for this body should do it
		_apply_boost_to_body(body, impulse)


## Check if the given body belongs to the player who fired this rocket.
func _is_owners_body(body: GoldGdt_Body) -> bool:
	if owner_peer_id < 0:
		return true # Singleplayer — always self-boost
	# The body's parent Pawn node has the multiplayer authority set to the peer id
	var pawn = body.get_parent()
	if pawn:
		return pawn.get_multiplayer_authority() == owner_peer_id
	return false


## Apply the velocity boost to a player body. In multiplayer, uses RPC so
## the authoritative client gets the boost.
func _apply_boost_to_body(body: GoldGdt_Body, impulse: Vector3) -> void:
	if not multiplayer.has_multiplayer_peer():
		# Singleplayer — just apply directly
		body.apply_rocket_boost(impulse)
		return

	# In multiplayer, the body's authority is the player who owns it.
	# We need to tell THAT client to apply the boost.
	var pawn = body.get_parent()
	if not pawn:
		return

	var authority_id = pawn.get_multiplayer_authority()

	if authority_id == multiplayer.get_unique_id():
		# We are the authority — apply locally
		body.apply_rocket_boost(impulse)
	else:
		# Tell the authority to apply the boost via RPC on the Pawn
		if pawn.has_method("_receive_rocket_boost"):
			pawn._receive_rocket_boost.rpc_id(authority_id, impulse)


## Recursively find all GoldGdt_Body nodes in the scene tree.
func _find_all_player_bodies(node: Node) -> Array:
	var result: Array = []
	if node is GoldGdt_Body:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_all_player_bodies(child))
	return result


## Spawns a one-shot AudioStreamPlayer3D at the given position.
## It parents itself to the scene root so it persists after the rocket is freed.
func _play_explosion_at(pos: Vector3) -> void:
	if _explode_stream == null:
		return

	var audio = AudioStreamPlayer3D.new()
	audio.stream = _explode_stream
	audio.volume_db = 0.0
	audio.max_distance = 100.0
	get_tree().current_scene.add_child(audio)
	audio.global_position = pos
	audio.play()
	# Auto-free after the sound finishes
	audio.finished.connect(audio.queue_free)
