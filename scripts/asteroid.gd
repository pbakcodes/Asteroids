class_name Asteroid
extends Area2D

## A drifting, spinning rock. Sizes are ordered smallest-first so that
## `size_index - 1` is always the next size down produced by a split.

enum Size { SMALL, MEDIUM, LARGE }

signal destroyed(asteroid: Asteroid)

const WRAP_MARGIN := 36.0

const TEXTURES := [
	preload("res://assets/sprites/asteroid_small.png"),
	preload("res://assets/sprites/asteroid_medium.png"),
	preload("res://assets/sprites/asteroid_large.png"),
]
const RADII := [9.0, 16.0, 26.0]
const BASE_SPEEDS := [118.0, 84.0, 56.0]
const SPIN_SPEEDS := [2.1, 1.4, 0.85]
const POINTS := [100, 50, 20]
const SPEED_JITTER := Vector2(0.85, 1.2)

var size_index := Size.LARGE
var velocity := Vector2.ZERO
var spin := 0.0

var _destroyed := false


## Rolls the launch velocity for a rock that has not been instantiated yet.
## Keeping the random draw separate from the node lets the caller resolve a
## spawn the moment it is requested and build the node later, so nothing
## touches the physics server while it is flushing collision callbacks.
static func roll_velocity(for_size: int, heading: float, rng: RandomNumberGenerator) -> Vector2:
	var speed: float = BASE_SPEEDS[for_size] * rng.randf_range(SPEED_JITTER.x, SPEED_JITTER.y)
	return Vector2.RIGHT.rotated(heading) * speed


## Rolls the spin that pairs with `roll_velocity`; call it straight after so the
## RNG stream stays in a fixed, reproducible order.
static func roll_spin(for_size: int, rng: RandomNumberGenerator) -> float:
	return SPIN_SPEEDS[for_size] * (1.0 if rng.randf() < 0.5 else -1.0)


## Must be called before the asteroid enters the tree.
func configure(new_size: int, spawn_position: Vector2, new_velocity: Vector2, new_spin: float) -> void:
	size_index = clampi(new_size, Size.SMALL, Size.LARGE)
	position = spawn_position
	velocity = new_velocity
	spin = new_spin


func _ready() -> void:
	add_to_group(Arena.ASTEROID_GROUP)

	var sprite: Sprite2D = $Sprite2D
	sprite.texture = TEXTURES[size_index]

	var shape := CircleShape2D.new()
	shape.radius = RADII[size_index]
	var collision: CollisionShape2D = $CollisionShape2D
	collision.shape = shape


func _physics_process(delta: float) -> void:
	global_position = Arena.wrap(global_position + velocity * delta, WRAP_MARGIN)
	rotation += spin * delta


func points() -> int:
	return POINTS[size_index]


func can_split() -> bool:
	return size_index > Size.SMALL


## Destroys the asteroid once, even if two bullets connect on the same frame.
##
## Leaving the group here rather than waiting for `queue_free()` keeps the
## "field cleared" test honest: a rock scheduled for deletion is already gone as
## far as wave tracking is concerned.
func take_hit() -> void:
	if _destroyed:
		return
	_destroyed = true
	remove_from_group(Arena.ASTEROID_GROUP)
	destroyed.emit(self)
	queue_free()
