extends Node

## Autoload singleton managing multiplayer connections.
## Handles hosting, joining, player tracking, and scene transitions.

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_disconnected
signal connection_failed
signal connection_succeeded
signal all_players_loaded

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4

## Dictionary of peer_id -> player_info for all connected players.
var players: Dictionary = {}

## This player's info — set from the lobby before hosting/joining.
var player_info: Dictionary = {"name": "Player"}

## Whether this peer is the server.
var is_host: bool = false

## Track how many peers have finished loading the game scene.
var _players_loaded: int = 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ── Public API ────────────────────────────────────────────────────────────────

## Creates a server and starts hosting.
func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		push_error("NetworkManager: Failed to create server: %s" % error_string(error))
		return error

	multiplayer.multiplayer_peer = peer
	is_host = true

	# Register the host as a player (host is always peer_id 1)
	players[1] = player_info
	player_connected.emit(1, player_info)

	print("=== SERVER STARTED on port %d ===" % port)
	return OK


## Joins an existing server at the given address.
func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	if error != OK:
		push_error("NetworkManager: Failed to create client: %s" % error_string(error))
		return error

	multiplayer.multiplayer_peer = peer
	is_host = false

	print("=== CONNECTING to %s:%d ===" % [address, port])
	return OK


## Disconnects from the current game and returns to the lobby.
func leave_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
	_players_loaded = 0
	print("=== DISCONNECTED ===")


## Called by the host to start the game for everyone.
func start_game() -> void:
	if not is_host:
		return
	_load_game.rpc()


## Called by each peer when they've finished loading the game scene.
@rpc("any_peer", "call_local", "reliable")
func player_loaded() -> void:
	if not multiplayer.is_server():
		return
	_players_loaded += 1
	if _players_loaded >= players.size():
		all_players_loaded.emit()
		_players_loaded = 0


## Returns true if we are currently connected to a multiplayer session.
func is_multiplayer_active() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


## Get a player's display name by peer ID.
func get_player_name(peer_id: int) -> String:
	if players.has(peer_id):
		return players[peer_id].get("name", "Player %d" % peer_id)
	return "Player %d" % peer_id


# ── RPCs ──────────────────────────────────────────────────────────────────────

## RPC called by the host to tell all peers to load the game scene.
@rpc("authority", "call_local", "reliable")
func _load_game() -> void:
	# Reset the loaded counter before switching
	_players_loaded = 0
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## RPC to register a player's info on all peers.
## Sent when a new player connects so everyone knows about them.
@rpc("any_peer", "reliable")
func _register_player(info: Dictionary) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	players[sender_id] = info
	player_connected.emit(sender_id, info)
	print("Player registered: %d (%s)" % [sender_id, info.get("name", "Unknown")])


## RPC for the server to tell a new client about all existing players.
@rpc("authority", "reliable")
func _sync_player_list(player_data: Dictionary) -> void:
	for peer_id in player_data:
		players[peer_id] = player_data[peer_id]
		player_connected.emit(peer_id, player_data[peer_id])
	print("Synced %d existing players from server." % player_data.size())


# ── Connection Callbacks ──────────────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	# Send our info to the new peer
	_register_player.rpc_id(id, player_info)

	# If we're the server, also send the full player list to the new peer
	if multiplayer.is_server():
		_sync_player_list.rpc_id(id, players)

	print("Peer connected: %d" % id)


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	player_disconnected.emit(id)
	print("Peer disconnected: %d" % id)


func _on_connected_to_server() -> void:
	# We successfully connected — register ourselves
	var my_id = multiplayer.get_unique_id()
	players[my_id] = player_info
	connection_succeeded.emit()
	print("=== CONNECTED to server (my id: %d) ===" % my_id)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()
	print("=== CONNECTION FAILED ===")


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
	server_disconnected.emit()
	print("=== SERVER DISCONNECTED ===")
	# Return to lobby
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
