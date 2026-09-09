class_name Arena
extends RefCounted

## Shared play-field geometry.
##
## The arena matches the project's base viewport (see `display/window/size` in
## project.godot). Keeping it as a constant instead of querying the viewport
## makes wrap-around behaviour identical no matter how the window is stretched.

const SIZE := Vector2(1280.0, 720.0)
const CENTER := Vector2(640.0, 360.0)

## Scene-tree group every live rock joins, so systems can find asteroids
## without knowing where in the tree they were parented.
const ASTEROID_GROUP := &"asteroids"

## Wraps a world position around the arena. `margin` lets a sprite travel fully
## off-screen before it reappears on the opposite edge.
static func wrap(position: Vector2, margin: float) -> Vector2:
	var span := SIZE + Vector2(margin, margin) * 2.0
	return Vector2(
		fposmod(position.x + margin, span.x) - margin,
		fposmod(position.y + margin, span.y) - margin
	)


## Returns a point on the arena border, chosen deterministically from `rng`.
static func random_border_point(rng: RandomNumberGenerator) -> Vector2:
	match rng.randi_range(0, 3):
		0:
			return Vector2(rng.randf_range(0.0, SIZE.x), 0.0)
		1:
			return Vector2(rng.randf_range(0.0, SIZE.x), SIZE.y)
		2:
			return Vector2(0.0, rng.randf_range(0.0, SIZE.y))
		_:
			return Vector2(SIZE.x, rng.randf_range(0.0, SIZE.y))
