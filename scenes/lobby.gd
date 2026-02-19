extends Control

## Lobby scene for hosting/joining multiplayer games.
## Builds the entire UI programmatically for maintainability.

# ── UI References ─────────────────────────────────────────────────────────────
var _title_label: Label
var _name_input: LineEdit
var _host_button: Button
var _ip_input: LineEdit
var _port_input: LineEdit
var _join_button: Button
var _player_list: ItemList
var _start_button: Button
var _back_button: Button
var _status_label: Label
var _singleplayer_button: Button

# ── State ─────────────────────────────────────────────────────────────────────
var _in_lobby: bool = false ## True when we're connected and waiting in the lobby.


func _ready() -> void:
	_build_ui()
	_connect_signals()
	_update_ui_state()


func _build_ui() -> void:
	# ── Background ────────────────────────────────────────────────────────
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# ── Center container ──────────────────────────────────────────────────
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# ── Main panel ────────────────────────────────────────────────────────
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 600)

	# Style the panel
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.18, 0.95)
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.3, 0.4, 0.9, 0.6)
	panel_style.shadow_color = Color(0.1, 0.1, 0.3, 0.5)
	panel_style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	# ── Margin inside panel ───────────────────────────────────────────────
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 25)
	margin.add_theme_constant_override("margin_bottom", 25)
	panel.add_child(margin)

	# ── VBox for all content ──────────────────────────────────────────────
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# ── Title ─────────────────────────────────────────────────────────────
	_title_label = Label.new()
	_title_label.text = "NODAONE"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.add_theme_color_override("font_color", Color(0.5, 0.6, 1.0))
	vbox.add_child(_title_label)

	var subtitle = Label.new()
	subtitle.text = "MULTIPLAYER LOBBY"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	vbox.add_child(subtitle)

	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size.y = 8
	vbox.add_child(spacer1)

	# ── Player Name ───────────────────────────────────────────────────────
	var name_label = Label.new()
	name_label.text = "YOUR NAME"
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	vbox.add_child(name_label)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Enter your name..."
	_name_input.text = "Player"
	_name_input.custom_minimum_size.y = 36
	vbox.add_child(_name_input)

	# ── Connection section ────────────────────────────────────────────────
	var conn_label = Label.new()
	conn_label.text = "CONNECTION"
	conn_label.add_theme_font_size_override("font_size", 12)
	conn_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	vbox.add_child(conn_label)

	# IP + Port row
	var ip_row = HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 8)
	vbox.add_child(ip_row)

	_ip_input = LineEdit.new()
	_ip_input.placeholder_text = "IP Address (e.g. 127.0.0.1)"
	_ip_input.text = "127.0.0.1"
	_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_input.custom_minimum_size.y = 36
	ip_row.add_child(_ip_input)

	_port_input = LineEdit.new()
	_port_input.placeholder_text = "Port"
	_port_input.text = "7777"
	_port_input.custom_minimum_size = Vector2(80, 36)
	ip_row.add_child(_port_input)

	# Host / Join row
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	_host_button = _create_button("HOST GAME", Color(0.2, 0.7, 0.3))
	_host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(_host_button)

	_join_button = _create_button("JOIN GAME", Color(0.3, 0.5, 0.9))
	_join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(_join_button)

	# ── Singleplayer ──────────────────────────────────────────────────────
	_singleplayer_button = _create_button("PLAY SOLO", Color(0.6, 0.5, 0.2))
	vbox.add_child(_singleplayer_button)

	# ── Player List ───────────────────────────────────────────────────────
	var list_label = Label.new()
	list_label.text = "PLAYERS"
	list_label.add_theme_font_size_override("font_size", 12)
	list_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	vbox.add_child(list_label)

	_player_list = ItemList.new()
	_player_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_player_list.custom_minimum_size.y = 100
	_player_list.auto_height = true
	vbox.add_child(_player_list)

	# ── Status label ──────────────────────────────────────────────────────
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_status_label)

	# ── Bottom buttons ────────────────────────────────────────────────────
	var bottom_row = HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom_row)

	_back_button = _create_button("DISCONNECT", Color(0.7, 0.3, 0.3))
	_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_button.visible = false
	bottom_row.add_child(_back_button)

	_start_button = _create_button("START GAME", Color(0.2, 0.8, 0.4))
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.visible = false
	bottom_row.add_child(_start_button)


