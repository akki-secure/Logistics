# Truck.gd
# 4トン級ウイングトラック（箱型バン）をコードで手続き的に生成するスクリプト。
# 長辺が X 方向、運転席は +X 側。荷台の中心がこのノードの原点（地面の高さ）。
# 横のウイング（側面パネル）は、リーチリフトが近づくと自動で開く。

extends Node3D

# ── 寸法（メートル）─────────────────────────────────────────────────────────
const BED_LENGTH   := 6.2   # 荷台の長さ（X 方向）
const BED_WIDTH    := 2.2   # 荷台の幅（Z 方向）
const BED_TOP_Y    := 1.1   # 荷台の床の上面の高さ
const BOX_HEIGHT   := 2.1   # 荷台の床から屋根の下までの高さ
const WHEEL_RADIUS := 0.45

# ── ウイング設定 ────────────────────────────────────────────────────────────
const WING_OPEN_DEG := 100.0  # 開いたときの角度（真上より少し先まで跳ね上げる）
const WING_SPEED    := 60.0   # 1秒あたりの開閉角度（度）
const OPEN_DISTANCE := 4.0    # リフトがこの距離（荷台の縁から）以内に来たら開く

# 自動開閉の対象にするリーチリフトのパス（Main.tscn では兄弟ノード）
@export var lift_path: NodePath = ^"../ReachLift"

var _lift: Node3D
var _wing_pivot_pos: Node3D   # +Z 側のウイングのヒンジ
var _wing_pivot_neg: Node3D   # -Z 側のウイングのヒンジ
var _angle_pos: float = 0.0   # 現在の開き具合（度）。0 = 閉じている
var _angle_neg: float = 0.0

func _ready() -> void:
	add_to_group("truck")
	_lift = get_node_or_null(lift_path) as Node3D
	_build_truck()

# ── Box を1つ追加するヘルパー（Pallet.gd の _add_box と同じ考え方）──────────
func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi   := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	return mi

