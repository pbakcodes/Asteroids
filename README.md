# Asteroids

A classic **Asteroids** game built with Godot 4 — a small but complete 2D
project featuring an inertia-based spaceship, a wrap-around arena, asteroids
that split into smaller fragments, scoring, lives, and enemy waves. All
graphics are original pixel art created locally in Aseprite.

![Gameplay](docs/screenshot.png)

## Requirements

* **Godot 4.x** (developed and verified with 4.7,
  `config/features = "4.7"`).
* No external dependencies, network access, or telemetry.

## Running the game

1. Open the project directory in Godot (`Import` → select `project.godot`).
2. Press **F5** or run the main scene at `res://scenes/main.tscn`.

To run from a terminal, Godot must be available in `PATH`. A fresh clone does
not have a `.godot/` directory yet, so its resources and textures have not
been imported. Running only `godot --path .` at this point will start the game
with missing graphics. Import the resources first:

```sh
# Run once after cloning to import resources
godot --headless --path . --import

# Then launch the game normally
godot --path .
```

Instead of using `--import`, you can open the project in the editor once with
`godot --editor --path .`, wait for the import to finish, and close it.

## Tests

```sh
tests/run_split_stress.sh  # or: GODOT_BIN=/path/to/godot tests/run_split_stress.sh
```

`tests/split_stress.gd` is a headless regression test for asteroid splitting.
It destroys the entire first wave down to the smallest fragments twice, with
nine splits per run. It verifies fragment counts, scoring, no lost lives, wave
progression only after deferred spawns have been registered, and deterministic
trajectories. The shell script also fails if the engine reports physics-server
errors such as `Can't change this state while flushing queries`, which cannot
be observed by GDScript from inside the game.

## Controls

| Action       | Keys          |
| ------------ | ------------- |
| Rotate left  | `A` / `←`     |
| Rotate right | `D` / `→`     |
| Thrust       | `W` / `↑`     |
| Fire         | `Space`       |
| Restart      | `R`           |

## Gameplay

* The ship accelerates toward its nose and has inertia, light velocity
  damping, a maximum speed, and a short firing cooldown.
* The ship, bullets, and asteroids wrap around the edges of the 1280×720
  arena.
* Asteroids come in three sizes. A large asteroid splits into two medium
  asteroids, a medium asteroid splits into two small ones, and a small
  asteroid disappears when hit.
* Scoring: **large 20**, **medium 50**, **small 100**. As in the original
  game, the smallest fragments are worth the most points.
* Bullets have a limited lifetime and remove themselves, so missed shots do
  not leave stale nodes in the scene.
* Colliding with an asteroid costs one life. After respawning, the ship
  briefly becomes invulnerable and blinks. At zero lives, the **GAME OVER**
  screen appears and the game can be restarted.
* Waves are **deterministic and bounded**. The asteroid count grows from 3 to
  a maximum of 9, and the random number generator is seeded with the wave
  number, so each wave number always produces the same starting layout.
  Asteroids never spawn within 260 pixels of the ship.

## Architecture

```text
project.godot          configuration, input map, collision layers, nearest filter
scenes/
  main.tscn            main scene: background, Asteroids/Bullets containers, Player, HUD
  player.tscn          ship, thrust sprite, and collision shape
  asteroid.tscn        one asteroid, with its size configured at runtime
  bullet.tscn          projectile
  hud.tscn             interface layer
scripts/
  arena.gd             shared arena geometry and position wrapping
  main.gd              game manager: waves, spawning, score, lives, restart
  player.gd            controls, flight physics, shooting, invulnerability
  asteroid.gd          sizes, movement, rotation, splitting, point values
  bullet.gd            movement, lifetime, asteroid hits
  hud.gd               score, life icons, control hints, game-over banner
assets/
  aseprite/            editable .aseprite source files
  sprites/             exported transparent PNG files with nearest filtering
tests/
  split_stress.gd      headless asteroid-splitting regression test
  run_split_stress.sh  runs the test and detects physics-server errors
docs/                  README screenshot, ignored by Godot through .gdignore
```

Code design principles:

* **Typed GDScript** and short, single-purpose scripts instead of one large
  controller responsible for everything.
* Communication through **signals** (`Player.fired`, `Player.died`, and
  `Asteroid.destroyed`) rather than polling unrelated nodes.
* Asteroids join the **`Arena.ASTEROID_GROUP` group**, so the wave-cleared
  condition does not depend on their parent node. There are no absolute node
  paths such as `/root/Main/...`.
* `Arena` is a standalone helper containing arena constants and the shared
  `wrap()` function used by the ship, bullets, and asteroids.
* Collision layers are named in `project.godot`: `player`, `asteroids`, and
  `bullets`. Collision masks are minimal, and asteroids do not collide with
  one another.
* Timers are ordinary fields updated in `_physics_process` rather than
  `await`-based tasks, preventing a restart from racing a previously scheduled
  timer.
* New asteroids are created **outside collision handling**. Splitting is
  reported through `Asteroid.destroyed` while the physics server is flushing
  queries, when adding collision shapes is forbidden. `Main` resolves random
  values immediately to preserve determinism, then creates the nodes through
  a deferred call. A wave cannot be considered cleared while the deferred
  spawn queue is non-empty.

## Artwork

All artwork in `assets/` is **original and was created locally in Aseprite**
for this repository. No external, downloaded, or third-party copyrighted
materials were used. The repository includes both editable `.aseprite`
sources and exported PNG files:

| File              | Size    | Purpose                         |
| ----------------- | ------- | ------------------------------- |
| `ship`            | 32×32   | player ship                     |
| `ship_thrust`     | 16×32   | engine flame                    |
| `bullet`          | 8×8     | projectile                      |
| `asteroid_large`  | 64×64   | large asteroid                  |
| `asteroid_medium` | 40×40   | medium asteroid                 |
| `asteroid_small`  | 24×24   | small asteroid                  |
| `starfield`       | 128×128 | tiled star background           |
| `life_icon`       | 16×16   | HUD life indicator              |

The project renders pixel art with **nearest-neighbour filtering**
(`textures/canvas_textures/default_texture_filter=0`), and every sprite except
the background uses transparency.

The project intentionally has no sound so that it does not introduce assets
that were not created locally.

## Optional local Godot AI plugin

The project was developed with a local *Godot AI* plugin for scene inspection
and automated gameplay testing. The plugin is a developer tool and **is not
part of this repository**. It does not appear in Git history and is not
required to run the game.

To use it locally, install it in your own `addons/` directory, enable it under
`Project → Project Settings → Plugins`, and **do not commit** either the plugin
directory or the entries it adds to `project.godot` (`[editor_plugins]` and
the `_mcp_game_helper` autoload). The main branch deliberately keeps
`project.godot` free of these entries so a fresh clone works without the
plugin.

## History

The repository began as an empty skeleton, including a test push from the
GitHub Copilot App. This is its first playable MVP.
