tool
class_name Ship
extends KinematicBody2D

signal movement_completed()

# different ways to move the ship
enum MovementStrategy {
	NONE, # ship will not move
	SPEED,	# ship's velocity is set to max speed - no acceleration/deceleration
	ACCELERATION, # ship accelerates to max speed - but stops instantly (no deceleration)
	ACCEL_AND_DECEL, # ship accelerates and decelarates
	LERP_ACCEL, # ships velocity is lerp'ed to max speed - but stops instantly
	LERP_POSITION # ship's position is lerp'ed to target
}

# different ways to rotate the ship
enum LookAtStrategy {
	NONE, # ship will not rotate
	JUST_LOOK_AT, # ship instantly looks at position
	LERP_ANGLE, # lerp_angle used to change rotation smoothly
	CONSTANT_ANGLE_VELOCITY, # constant angular velocity used to change rotation smoothly
}

# when checking if we're close to a target value - use different checks for accuracy
# this effects how long some look at strategies take to complete
enum IsZeroAccuracy {
	APPROXIMATE, # use is_zero_approximate() function - equiv to abs(x) < .00001
	HALF_APPROXIMATE, # use abs(x) < .001
	QUARTER_APPROXIMATE, # use abs(x) < .01
	EXACT, # us x == 0.0 !! CAUTION - may take VERY long time with this option !!
}

# different ways of doing movement
export (MovementStrategy) var movement_strategy: int
# different ways of doing look at
export (LookAtStrategy) var look_at_strategy: int
# linear speed
export var speed := 300.0
# linear acceeration
export var acceleration := 100.0
# speed of rotation (degrees)
export var angle_speed_degrees := 180.0
# complete look at before movement or do look at and movement together
export var complete_look_at_first := false
# show green dot at center of ship
#   why?  To show how accurate or inaccurate some movment strategy options are
#  Your needs will determine how accurate this must be to look right for your game
export var show_center_indicator := false setget _set_show_center_indicator
# show yellow line to show rotation angle/heading of ship
#  why?  To show how accurate or inaccurate some look at strategy options are
#  Your needs will determine how accurate this must be to look right for your game
export var show_angle_indicator := false setget _set_show_angle_indicator
# movement strategies don't get the ship all the way to the final position, only close
# this option makes ship lerp position to the final position after the movement
# strategy completes
export var lerp_rest_of_distance := false

export (IsZeroAccuracy) var lerp_finish_accuracy := 0

# global position to move to - set by global mouse position on click
export var screen_target := Vector2.INF setget _set_screen_target


onready var _angle_speed := deg2rad(angle_speed_degrees)
onready var _center_pos_dot: Sprite = $CenterPositionDot
onready var _angle_indicator_line: Line2D = $AngleIndicatorLine

var _velocity := Vector2.ZERO
var _look_at_completed := false
var _movement_completed := false
var _deceleration_started := false


func _set_screen_target(value: Vector2) -> void:
	screen_target = value
	set_physics_process(value != Vector2.INF)
	_look_at_completed = false
	_movement_completed = false
	_deceleration_started = false
	_velocity = Vector2.ZERO

func _set_show_center_indicator(value: bool) -> void:
	show_center_indicator = value
	if _center_pos_dot:
		_center_pos_dot.visible = value

func _set_show_angle_indicator(value: bool) -> void:
	show_angle_indicator = value
	if _angle_indicator_line:
		_angle_indicator_line.visible = value

func _ready():
	if movement_strategy == MovementStrategy.NONE:
		set_physics_process(false)
	elif screen_target == Vector2.INF:
		set_physics_process(false)
	# cause the set functions to be called
	self.show_center_indicator = show_center_indicator
	self.show_angle_indicator = show_angle_indicator


func _physics_process(delta):
	if !_movement_completed and (!complete_look_at_first or _look_at_completed):
		match(movement_strategy):
			MovementStrategy.NONE:
				_movement_completed = true
			MovementStrategy.SPEED:
				_movement_completed = _movement_strategy_speed(delta)
			MovementStrategy.ACCELERATION:
				_movement_completed = _movement_strategy_acceleration(delta)
			MovementStrategy.ACCEL_AND_DECEL:
				_movement_completed = _movement_strategy_acceleration_and_deceleration(delta)
			MovementStrategy.LERP_ACCEL:
				_movement_completed = _movement_strategy_lerp_acceleration(delta)
			MovementStrategy.LERP_POSITION:
				_movement_completed = _movement_strategy_lerp_position(delta)
	
	if _movement_completed and _look_at_completed:
		if lerp_rest_of_distance:
			var v_to_target = screen_target - global_position
			if !_is_zero(v_to_target.length()):
				global_position = global_position.linear_interpolate(screen_target, .8)
				return
		screen_target = Vector2.INF
		set_physics_process(false)
		emit_signal("movement_completed")
		return
	
	if _look_at_completed:
		return
	
	match(look_at_strategy):
		LookAtStrategy.NONE:
			_look_at_completed = true
		LookAtStrategy.JUST_LOOK_AT:
			_look_at_completed = _look_at_strategy_just_look_at(delta)
		LookAtStrategy.LERP_ANGLE:
			_look_at_completed = _look_at_strategy_just_lerp_angle(delta)
		LookAtStrategy.CONSTANT_ANGLE_VELOCITY:
			_look_at_completed = _look_at_strategy_const_angle_velocity(delta)

