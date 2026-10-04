extends Node2D

const WIDTH_PER_PLAYER: float = 200.0
const SHRINK_DELAY: float = 7.0
@export_range(1, 16) var test_player_count: int = 1

var _stage_count: int = 1
var _target_count: int = 1
var _shrink_remaining: float = 0.0
var _warning := Node2D.new()

@onready var platforms: Array[Node2D] = [
	$BottomPlatform,
	$TopPlatform,
]


func _ready() -> void:
	for platform in platforms:
		var collision: CollisionShape2D = platform.get_node("CollisionShape2D")
		collision.shape = collision.shape.duplicate()

	add_child(_warning)
	_warning.z_index = 1
	_warning.draw.connect(_draw_warning)


func _physics_process(delta: float) -> void:
	var count: int = 0
	for player in Stdb.get_players():
		if player.get("online", true):
			count += 1

	if OS.has_feature("editor"):
		count = test_player_count

	count = maxi(count, 1)

	if count != _target_count:
		_target_count = count

		if count < _stage_count:
			# Keep the existing platform during the warning.
			_shrink_remaining = SHRINK_DELAY
		else:
			# Grow immediately, or cancel a pending shrink.
			_shrink_remaining = 0.0
			_resize_stage(count)

		_warning.queue_redraw()

	elif _shrink_remaining > 0.0:
		_shrink_remaining -= delta
		if _shrink_remaining <= 0.0:
			_resize_stage(_target_count)
			_warning.queue_redraw()


func _resize_stage(count: int) -> void:
	var width_change := (count - _stage_count) * WIDTH_PER_PLAYER
	_stage_count = count

	for platform in platforms:
		var collision: CollisionShape2D = platform.get_node("CollisionShape2D")
		var shape := collision.shape as RectangleShape2D
		shape.size.x += width_change

		var line: Line2D = platform.get_node("Line2D")
		var offset := Vector2(width_change / 2.0, 0.0)
		line.set_point_position(0, line.get_point_position(0) - offset)
		line.set_point_position(1, line.get_point_position(1) + offset)


func _draw_warning() -> void:
	var removed_width := (_stage_count - _target_count) * WIDTH_PER_PLAYER
	if removed_width <= 0.0:
		return

	var offset := Vector2(removed_width / 2.0, 0.0)

	for platform in platforms:
		var line: Line2D = platform.get_node("Line2D")
		var left := _warning.to_local(
			line.to_global(line.get_point_position(0))
		)
		var right := _warning.to_local(
			line.to_global(line.get_point_position(1))
		)

		_warning.draw_line(left, left + offset, Color.RED, line.width)
		_warning.draw_line(right - offset, right, Color.RED, line.width)
