extends Node3D

# 走行設定
const MOVE_SPEED  = 3.0
const TURN_SPEED  = 90.0

# フォーク設定
const FORK_SPEED  = 1.2
const TILT_SPEED  = 15.0
const FORK_MIN_Y  = 0.02
const FORK_MAX_Y  = 1.8
const TILT_MIN    = -10.0
const TILT_MAX    =  10.0

# カメラ設定
const CAM_DIST        = 4.5
const CAM_SENSITIVITY = 0.25
const CAM_PITCH_MIN   = 5.0
const CAM_PITCH_MAX   = 70.0

@onready var camera        = $Camera3D
@onready var fork_carriage = $ForkCarriage
@onready var fork_left     = $ForkLeft
@onready var fork_right    = $ForkRight
@onready var light_face    = $LightFace

var fork_height: float = 0.02
var fork_tilt:   float = 0.0
var cam_yaw:     float = 0.0
var cam_pitch:   float = 25.0
var light_on:    bool  = true

func _ready() -> void:
	# マテリアルを複製して独立して変更できるようにする
	var mat = light_face.get_surface_override_material(0)
	if mat:
		light_face.set_surface_override_material(0, mat.duplicate())
	_update_camera()

func _input(event: InputEvent) -> void:
	# 右クリック：カメラ回転モード
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			cam_yaw   = fmod(cam_yaw - event.relative.x * CAM_SENSITIVITY, 360.0)
			cam_pitch = clamp(cam_pitch + event.relative.y * CAM_SENSITIVITY,
							  CAM_PITCH_MIN, CAM_PITCH_MAX)
			_update_camera()

	# E キー：ライトON/OFF切り替え
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			light_on = !light_on
			_apply_light()

func _process(delta: float) -> void:
	# ===== 走行操作 =====
	var move := 0.0
	var turn := 0.0
	if Input.is_key_pressed(KEY_F): move = -1.0
	if Input.is_key_pressed(KEY_B): move =  1.0
	if Input.is_key_pressed(KEY_L): turn =  1.0
	if Input.is_key_pressed(KEY_R): turn = -1.0
	if move != 0.0:
		translate(Vector3(0, 0, move * MOVE_SPEED * delta))
	if turn != 0.0:
		rotate_y(deg_to_rad(turn * TURN_SPEED * delta))

	# ===== フォーク上下 =====
	if Input.is_key_pressed(KEY_UP):
		fork_height = minf(fork_height + FORK_SPEED * delta, FORK_MAX_Y)
		_apply_fork_height()
	if Input.is_key_pressed(KEY_DOWN):
		fork_height = maxf(fork_height - FORK_SPEED * delta, FORK_MIN_Y)
		_apply_fork_height()

	# ===== フォーク傾き =====
	if Input.is_key_pressed(KEY_RIGHT):
		fork_tilt = minf(fork_tilt + TILT_SPEED * delta, TILT_MAX)
		_apply_fork_tilt()
	if Input.is_key_pressed(KEY_LEFT):
		fork_tilt = maxf(fork_tilt - TILT_SPEED * delta, TILT_MIN)
		_apply_fork_tilt()

func _apply_fork_height() -> void:
	fork_carriage.position.y = fork_height + 0.13
	fork_left.position.y     = fork_height
	fork_right.position.y    = fork_height

func _apply_fork_tilt() -> void:
	fork_left.rotation_degrees.x  = fork_tilt
	fork_right.rotation_degrees.x = fork_tilt

func _apply_light() -> void:
	var mat = light_face.get_surface_override_material(0) as StandardMaterial3D
	if mat:
		mat.emission_enabled = light_on

func _update_camera() -> void:
	var yr = deg_to_rad(cam_yaw)
	var pr = deg_to_rad(cam_pitch)
	camera.position = Vector3(
		CAM_DIST * sin(yr) * cos(pr),
		CAM_DIST * sin(pr),
		CAM_DIST * cos(yr) * cos(pr)
	)
	camera.look_at(global_position + Vector3(0, 1.0, 0), Vector3.UP)
