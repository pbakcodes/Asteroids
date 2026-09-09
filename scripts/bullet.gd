class_name Bullet
extends Area2D

## Short-lived projectile. Wraps like everything else and despawns on its own
## so that missed shots can never leak.

const SPEED := 640.0
const LIFETIME := 1.05
const WRAP_MARGIN := 8.0

var velocity := Vector2.ZERO

var _life := LIFETIME


## Must be called before the bullet enters the tree.
func launch(spawn_position: Vector2, direction: Vector2) -> void:
	position = spawn_position
	velocity = direction.normalized() * SPEED
	rotation = velocity.angle()


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	global_position = Arena.wrap(global_position + velocity * delta, WRAP_MARGIN)


func _on_area_entered(area: Area2D) -> void:
	if not area is Asteroid:
		return
	(area as Asteroid).take_hit()
	queue_free()
