extends Area3D

## A flying target that navigates toward the Base.
## Tower-defense style: it flies toward the base, deals damage on arrival,
## and destroys itself. Can be shot down mid-flight by rockets.

signal target_destroyed

@export var speed: float = 12.0
@export var lifetime: float = 60.0
@export var damage: float = 10.0 ## Damage dealt to the base on arrival.
@export var arrival_distance: float = 3.0 ## How close before it "hits" the base.
@export_group("Homing")
@export var turn_speed: float = 2.0 ## How fast the target rotates toward the base (radians/sec). Higher = sharper turns.
@export var homing_delay: float = 1.5 ## Seconds of straight-line flight before homing kicks in.

var direction: Vector3 = Vector3.FORWARD
var _timer: float = 0.0
var _base_node: Node3D = null
var _homing_active: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Find the base in the scene
	call_deferred("_find_base")


func _find_base() -> void:
	_base_node = get_tree().current_scene.find_child("Base", true, false)
	if _base_node == null:
		push_warning("Target: No 'Base' node found — flying straight.")


func _process(delta: float) -> void:
	_timer += delta

	# After the homing delay, start turning toward the base
	if not _homing_active and _timer >= homing_delay:
		_homing_active = true

	if _homing_active and _base_node != null and is_instance_valid(_base_node):
		_home_toward_base(delta)

	# Move along current direction
	global_position += direction * speed * delta

	# Rotate the mesh to face the movement direction (visual polish)
	if direction.length_squared() > 0.001:
		var target_basis = Basis.looking_at(direction, Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(target_basis, delta * 5.0)

	# Check if arrived at base
	if _base_node != null and is_instance_valid(_base_node):
		var dist = global_position.distance_to(_base_node.global_position + Vector3(0, 1.5, 0))
		if dist <= arrival_distance:
			_attack_base()
			return

	# Lifetime expiry
	if _timer >= lifetime:
		queue_free()


func _home_toward_base(delta: float) -> void:
	# Calculate desired direction toward the base (aim at center mass)
	var base_center = _base_node.global_position + Vector3(0, 1.5, 0)
	var desired_dir = (base_center - global_position).normalized()

	# Smoothly rotate direction toward the base
	direction = direction.normalized().slerp(desired_dir, turn_speed * delta).normalized()


func _attack_base() -> void:
	if _base_node.has_method("take_damage"):
		_base_node.take_damage(damage)
		print(">> Target attacked base for %.1f damage! <<" % damage)
	_destroy()


func _on_body_entered(body: Node3D) -> void:
	print("Target hit by body: ", body.name)
	_destroy()


func _on_area_entered(area: Area3D) -> void:
	print("Target hit by area: ", area.name)
	_destroy()


func _destroy() -> void:
	print(">> Target destroyed! <<")
	target_destroyed.emit()
	queue_free()
