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

# 三人称カメラ設定
const CAM_DIST        = 4.5
const CAM_SENSITIVITY = 0.25
const CAM_PITCH_MIN   = 5.0
const CAM_PITCH_MAX   = 70.0

# 一人称カメラ設定
const FPS_SENSITIVITY = 0.20
const FPS_YAW_LIMIT   = 120.0
const FPS_PITCH_LIMIT =  45.0

@onready var camera        = $Camera3D
@onready var fps_camera    = $FPSCamera
@onready var fork_carriage = $ForkCarriage
@onready var fork_left     = $ForkLeft
@onready var fork_right    = $ForkRight
@onready var light_face    = $LightFace

# パレット積み込み設定
const FORK_CENTER_Z    = -1.035  # フォークの中心（リフトのローカル座標 Z）
const FORK_TOP_OFFSET  = 0.02    # フォークの板の上面（fork_height からの高さ）
const PICK_RANGE_XZ    = 0.6     # フォーク中心からこの距離以内のパレットを掴める
const PICK_MAX_YAW_DEG = 15.0    # パレットの向きがフォークと何度までずれていてよいか
const PICK_MIN_DY      = -0.03   # フォーク上面 - パレット底面 の許容範囲（下限）
const PICK_MAX_DY      = 0.09    # 同（上限。パレットの桁の高さまで）
const GROUND_PLACE_MAX = 0.3     # 地面に置くときのフォーク上面の最大高さ
const MESSAGE_SECONDS  = 2.5

var held_pallet: Node3D = null
var _message_label: Label
var _message_timer: float = 0.0

var fork_height: float = 0.02
var fork_tilt:   float = 0.0
var cam_yaw:     float = 0.0
var cam_pitch:   float = 25.0
var light_on:    bool  = true

var is_fps:    bool  = false
var fps_yaw:   float = 0.0
var fps_pitch: float = 0.0

func _ready() -> void:
	var mat = light_face.get_surface_override_material(0)
	if mat:
		light_face.set_surface_override_material(0, mat.duplicate())
	fps_camera.current = false
	_update_camera()
	_create_message_label()

func _input(event: InputEvent) -> void:
	# 右クリック：三人称モード時のみカメラ回転
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and not is_fps:
			if event.pressed:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			if is_fps:
				fps_yaw  -= event.relative.x * FPS_SENSITIVITY
				fps_yaw   = clamp(fps_yaw, -FPS_YAW_LIMIT, FPS_YAW_LIMIT)
				fps_pitch += event.relative.y * FPS_SENSITIVITY
				fps_pitch  = clamp(fps_pitch, -FPS_PITCH_LIMIT, FPS_PITCH_LIMIT)
				_update_fps_camera()
			else:
				cam_yaw   = fmod(cam_yaw - event.relative.x * CAM_SENSITIVITY, 360.0)
				cam_pitch = clamp(cam_pitch + event.relative.y * CAM_SENSITIVITY,
								  CAM_PITCH_MIN, CAM_PITCH_MAX)
				_update_camera()

	if event is InputEventKey and event.pressed and not event.echo:
		# V キー：一人称↔三人称切替
		if event.keycode == KEY_V:
			is_fps = !is_fps
			camera.current     = !is_fps
			fps_camera.current =  is_fps
			fps_yaw   = 0.0
			fps_pitch = 0.0
			_update_fps_camera()
			if is_fps:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		# E キー：ライトON/OFF
		if event.keycode == KEY_E:
			light_on = !light_on
			_apply_light()
		# P キー：パレットを掴む／置く
		if event.keycode == KEY_P:
			if held_pallet == null:
				_try_pick_pallet()
			else:
				_try_place_pallet()

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

	# ===== 掴んでいるパレットをフォークに追従させる =====
	_follow_held_pallet()

	# ===== メッセージ表示の時間切れ =====
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message_label.text = ""

# ── パレット積み込み ────────────────────────────────────────────────────────

# フォーク上面の位置（ワールド座標）
func _fork_top_position() -> Vector3:
	return to_global(Vector3(0.0, fork_height + FORK_TOP_OFFSET, FORK_CENTER_Z))

