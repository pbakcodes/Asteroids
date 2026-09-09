class_name Hud
extends CanvasLayer

## Score, remaining lives, control hints and the centre banner used for wave
## announcements and the game-over state.

const LIFE_ICON := preload("res://assets/sprites/life_icon.png")

var _banner_time := 0.0

@onready var _score_label: Label = $Root/ScoreLabel
@onready var _lives_box: HBoxContainer = $Root/LivesBox
@onready var _banner_label: Label = $Root/BannerLabel


func _process(delta: float) -> void:
	if _banner_time <= 0.0:
		return
	_banner_time -= delta
	if _banner_time <= 0.0:
		_banner_label.text = ""


func set_score(score: int) -> void:
	_score_label.text = "SCORE %06d" % score


func set_lives(lives: int) -> void:
	for child in _lives_box.get_children():
		_lives_box.remove_child(child)
		child.queue_free()
	for _i in maxi(lives, 0):
		var icon := TextureRect.new()
		icon.texture = LIFE_ICON
		icon.custom_minimum_size = Vector2(16.0, 16.0)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		_lives_box.add_child(icon)


## Shows a message that fades away after `duration` seconds.
func show_banner(text: String, duration: float) -> void:
	_banner_label.text = text
	_banner_time = maxf(duration, 0.0)


## Shows a message that stays until it is replaced or cleared.
func show_persistent_banner(text: String) -> void:
	_banner_label.text = text
	_banner_time = 0.0


func clear_banner() -> void:
	_banner_label.text = ""
	_banner_time = 0.0
