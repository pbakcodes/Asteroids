extends SceneTree

## Headless regression check for asteroid splitting.
##
## Splits are requested from a collision callback, i.e. while the physics server
## is flushing queries. Building the child rocks there used to add collision
## shapes mid-flush, which the engine rejects with "Can't change this state
## while flushing queries". This check drives real bullet/asteroid collisions
## across every size so that a regression shows up as engine errors on stderr;
## `tests/run_split_stress.sh` fails the run when it sees them.
##
## On top of that it asserts the gameplay invariants the deferred spawn must
## preserve: split counts per size, size-based scoring, wave advancement only
## after the deferred children exist, and identical trajectories between two
## runs of the same wave.
##
## The timeline is frame-exact on purpose: every shot gets the same fixed frame
## budget whether or not it connects early, so two runs of the same wave are
## directly comparable.
##
## Run with:
##     godot --headless --path . --script res://tests/split_stress.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")

## Bullets are launched from behind the rock, along its own heading, so the
## overlap is a genuine enter transition rather than a spawn-inside-the-shape.
const SHOT_STANDOFF := 48.0
const SHOT_FRAMES := 20
const SETTLE_FRAMES := 6
const WAVE_TIMEOUT_FRAMES := 600

## Wave 1 opens with 3 large rocks, which yield 6 medium and then 12 small.
## Those totals hold whatever order the rocks are destroyed in, so they stay
## valid even when a shot clips a neighbour instead of the rock it was aimed at.
const EXPECTED_FIRST_WAVE := 3
const EXPECTED_SPLITS := 9
const EXPECTED_SCORE := 3 * 20 + 6 * 50 + 12 * 100
const MAX_SHOTS := 40

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	var main: Main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await physics_frame

	# Both runs are entered through the same reset so their timelines line up
	# frame for frame and their trajectories can be compared directly.
	await _restart(main)
	var first := await _clear_wave(main, "run 1")
	_check_totals(main, "run 1")
	await _await_wave(main, 2, "run 1")

	await _restart(main)
	var second := await _clear_wave(main, "run 2")
	_check_totals(main, "run 2")

	if first != second:
		_fail("split trajectories are not reproducible between two runs of wave 1")

	_report()


## Restarts the game and parks the ship out of harm's way: it would otherwise
## be ground down by the rocks it is standing among, and this check is about
## splitting, not about survival.
func _restart(main: Main) -> void:
	main._start_game()
	main._player.set_deferred("monitoring", false)
	main._player.set_deferred("monitorable", false)
	await _settle()


## Empties the field by repeatedly shooting the largest rock left, so every
## size is split at least once. Returns a per-shot signature of the surviving
## rocks so two runs can be compared for reproducibility.
func _clear_wave(main: Main, label: String) -> PackedStringArray:
	var signature: PackedStringArray = []

	var opening := _live_asteroids()
	if opening.size() != EXPECTED_FIRST_WAVE:
		_fail("%s: expected %d rocks at wave start, found %d" % [
			label, EXPECTED_FIRST_WAVE, opening.size(),
		])
		return signature

	var shots := 0
	while true:
		var live := _live_asteroids()
		if live.is_empty():
			break
		if shots >= MAX_SHOTS:
			_fail("%s: field still had %d rocks after %d shots" % [label, live.size(), shots])
			return signature

		await _shoot(main, _biggest(live))
		shots += 1
		signature.append("shot %d" % shots)
		signature.append_array(_signature_of(_live_asteroids()))

	return signature


## Picks the largest rock, breaking ties on position so the choice is a pure
## function of the world state and therefore reproducible.
func _biggest(live: Array[Node]) -> Asteroid:
	var best: Asteroid = live[0]
	for node in live:
		var rock := node as Asteroid
		if rock.size_index > best.size_index:
			best = rock
		elif rock.size_index == best.size_index and _order_key(rock) < _order_key(best):
			best = rock
	return best


func _order_key(rock: Asteroid) -> float:
	return rock.global_position.y * Arena.SIZE.x + rock.global_position.x


## Fires one bullet at a single rock and always burns the same number of frames,
## so the run stays frame-for-frame comparable.
func _shoot(main: Main, rock: Asteroid) -> void:
	var heading := rock.velocity.normalized()
	if heading.is_zero_approx():
		heading = Vector2.RIGHT
	main._on_player_fired(rock.global_position - heading * SHOT_STANDOFF, heading)

	for _frame in SHOT_FRAMES:
		await physics_frame

	# A stray bullet would otherwise wander into the next shot's target.
	main._clear_container(main._bullets)
	await _settle()


func _check_totals(main: Main, label: String) -> void:
	if main._score != EXPECTED_SCORE:
		_fail("%s: expected score %d, got %d" % [label, EXPECTED_SCORE, main._score])
	if main._lives != Main.STARTING_LIVES:
		_fail("%s: expected %d lives, got %d" % [label, Main.STARTING_LIVES, main._lives])


## Waits for the next wave and fails if it arrives while spawns are still
## queued, which would mean the field had been declared clear too early.
func _await_wave(main: Main, wave: int, label: String) -> void:
	for _frame in WAVE_TIMEOUT_FRAMES:
		if main._wave >= wave:
			if not main._pending_spawns.is_empty():
				_fail("%s: wave %d started with spawns still queued" % [label, wave])
			return
		await physics_frame
	_fail("%s: wave %d never started" % [label, wave])


func _settle() -> void:
	for _frame in SETTLE_FRAMES:
		await physics_frame


func _live_asteroids() -> Array[Node]:
	var live: Array[Node] = []
	for node in get_nodes_in_group(Arena.ASTEROID_GROUP):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			live.append(node)
	return live


func _signature_of(asteroids: Array[Node]) -> PackedStringArray:
	var rows: PackedStringArray = []
	for node in asteroids:
		var rock := node as Asteroid
		rows.append("%d|%.3f|%.3f|%.3f|%.3f" % [
			rock.size_index,
			rock.global_position.x, rock.global_position.y,
			rock.velocity.x, rock.velocity.y,
		])
	rows.sort()
	return rows


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("split_stress: OK (%d splits per run, 2 runs, expected score %d)" % [
			EXPECTED_SPLITS, EXPECTED_SCORE,
		])
		quit(0)
		return

	for failure in _failures:
		printerr("split_stress: FAIL: %s" % failure)
	quit(1)