# フォークの上にあるパレットを1つ探して掴む
func _try_pick_pallet() -> void:
	var fork_top := _fork_top_position()
	var best: Node3D = null
	var best_dist := INF
	for p in get_tree().get_nodes_in_group("pallets"):
		var pallet := p as Node3D
		if pallet == null:
			continue
		# フォーク基準（リフトのローカル座標）でのパレット位置
		var lp := to_local(pallet.global_position)
		if absf(lp.x) > PICK_RANGE_XZ or absf(lp.z - FORK_CENTER_Z) > PICK_RANGE_XZ:
			continue
		var dy := fork_top.y - pallet.global_position.y
		if dy < PICK_MIN_DY or dy > PICK_MAX_DY:
			continue
		# 向きのずれ（パレットは180°回しても同じ形なので、PI 周期で見る）
		var diff := fposmod(pallet.global_rotation.y - global_rotation.y + PI * 0.5, PI) - PI * 0.5
		if absf(diff) > deg_to_rad(PICK_MAX_YAW_DEG):
			continue
		var dist := Vector2(lp.x, lp.z - FORK_CENTER_Z).length()
		if dist < best_dist:
			best_dist = dist
			best = pallet
	if best == null:
		_show_message("パレットがフォークの上にありません")
		return
	held_pallet = best
	_follow_held_pallet()
	_show_message("パレットを掴みました (P で置く)")

# 掴んでいるパレットを置く
func _try_place_pallet() -> void:
	var pallet := held_pallet
	var pos := pallet.global_position
	var footprint := _pallet_footprint(pallet)

	# 置く先の高さを決める：荷台の上なら荷台の床、外なら地面
	var target_y := 0.0
	var truck := _find_truck_under(pallet, footprint)
	if truck != null:
		var bed_y: float = truck.get_bed_top_y()
		if pos.y < bed_y - 0.02:
			_show_message("荷台の床より下には置けません（フォークを上げてください）")
			return
		target_y = bed_y
	else:
		if pos.y > GROUND_PLACE_MAX:
			_show_message("高すぎます。フォークを下げてください")
			return

	# 他のパレットと重なっていないか確認する
	for p in get_tree().get_nodes_in_group("pallets"):
		var other := p as Node3D
		if other == null or other == pallet:
			continue
		if absf(other.global_position.y - target_y) > 0.3:
			continue  # 高さが違う（荷台の上と地面など）ものは重ならない
		var d := Vector2(pos.x - other.global_position.x, pos.z - other.global_position.z).length()
		if d < (footprint + _pallet_footprint(other)) * 0.5 - 0.01:
			_show_message("他のパレットと重なっています")
			return

	pallet.global_position = Vector3(pos.x, target_y, pos.z)
	held_pallet = null
	_show_message("荷台に置きました" if truck != null else "地面に置きました")

# パレットの4隅がすべてトラックの荷台の上にあれば、そのトラックを返す
func _find_truck_under(pallet: Node3D, footprint: float) -> Node:
	var half := footprint * 0.5
	for t in get_tree().get_nodes_in_group("truck"):
		var all_over := true
		for corner in [Vector3(-half, 0, -half), Vector3(half, 0, -half),
				Vector3(-half, 0, half), Vector3(half, 0, half)]:
			if not t.is_over_bed(pallet.to_global(corner)):
				all_over = false
				break
		if all_over:
			return t
	return null

# パレットの一辺の長さ（大 1.1m / 小 0.8m）
func _pallet_footprint(pallet: Node3D) -> float:
	return pallet.get_footprint()

func _follow_held_pallet() -> void:
	if held_pallet == null:
		return
	held_pallet.global_position = _fork_top_position()
	held_pallet.global_rotation = Vector3(0.0, global_rotation.y, 0.0)

# ── 画面メッセージ ──────────────────────────────────────────────────────────
func _create_message_label() -> void:
	var layer := CanvasLayer.new()
	_message_label = Label.new()
	_message_label.position = Vector2(20, 20)
	_message_label.add_theme_font_size_override("font_size", 22)
	_message_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	layer.add_child(_message_label)
	add_child(layer)

func _show_message(text: String) -> void:
	_message_label.text = text
	_message_timer = MESSAGE_SECONDS

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

func _update_fps_camera() -> void:
	fps_camera.rotation_degrees = Vector3(fps_pitch, -90.0 + fps_yaw, 0.0)