# ship moves at max speed - no acceleration or deceleration
func _movement_strategy_speed(delta: float) -> bool:
	var v_to_target := screen_target - global_position
	
	var distance_travel_one_frame := delta * speed
	# stop when within distance that can be traveled in one frame
	if v_to_target.length() <= distance_travel_one_frame:
		return true
	
	_velocity = v_to_target.normalized() * speed
	_velocity = move_and_slide(_velocity)
	
	return false

# ship accelerates to max speed - but stops instantly
func _movement_strategy_acceleration(delta: float) -> bool:
	var v_to_target := screen_target - global_position
	var current_speed := _velocity.length()
	var distance_travel_one_frame := delta * current_speed
	# stop when within distance that can be traveled in one frame
	if v_to_target.length() <= distance_travel_one_frame:
		_velocity = Vector2.ZERO
		return true
	
	# add to velocity an acceleration amount in the direction to the target
	v_to_target = v_to_target.normalized()
	_velocity += v_to_target * acceleration * delta
	_velocity = _velocity.clamped(speed)
	
	_velocity = move_and_slide(_velocity)
	
	return false

# ship accelerates to max speed and decelerates
func _movement_strategy_acceleration_and_deceleration(delta: float) -> bool:

	var v_to_target := screen_target - global_position
	
	var current_speed := _velocity.length()
	
	# check if we should start decelerating
	if !_deceleration_started and !is_zero_approx(current_speed):
		# calc distance to decelerate to zero if we decelerated right now from current speed
		var time_to_decelerate_to_zero: float = current_speed / acceleration
		var distance_to_decelerate = current_speed * time_to_decelerate_to_zero -.5*acceleration*time_to_decelerate_to_zero*time_to_decelerate_to_zero
		
		var distance := v_to_target.length()
		# if we're closer to target than it takes to brake to zero velocity - start deceleration
		if distance_to_decelerate >= distance:
			_deceleration_started = true
	
	
	if _deceleration_started:
		# stop when within distance that can be traveled in one frame
		var distance_travel_one_frame := delta * current_speed
		if v_to_target.length() <= distance_travel_one_frame:
			_velocity = Vector2.ZERO
			# if we need to be right on target - then set position or interpolate to it
			#  otherwise we'll be off a little bit
			#global_position = screen_target
			return true
		
		_velocity -= _velocity.normalized() * acceleration * delta
		
		# the speed is now increasing - meaning the ship is starting to go the other way
		if _velocity.length() > current_speed:
			_velocity = Vector2.ZERO
			# if we need to be right on target - then set position or interpolate to it
			#  otherwise we'll be off a little bit
			#global_position = screen_target
			return true
		
		_velocity = move_and_slide(_velocity)
		return false

	_velocity += v_to_target.normalized() * acceleration * delta
	
	_velocity = _velocity.clamped(speed)

	_velocity = move_and_slide(_velocity)
	
	return false

# ship accelerates to max speed using lerp
func _movement_strategy_lerp_acceleration(delta: float) -> bool:
	var v_to_target := screen_target - global_position
	
	var current_speed := _velocity.length()

	# stop when within distance that can be traveled in one frame
	var distance_travel_one_frame := delta * current_speed
	if v_to_target.length() <= distance_travel_one_frame:
		_velocity = Vector2.ZERO
		return true
	
	if current_speed < speed:
		var max_speed_velocity := v_to_target.normalized() * speed
		_velocity = _velocity.linear_interpolate(max_speed_velocity, .2)
	
	_velocity = move_and_slide(_velocity)
	
	return false

# ship lerps position to the target
func _movement_strategy_lerp_position(delta: float) -> bool:
	var v_to_target := screen_target - global_position
	if _is_zero(v_to_target.length()):
		return true
	global_position = global_position.linear_interpolate(screen_target, .1)
	return false


# look at occurs instantly with look_at function
func _look_at_strategy_just_look_at(_delta: float) -> bool:
	look_at(screen_target)
	return true

# look at occurs using lerp_angle
func _look_at_strategy_just_lerp_angle(_delta: float) -> bool:
	var v_to_target := screen_target - global_position
	var angle_to_target := v_to_target.angle()
	global_rotation = lerp_angle(global_rotation, angle_to_target, .2)
	if _is_zero(global_rotation - angle_to_target):
		return true
	return false

# look at occurs using constant angle velocity
func _look_at_strategy_const_angle_velocity(delta: float) -> bool:
	var v_to_target := screen_target - global_position
	var angle_to_target := v_to_target.angle()
	var max_angle_per_frame := _angle_speed * delta
	
	# stop within rotation that can be done in one frame
	if abs(global_rotation - angle_to_target) <= max_angle_per_frame:
		# if we need to be right on target - then set rotation
		#  otherwise we'll be off a little bit
		#global_rotation = angle_to_target
		return true
	
	# use lerp_angle() to figure out which "direction" to change angle towards
	var whole_angle_delta = lerp_angle(global_rotation, angle_to_target, 1.0)
	var angle = clamp(whole_angle_delta, global_rotation - max_angle_per_frame, global_rotation + max_angle_per_frame)
	global_rotation = angle
	return false


#checks if value is zero - how close depends on option selected
#  The more accurate this check - the longer it takes to complete lerp rotations
func _is_zero(value: float) -> bool:
	if lerp_finish_accuracy == IsZeroAccuracy.APPROXIMATE:
		return is_zero_approx(value)
	elif lerp_finish_accuracy == IsZeroAccuracy.HALF_APPROXIMATE:
		return abs(value) < .001
	elif lerp_finish_accuracy == IsZeroAccuracy.QUARTER_APPROXIMATE:
		return abs(value) < .01
	return value == 0.0



