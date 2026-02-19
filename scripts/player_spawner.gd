extends Node

## Handles spawning and despawning player Pawns in multiplayer.
## Attach this to the Main scene. It will:
##  • In multiplayer: remove the default Pawn and spawn one per connected player.
##  • In singleplayer: leave the existing Pawn untouched.

@export var pawn_scene: PackedScene ## Assign the Pawn.tscn scene here.
@export var spawn_points: Array[Vector3] = [
	Vector3(0, 2.8, 0),
	Vector3(5, 2.8, -5),
	Vector3(-5, 2.8, -5),
	Vector3(0, 2.8, -10),
]

var _spawned_pawns: Dictionary = {} ## peer_id -> Pawn node


func _ready() -> void:
	if not NetworkManager.is_multiplayer_active():
		# Single player — the default Pawn in the scene handles everything.
		return

	# ── Multiplayer setup ─────────────────────────────────────────────────
	# Remove the default singleplayer Pawn from the scene
	var default_pawn = get_parent().get_node_or_null("Pawn")
	if default_pawn:
		default_pawn.queue_free()

	# Load pawn scene if not exported
	if pawn_scene == null:
		pawn_scene = load("res://addons/GoldGdt/Pawn.tscn")

	# Wait a frame for the default pawn to be freed
	await get_tree().process_frame

	# Spawn a pawn for each connected player
	for peer_id in NetworkManager.players:
		_spawn_player(peer_id)

	# Listen for future connections/disconnections
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	# Tell the server we've finished loading
	NetworkManager.player_loaded.rpc_id(1)


func _spawn_player(peer_id: int) -> void:
	if _spawned_pawns.has(peer_id):
		return # Already spawned

	var pawn = pawn_scene.instantiate()
	pawn.name = "Player_%d" % peer_id

	# Set multiplayer authority before add_child (for MultiplayerSynchronizer)
	pawn.set_multiplayer_authority(peer_id)

	# Add to scene tree — this triggers _ready() on all child nodes
	get_parent().add_child(pawn)

	# ── Determine if this pawn belongs to the local player ────────────────
	var is_local = (peer_id == multiplayer.get_unique_id())

	if not is_local:
		# This is a REMOTE player's pawn — disable input/camera/physics
		# by calling configure_for_remote() on each component.
		# This is 100% reliable because it's a simple function call,
		# not dependent on Godot's multiplayer authority timing.
		pawn.configure_for_remote()

		var controls = pawn.get_node_or_null("User Input")
		if controls and controls.has_method("configure_for_remote"):
			controls.configure_for_remote()

		var body = pawn.get_node_or_null("Body")
		if body and body.has_method("configure_for_remote"):
			body.configure_for_remote()

		var view = pawn.get_node_or_null("View Control")
		if view and view.has_method("configure_for_remote"):
			view.configure_for_remote()

		var camera = pawn.get_node_or_null("Interpolated Camera")
		if camera and camera.has_method("configure_for_remote"):
			camera.configure_for_remote()

	# Position at a spawn point
	var spawn_idx = _spawned_pawns.size() % spawn_points.size()
	var body_node = pawn.get_node_or_null("Body")
	if body_node:
		body_node.global_position = spawn_points[spawn_idx]
	else:
		pawn.global_position = spawn_points[spawn_idx]

	_spawned_pawns[peer_id] = pawn
	print("Spawned %s pawn for player %d at spawn point %d" % [
		"LOCAL" if is_local else "REMOTE", peer_id, spawn_idx
	])


func _despawn_player(peer_id: int) -> void:
	if _spawned_pawns.has(peer_id):
		var pawn = _spawned_pawns[peer_id]
		if is_instance_valid(pawn):
			pawn.queue_free()
		_spawned_pawns.erase(peer_id)
		print("Despawned pawn for player %d" % peer_id)


func _on_player_connected(peer_id: int, _info: Dictionary) -> void:
	if multiplayer.is_server():
		_spawn_player(peer_id)


func _on_player_disconnected(peer_id: int) -> void:
	_despawn_player(peer_id)


func _on_server_disconnected() -> void:
	for peer_id in _spawned_pawns.keys():
		_despawn_player(peer_id)
