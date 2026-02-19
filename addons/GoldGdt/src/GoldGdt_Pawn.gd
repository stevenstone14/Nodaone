@tool
class_name GoldGdt_Pawn extends Node3D

@export_group("Components")
@export var View: GoldGdt_View
@export var Camera: GoldGdt_Camera
@export var rocket_scene: PackedScene

@export_group("Shooting")
@export var shoot_cooldown: float = 0.3 ## Minimum seconds between shots.

@export_group("On Ready")
@export_range(-89, 89) var start_view_pitch: float = 0 ## How the vertical view of the pawn should be rotated on ready. The default value is 0.
@export var start_view_yaw: float = 0 ## How the horizontal view of the pawn should be rotated on ready. The default values is 0.

var _cooldown_timer: float = 0.0
var _whoosh_player: AudioStreamPlayer = null

func _process(delta):
	# Purely for visuals, to show you the camera rotation.
	if Engine.is_editor_hint():
		if View and Camera:
			_override_view_rotation(Vector2(deg_to_rad(start_view_yaw), deg_to_rad(start_view_pitch)))
		return

	# Tick down the cooldown timer
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

func _ready():
	_override_view_rotation(Vector2(deg_to_rad(start_view_yaw), deg_to_rad(start_view_pitch)))

	# Set up whoosh sound for shooting
	_whoosh_player = AudioStreamPlayer.new()
	var whoosh_stream = load("res://sounds/whoosh.wav")
	if whoosh_stream:
		_whoosh_player.stream = whoosh_stream
		_whoosh_player.volume_db = -5.0
	else:
		push_warning("Pawn: Could not load whoosh.wav")
	add_child(_whoosh_player)

	# ── Multiplayer synchronization ──────────────────────────────────────
	# Sync the Body's position and rotation so other clients can see this player move.
	var body_node = get_node_or_null("Body")
	if body_node and multiplayer.has_multiplayer_peer():
		var syncer = MultiplayerSynchronizer.new()
		syncer.name = "PlayerSync"
		# Replication config: sync body transform properties
		var config = SceneReplicationConfig.new()
		config.add_property(NodePath("Body:position"))
		config.add_property(NodePath("Body:rotation"))
		config.add_property(NodePath("Body:velocity"))
		# Also sync the horizontal view rotation so remote players look correct
		var h_view = get_node_or_null("Body/Horizontal View")
		if h_view:
			config.add_property(NodePath("Body/Horizontal View:rotation"))
		var v_view = get_node_or_null("Body/Horizontal View/Vertical View")
		if v_view:
			config.add_property(NodePath("Body/Horizontal View/Vertical View:rotation"))
		syncer.replication_config = config
		# CRITICAL: Set the syncer's authority to match the pawn's authority.
		# Without this, the syncer defaults to authority=1 (server), which means
		# on the CLIENT, the syncer thinks it should RECEIVE data — it overwrites
		# the client's own Body position every frame, preventing all movement.
		syncer.set_multiplayer_authority(get_multiplayer_authority())
		add_child(syncer)

## Set to false by PlayerSpawner for remote players' pawns.
var is_local_player: bool = true


## Called by PlayerSpawner to disable this node for remote players.
func configure_for_remote() -> void:
	is_local_player = false
	set_process_unhandled_input(false)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not is_local_player:
		return
	if get_tree().paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_shoot_rocket()

func _shoot_rocket() -> void:
	if rocket_scene == null:
		return
	if _cooldown_timer > 0.0:
		return

	_cooldown_timer = shoot_cooldown

	# Play whoosh sound
	if _whoosh_player and _whoosh_player.stream:
		_whoosh_player.play()

	# Get the actual Camera3D node to determine position and direction
	var cam: Camera3D = Camera.get_node("Arm/Arm Anchor/Camera")

	# Calculate the spawn transform
	var spawn_xform = cam.global_transform
	var spawn_pos = spawn_xform.origin + (-spawn_xform.basis.z * 1.0)
	var spawn_rot = spawn_xform.basis.get_euler()

	# Determine who owns this rocket (for self-boost detection)
	var my_peer_id: int = -1
	if multiplayer.has_multiplayer_peer():
		my_peer_id = multiplayer.get_unique_id()

	# Spawn the rocket locally
	_do_spawn_rocket(spawn_pos, spawn_rot, my_peer_id)

	# In multiplayer, tell all other peers to also spawn this rocket
	if multiplayer.has_multiplayer_peer():
		_remote_spawn_rocket.rpc(spawn_pos, spawn_rot, my_peer_id)


## Called via RPC on remote peers to show this player's rocket.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _remote_spawn_rocket(pos: Vector3, rot: Vector3, peer_id: int = -1) -> void:
	_do_spawn_rocket(pos, rot, peer_id)


## Actually instantiate and place the rocket in the scene.
func _do_spawn_rocket(pos: Vector3, rot: Vector3, peer_id: int = -1) -> void:
	var rocket = rocket_scene.instantiate()
	get_tree().current_scene.add_child(rocket)

	rocket.global_position = pos
	rocket.global_rotation = rot
	# Rotate 180° to fix Blender model facing +Z vs Godot's -Z forward
	rocket.rotate_object_local(Vector3.UP, PI)

	# Set the owner peer ID on the rocket for self-boost detection
	if rocket.has_method("set") or "owner_peer_id" in rocket:
		rocket.owner_peer_id = peer_id


## Called via RPC by a rocket explosion to apply boost to this pawn's body.
## Only the authoritative peer (the player who owns this pawn) runs this.
@rpc("any_peer", "call_remote", "reliable")
func _receive_rocket_boost(impulse: Vector3) -> void:
	var body_node = get_node_or_null("Body")
	if body_node and body_node.has_method("apply_rocket_boost"):
		body_node.apply_rocket_boost(impulse)
		print("Received rocket boost via RPC: ", impulse)

## Forces camera rotation based on a Vector2 containing yaw and pitch, in degrees.
func _override_view_rotation(rotation: Vector2) -> void:
	View.horizontal_view.rotation.y = rotation.x
	View.horizontal_view.orthonormalize()
	
	View.vertical_view.rotation.x = rotation.y
	View.vertical_view.orthonormalize()
	
	View.vertical_view.rotation.x = clamp(View.vertical_view.rotation.x, deg_to_rad(-89), deg_to_rad(89))
	View.vertical_view.orthonormalize()
	
	Camera.global_rotation = View.camera_mount.global_rotation
	Camera.orthonormalize()
