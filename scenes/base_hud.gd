extends CanvasLayer

## HUD that displays the base's health bar, wave info, and game-over state.
## Automatically finds the "Base" and "WaveManager" nodes in the scene.

@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthLabel
@onready var wave_label: Label = $WaveInfo/WaveLabel
@onready var enemies_label: Label = $WaveInfo/EnemiesLabel
@onready var countdown_label: Label = $CountdownLabel
@onready var heal_bar_container: VBoxContainer = $HealBarContainer
@onready var heal_bar: ProgressBar = $HealBarContainer/HealBar
@onready var heal_prompt_label: Label = $HealBarContainer/HealPromptLabel
@onready var game_over_panel: PanelContainer = $GameOverPanel
@onready var game_over_label: Label = $GameOverPanel/MarginContainer/VBoxContainer/GameOverLabel
@onready var restart_button: Button = $GameOverPanel/MarginContainer/VBoxContainer/RestartButton

var _base_node: Node = null
var _wave_manager: Node = null
var _heal_stations: Array[Node] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 98 # Below crosshair (99), above everything else

	game_over_panel.visible = false
	countdown_label.visible = false
	heal_bar_container.visible = false

	restart_button.pressed.connect(_on_restart_pressed)

	# Find nodes — defer so scene is fully loaded
	call_deferred("_find_nodes")


func _find_nodes() -> void:
	# ── Find Base ──────────────────────────────────────────────────────────
	_base_node = get_tree().current_scene.find_child("Base", true, false)
	if _base_node == null:
		push_warning("BaseHUD: No node named 'Base' found in scene!")
	else:
		if _base_node.has_signal("health_changed"):
			_base_node.health_changed.connect(_on_health_changed)
		if _base_node.has_signal("base_destroyed"):
			_base_node.base_destroyed.connect(_on_base_destroyed)
		if _base_node.has_signal("started_moving"):
			_base_node.started_moving.connect(_on_base_moving)

		# Initialize the bar
		health_bar.max_value = _base_node.max_health
		health_bar.value = _base_node.current_health
		_update_health_label(_base_node.current_health, _base_node.max_health)

	# ── Find Wave Manager ──────────────────────────────────────────────────
	_wave_manager = get_tree().current_scene.find_child("WaveManager", true, false)
	if _wave_manager == null:
		push_warning("BaseHUD: No 'WaveManager' found — wave info hidden.")
		wave_label.text = ""
		enemies_label.text = ""
	else:
		if _wave_manager.has_signal("wave_started"):
			_wave_manager.wave_started.connect(_on_wave_started)
		if _wave_manager.has_signal("wave_completed"):
			_wave_manager.wave_completed.connect(_on_wave_completed)
		if _wave_manager.has_signal("enemy_killed"):
			_wave_manager.enemy_killed.connect(_on_enemy_killed)
		if _wave_manager.has_signal("countdown_tick"):
			_wave_manager.countdown_tick.connect(_on_countdown_tick)

		# Initial state
		wave_label.text = "WAVE: –"
		enemies_label.text = "GET READY..."

	# ── Find Heal Stations ────────────────────────────────────────────────
	_find_heal_stations()


func _find_heal_stations() -> void:
	# Find all heal stations in the scene
	var scene_root = get_tree().current_scene
	for child in scene_root.get_children():
		if child.has_signal("heal_pool_changed"):
			_heal_stations.append(child)


func _process(_delta: float) -> void:
	if get_tree().paused:
		return

	# Check if any heal station is being channeled
	var any_channeling := false
	var channeling_station: Node = null
	for station in _heal_stations:
		if is_instance_valid(station) and station.is_channeling:
			any_channeling = true
			channeling_station = station
			break

	if any_channeling and channeling_station:
		heal_bar_container.visible = true
		heal_bar.max_value = channeling_station.heal_pool
		heal_bar.value = channeling_station.current_pool
		heal_prompt_label.text = "CHANNELING... [%d / %d]" % [int(channeling_station.current_pool), int(channeling_station.heal_pool)]
	else:
		heal_bar_container.visible = false


# ── Health ────────────────────────────────────────────────────────────────────

func _on_health_changed(current_hp: float, max_hp: float) -> void:
	health_bar.max_value = max_hp
	health_bar.value = current_hp
	_update_health_label(current_hp, max_hp)

	# Color the bar based on HP percentage
	var pct = current_hp / max_hp
	if pct > 0.6:
		health_bar.modulate = Color(0.2, 1.0, 0.3) # Green
	elif pct > 0.3:
		health_bar.modulate = Color(1.0, 0.8, 0.1) # Yellow
	else:
		health_bar.modulate = Color(1.0, 0.2, 0.2) # Red


func _update_health_label(current_hp: float, max_hp: float) -> void:
	health_label.text = "BASE HP: %d / %d" % [int(current_hp), int(max_hp)]


# ── Waves ─────────────────────────────────────────────────────────────────────

func _on_wave_started(wave_number: int, enemy_count: int) -> void:
	wave_label.text = "WAVE: %d" % wave_number
	enemies_label.text = "ENEMIES: %d" % enemy_count
	countdown_label.visible = false

	# Brief flash announcement
	countdown_label.text = "WAVE %d" % wave_number
	countdown_label.visible = true
	# Hide after 2 seconds
	var tween = create_tween()
	tween.tween_interval(2.0)
	tween.tween_callback(func(): countdown_label.visible = false)


func _on_wave_completed(_wave_number: int) -> void:
	enemies_label.text = "WAVE CLEARED!"


func _on_base_moving(_target_pos: Vector3) -> void:
	# Show a brief relocating notice
	countdown_label.text = "BASE RELOCATING..."
	countdown_label.visible = true


func _on_enemy_killed(remaining: int) -> void:
	enemies_label.text = "ENEMIES: %d" % remaining


func _on_countdown_tick(seconds_left: float) -> void:
	if seconds_left > 0.0:
		countdown_label.visible = true
		countdown_label.text = "NEXT WAVE IN: %d" % int(ceil(seconds_left))
	else:
		countdown_label.visible = false


# ── Game Over ─────────────────────────────────────────────────────────────────

func _on_base_destroyed() -> void:
	# Tell wave manager to stop
	if _wave_manager and _wave_manager.has_method("stop"):
		_wave_manager.stop()

	# Show how far they got
	var final_wave = 0
	if _wave_manager:
		final_wave = _wave_manager.current_wave

	game_over_label.text = "BASE DESTROYED\nYou survived %d waves" % final_wave
	game_over_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true


func _on_restart_pressed() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().reload_current_scene()
