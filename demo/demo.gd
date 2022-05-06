extends Node2D


onready var _ship: Ship = $Ship
onready var _click_position_sprite: Sprite = $ClickPositionDot

var _stopwatch := StopWatch.new()

func _unhandled_input(event):
	if event.is_echo():
		return
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_LEFT and event.is_pressed():
			_ship.screen_target = event.global_position
			_click_position_sprite.global_position = event.global_position
			_stopwatch.clear()
			_stopwatch.start()


func _on_Ship_movement_completed():
	_stopwatch.stop()
	print("Ship movement done in %d ms" % _stopwatch.get_elapsed_msec())

