class_name Main
extends Node2D

## Game manager: wave progression, spawning, scoring and lives.
##
## Wave layouts are deterministic: the RNG is reseeded from the wave number at
## the start of every wave, so wave N always opens with the same rocks. Wave
## size is bounded by MAX_WAVE_ASTEROIDS so the field stays playable, and
## spawns are kept outside SAFE_SPAWN_RADIUS of the ship.

const ASTEROID_SCENE := preload("res://scenes/asteroid.tscn")
const BULLET_SCENE := preload("res://scenes/bullet.tscn")

const STARTING_LIVES := 3
const WAVE_SEED_BASE := 20240917
const WAVE_SEED_STRIDE := 7919
const FIRST_WAVE_ASTEROIDS := 3
const MAX_WAVE_ASTEROIDS := 9
const SAFE_SPAWN_RADIUS := 260.0
const SPAWN_ATTEMPTS := 24
const SPLIT_SPREAD := 0.7
const RESPAWN_DELAY := 1.2
const WAVE_DELAY := 1.8


## A spawn that has been fully resolved (position, velocity, spin) but whose
## node has not been built yet.
##
## Splits are requested from `Asteroid.destroyed`, which fires while the physics
## server is flushing its collision callbacks. Instantiating a rock there would
## add a collision shape mid-flush, so the random draws happen immediately —
## keeping the RNG stream deterministic — while node creation is deferred.
class PendingSpawn:
	var size_index: int
	var spawn_position: Vector2
	var velocity: Vector2
	var spin: float


var _score := 0
var _lives := STARTING_LIVES
var _wave := 0
var _game_over := false
var _respawn_timer := 0.0
var _wave_timer := 0.0
var _wave_pending := false

var _rng := RandomNumberGenerator.new()
var _restart_held := false
var _pending_spawns: Array[PendingSpawn] = []
var _spawn_flush_queued := false

@onready var _player: Player = $Player
@onready var _asteroids: Node2D = $Asteroids
@onready var _bullets: Node2D = $Bullets
@onready var _hud: Hud = $HUD


func _ready() -> void:
	_player.fired.connect(_on_player_fired)
	_player.died.connect(_on_player_died)
	_start_game()


func _process(delta: float) -> void:
	if _consume_restart_press():
		_start_game()
		return
	if _game_over:
		return
	_tick_respawn(delta)
	_tick_waves(delta)


## Edge-detects the restart key ourselves instead of using
## `Input.is_action_just_pressed()`, which only reports the single frame the
## press was registered on and can be missed depending on input timing.
func _consume_restart_press() -> bool:
	var held := Input.is_action_pressed("restart")
	var pressed := held and not _restart_held
	_restart_held = held
	return pressed


func _start_game() -> void:
	_score = 0
	_lives = STARTING_LIVES
	_wave = 0
	_game_over = false
	_respawn_timer = 0.0
	_wave_pending = false
	_wave_timer = 0.0

	_clear_container(_asteroids)
	_clear_container(_bullets)
	_pending_spawns.clear()

	_hud.set_score(_score)
	_hud.set_lives(_lives)
	_hud.clear_banner()

	_player.respawn(Arena.CENTER)
	_start_wave()


func _tick_respawn(delta: float) -> void:
	if _respawn_timer <= 0.0:
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_player.respawn(Arena.CENTER)


func _tick_waves(delta: float) -> void:
	if _wave_pending:
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			_wave_pending = false
			_start_wave()
		return
	# Splits are only registered once the deferred flush runs, so a field that
	# merely looks empty right now must not be mistaken for a cleared wave.
	if not _pending_spawns.is_empty():
		return
	if get_tree().get_nodes_in_group(Arena.ASTEROID_GROUP).is_empty():
		_wave_pending = true
		_wave_timer = WAVE_DELAY
		_hud.show_banner("WAVE %d CLEARED" % _wave, WAVE_DELAY * 0.75)


func _start_wave() -> void:
	_wave += 1
	_rng.seed = WAVE_SEED_BASE + _wave * WAVE_SEED_STRIDE
	var count := mini(FIRST_WAVE_ASTEROIDS + _wave - 1, MAX_WAVE_ASTEROIDS)
	for _i in count:
		_queue_spawn(Asteroid.Size.LARGE, _pick_spawn_point(), _rng.randf_range(0.0, TAU))
	_hud.show_banner("WAVE %d" % _wave, 1.3)


func _pick_spawn_point() -> Vector2:
	var reference := _player.global_position if _player.is_active() else Arena.CENTER
	for _attempt in SPAWN_ATTEMPTS:
		var point := Arena.random_border_point(_rng)
		if point.distance_to(reference) >= SAFE_SPAWN_RADIUS:
			return point
	# Bounded fallback: the point diagonally opposite the ship is always the
	# farthest corner-ish spot available, so a cornered player still gets room.
	return Arena.SIZE - reference


## Resolves a spawn now and builds the node once the physics server is idle.
## The RNG is read here, in call order, so wave layouts and split trajectories
## stay bit-for-bit reproducible regardless of when the node is created.
func _queue_spawn(size_index: int, spawn_position: Vector2, heading: float) -> void:
	var request := PendingSpawn.new()
	request.size_index = clampi(size_index, Asteroid.Size.SMALL, Asteroid.Size.LARGE)
	request.spawn_position = spawn_position
	request.velocity = Asteroid.roll_velocity(request.size_index, heading, _rng)
	request.spin = Asteroid.roll_spin(request.size_index, _rng)
	_pending_spawns.append(request)

	if _spawn_flush_queued:
		return
	_spawn_flush_queued = true
	_flush_pending_spawns.call_deferred()


func _flush_pending_spawns() -> void:
	_spawn_flush_queued = false
	var requests := _pending_spawns.duplicate()
	_pending_spawns.clear()
	for request in requests:
		var asteroid: Asteroid = ASTEROID_SCENE.instantiate()
		asteroid.configure(request.size_index, request.spawn_position, request.velocity, request.spin)
		asteroid.destroyed.connect(_on_asteroid_destroyed)
		_asteroids.add_child(asteroid)


func _clear_container(container: Node2D) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _on_player_fired(muzzle_position: Vector2, direction: Vector2) -> void:
	var bullet: Bullet = BULLET_SCENE.instantiate()
	bullet.launch(muzzle_position, direction)
	_bullets.add_child(bullet)


func _on_player_died() -> void:
	_lives -= 1
	_hud.set_lives(_lives)
	if _lives > 0:
		_respawn_timer = RESPAWN_DELAY
		return
	_game_over = true
	_hud.show_persistent_banner("GAME OVER\nSCORE %d\nPRESS R TO RESTART" % _score)


func _on_asteroid_destroyed(asteroid: Asteroid) -> void:
	_score += asteroid.points()
	_hud.set_score(_score)
	if not asteroid.can_split():
		return
	var child_size := asteroid.size_index - 1
	var base_heading := asteroid.velocity.angle()
	for i in 2:
		var offset := SPLIT_SPREAD if i == 0 else -SPLIT_SPREAD
		var heading := base_heading + offset + _rng.randf_range(-0.25, 0.25)
		_queue_spawn(child_size, asteroid.global_position, heading)