func _make_mat(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
	return mat

# ── トラック全体の生成 ──────────────────────────────────────────────────────
func _build_truck() -> void:
	var white  := _make_mat(Color(0.93, 0.94, 0.96))
	var blue   := _make_mat(Color(0.15, 0.35, 0.65))
	var dark   := _make_mat(Color(0.12, 0.12, 0.14))
	var glass  := _make_mat(Color(0.25, 0.4, 0.5))
	var deck   := _make_mat(Color(0.55, 0.45, 0.32))
	var lamp   := _make_mat(Color(1.0, 0.95, 0.7), true)

	var half_l := BED_LENGTH * 0.5
	var half_w := BED_WIDTH * 0.5
	var roof_y := BED_TOP_Y + BOX_HEIGHT

	# シャーシ（車体の骨組み）
	_add_box(self, Vector3(0.9, 0.7, 0.0), Vector3(8.2, 0.25, 1.5), dark)

	# 荷台の床（上面が BED_TOP_Y）
	_add_box(self, Vector3(0.0, BED_TOP_Y - 0.1, 0.0), Vector3(BED_LENGTH, 0.2, BED_WIDTH), deck)

	# 荷箱の固定部分：屋根・前壁（運転席側）・後ろ壁
	_add_box(self, Vector3(0.0, roof_y + 0.05, 0.0), Vector3(BED_LENGTH, 0.1, BED_WIDTH + 0.1), white)
	_add_box(self, Vector3(half_l - 0.05, BED_TOP_Y + BOX_HEIGHT * 0.5, 0.0),
			Vector3(0.1, BOX_HEIGHT, BED_WIDTH), white)
	_add_box(self, Vector3(-half_l + 0.05, BED_TOP_Y + BOX_HEIGHT * 0.5, 0.0),
			Vector3(0.1, BOX_HEIGHT, BED_WIDTH), white)

	# ウイング（側面パネル）：上端をヒンジにして回転させる
	_wing_pivot_pos = _build_wing(+1.0, white, half_w, roof_y)
	_wing_pivot_neg = _build_wing(-1.0, white, half_w, roof_y)

	# 運転席（キャブ）
	_add_box(self, Vector3(half_l + 1.0, 1.85, 0.0), Vector3(1.8, 1.9, BED_WIDTH), blue)
	_add_box(self, Vector3(half_l + 1.91, 2.3, 0.0), Vector3(0.02, 0.7, 1.9), glass)   # フロントガラス
	for side in [-1.0, 1.0]:
		_add_box(self, Vector3(half_l + 1.2, 2.3, side * (half_w + 0.01)),
				Vector3(0.9, 0.6, 0.02), glass)                                          # 側面の窓
		_add_box(self, Vector3(half_l + 1.91, 1.2, side * 0.8),
				Vector3(0.02, 0.2, 0.3), lamp)                                           # ヘッドライト

	# タイヤ：前2本・後ろ4本（ダブルタイヤ）
	for z in [-1.0, 1.0]:
		_add_wheel(Vector3(half_l + 1.1, WHEEL_RADIUS, z), dark)
	for z in [-1.0, -0.68, 0.68, 1.0]:
		_add_wheel(Vector3(-half_l + 1.3, WHEEL_RADIUS, z), dark)

# ウイング1枚を作り、ヒンジ（回転の中心になる Node3D）を返す。
# sign_z: +1 なら +Z 側、-1 なら -Z 側。
func _build_wing(sign_z: float, mat: StandardMaterial3D, half_w: float, roof_y: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0.0, roof_y, sign_z * (half_w + 0.025))
	add_child(pivot)
	# パネルはヒンジから真下にぶら下げる（中心がヒンジの BOX_HEIGHT/2 下）
	_add_box(pivot, Vector3(0.0, -BOX_HEIGHT * 0.5, 0.0),
			Vector3(BED_LENGTH - 0.2, BOX_HEIGHT, 0.05), mat)
	return pivot

func _add_wheel(pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi   := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius    = WHEEL_RADIUS
	mesh.bottom_radius = WHEEL_RADIUS
	mesh.height        = 0.3
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees.x = 90.0   # 円柱の軸を Z 方向（車軸方向）に向ける
	mi.set_surface_override_material(0, mat)
	add_child(mi)

# ── 自動開閉 ────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _lift == null:
		return

	# リフトの位置をトラック基準の座標に変換する
	var p := to_local(_lift.global_position)
	# 荷台の長方形（XZ）から、リフトまでの距離
	var dx := maxf(absf(p.x) - BED_LENGTH * 0.5, 0.0)
	var dz := maxf(absf(p.z) - BED_WIDTH * 0.5, 0.0)
	var near := sqrt(dx * dx + dz * dz) < OPEN_DISTANCE

	# リフトがいる側のウイングだけ開く
	var target_pos := WING_OPEN_DEG if (near and p.z > 0.0) else 0.0
	var target_neg := WING_OPEN_DEG if (near and p.z <= 0.0) else 0.0

	_angle_pos = move_toward(_angle_pos, target_pos, WING_SPEED * delta)
	_angle_neg = move_toward(_angle_neg, target_neg, WING_SPEED * delta)

	# +Z 側は -X 軸回り、-Z 側は +X 軸回りに回すと、どちらも外側へ跳ね上がる
	_wing_pivot_pos.rotation_degrees.x = -_angle_pos
	_wing_pivot_neg.rotation_degrees.x =  _angle_neg

# ── 他のスクリプトから使う関数 ───────────────────────────────────────────────

# 荷台の床の上面の高さ（ワールド座標）
func get_bed_top_y() -> float:
	return global_position.y + BED_TOP_Y

# 指定したワールド座標が荷台の真上（XZ の範囲内）かどうか
func is_over_bed(world_pos: Vector3) -> bool:
	var p := to_local(world_pos)
	return absf(p.x) <= BED_LENGTH * 0.5 and absf(p.z) <= BED_WIDTH * 0.5

# どちらかのウイングが（ほぼ）開いているか
func is_wing_open() -> bool:
	return maxf(_angle_pos, _angle_neg) > WING_OPEN_DEG * 0.9