func _create_button(text: String, color: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size.y = 40

	var style = StyleBoxFlat.new()
	style.bg_color = color.darkened(0.3)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = color
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = style.duplicate()
	pressed_style.bg_color = color.darkened(0.5)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	return btn


func _connect_signals() -> void:
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_singleplayer_button.pressed.connect(_on_singleplayer_pressed)

	# NetworkManager signals
	NetworkManager.player_connected.connect(_on_player_joined)
	NetworkManager.player_disconnected.connect(_on_player_left)
	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connect_failed)
	NetworkManager.server_disconnected.connect(_on_server_lost)


# ── Button Handlers ───────────────────────────────────────────────────────────

func _on_host_pressed() -> void:
	var player_name = _name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Host"
	NetworkManager.player_info = {"name": player_name}

	var port = _port_input.text.to_int()
	if port <= 0 or port > 65535:
		port = NetworkManager.DEFAULT_PORT

	var error = NetworkManager.host_game(port)
	if error == OK:
		_in_lobby = true
		_status_label.text = "Hosting on port %d — waiting for players..." % port
		_status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
		_update_ui_state()
		_refresh_player_list()
	else:
		_status_label.text = "Failed to start server: %s" % error_string(error)
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))


func _on_join_pressed() -> void:
	var player_name = _name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player"
	NetworkManager.player_info = {"name": player_name}

	var address = _ip_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"

	var port = _port_input.text.to_int()
	if port <= 0 or port > 65535:
		port = NetworkManager.DEFAULT_PORT

	var error = NetworkManager.join_game(address, port)
	if error == OK:
		_status_label.text = "Connecting to %s:%d..." % [address, port]
		_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
		# Disable buttons while connecting
		_host_button.disabled = true
		_join_button.disabled = true
	else:
		_status_label.text = "Failed to connect: %s" % error_string(error)
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))


func _on_start_pressed() -> void:
	if NetworkManager.is_host:
		NetworkManager.start_game()


func _on_back_pressed() -> void:
	NetworkManager.leave_game()
	_in_lobby = false
	_status_label.text = "Disconnected."
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
	_update_ui_state()
	_player_list.clear()


func _on_singleplayer_pressed() -> void:
	# Just go straight to the game with no networking
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# ── Network Event Handlers ────────────────────────────────────────────────────

func _on_player_joined(_peer_id: int, _info: Dictionary) -> void:
	_refresh_player_list()


func _on_player_left(_peer_id: int) -> void:
	_refresh_player_list()


func _on_connected() -> void:
	_in_lobby = true
	_status_label.text = "Connected! Waiting for host to start..."
	_status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
	_update_ui_state()
	_refresh_player_list()


func _on_connect_failed() -> void:
	_in_lobby = false
	_status_label.text = "Connection failed! Check IP and port."
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_update_ui_state()


func _on_server_lost() -> void:
	_in_lobby = false
	_status_label.text = "Server disconnected!"
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_update_ui_state()
	_player_list.clear()


# ── UI Helpers ────────────────────────────────────────────────────────────────

func _update_ui_state() -> void:
	if _in_lobby:
		# In lobby — show player list, hide connection inputs
		_host_button.visible = false
		_join_button.visible = false
		_ip_input.get_parent().visible = false # Hide the IP row
		_singleplayer_button.visible = false
		_name_input.editable = false

		_back_button.visible = true
		_start_button.visible = NetworkManager.is_host # Only host can start
	else:
		# Not in lobby — show connection UI
		_host_button.visible = true
		_join_button.visible = true
		_host_button.disabled = false
		_join_button.disabled = false
		_ip_input.get_parent().visible = true
		_singleplayer_button.visible = true
		_name_input.editable = true

		_back_button.visible = false
		_start_button.visible = false


func _refresh_player_list() -> void:
	_player_list.clear()
	for peer_id in NetworkManager.players:
		var info = NetworkManager.players[peer_id]
		var display_name = info.get("name", "Player %d" % peer_id)
		if peer_id == 1:
			display_name += "  [HOST]"
		if multiplayer.has_multiplayer_peer() and peer_id == multiplayer.get_unique_id():
			display_name += "  (you)"
		_player_list.add_item(display_name)
