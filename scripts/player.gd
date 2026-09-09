class_name Player
extends Area2D

## Player ship: rotation, thrust with inertia, a capped top speed and a short
## fire cooldown. The ship never destroys itself; it reports hits through
## `died` and waits for the game manager to call `respawn()`.

signal fired(muzzle_position: Vector2, direction: Vector2)
signal died

const ROTATION_SPEED := 3.4
const THRUST_ACCELERATION := 470.0
const MAX_SPEED := 430.0
const LINEAR_DAMPING := 0.6
const FIRE_COOLDOWN := 0.17
const MUZZLE_OFFSET := 20.0
const INVULNERABLE_TIME := 2.0
const WRAP_MARGIN := 24.0

var velocity := Vector2.ZERO

var _fire_cooldown := 0.0
var _invulnerable_time := 0.0
var _active := true

@onready var _thrust_sprite: Sprite2D = $Thrust


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	respawn(Arena.CENTER)


func is_active() -> bool:
	return _active


func is_invulnerable() -> bool:
	return _invulnerable_time > 0.0


## Places the ship back in play, stationary and briefly invulnerable.
func respawn(spawn_position: Vector2) -> void:
	global_position = spawn_position
	rotation = -PI / 2.0
	velocity = Vector2.ZERO
	_fire_cooldown = 0.0
	_invulnerable_time = INVULNERABLE_TIME
	_active = true
	visible = true
	_thrust_sprite.visible = false


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_advance_timers(delta)
	_steer(delta)
	_move(delta)
	_try_fire()
	_update_blink()


func _advance_timers(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	_invulnerable_time = maxf(_invulnerable_time - delta, 0.0)


func _steer(delta: float) -> void:
	var turn := Input.get_axis("rotate_left", "rotate_right")
	rotation += turn * ROTATION_SPEED * delta

	var thrusting := Input.is_action_pressed("thrust")
	_thrust_sprite.visible = thrusting
	if thrusting:
		velocity += Vector2.RIGHT.rotated(rotation) * THRUST_ACCELERATION * delta
	else:
		velocity = velocity.lerp(Vector2.ZERO, LINEAR_DAMPING * delta)
	velocity = velocity.limit_length(MAX_SPEED)


func _move(delta: float) -> void:
	global_position = Arena.wrap(global_position + velocity * delta, WRAP_MARGIN)


func _try_fire() -> void:
	if _fire_cooldown > 0.0 or not Input.is_action_pressed("fire"):
		return
	_fire_cooldown = FIRE_COOLDOWN
	var direction := Vector2.RIGHT.rotated(rotation)
	fired.emit(global_position + direction * MUZZLE_OFFSET, direction)


func _update_blink() -> void:
	modulate.a = 1.0 if _invulnerable_time <= 0.0 else 0.35 + 0.65 * absf(sin(_invulnerable_time * 14.0))


func _on_area_entered(area: Area2D) -> void:
	if not _active or is_invulnerable() or not area is Asteroid:
		return
	_active = false
	visible = false
	_thrust_sprite.visible = false
	velocity = Vector2.ZERO
	modulate.a = 1.0
	died.emit()
