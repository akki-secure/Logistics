# Pallet.gd
# パレット（荷役台）をコードで手続き的に生成するスクリプト

extends Node3D

# ── enum（列挙型）───────────────────────────────────────────────────────────
# 「決まった選択肢」を名前で管理する型。
# Godotエディタの Inspector でドロップダウンとして表示される。

enum PalletType {
	WOOD,    # 木製パレット（茶色）
	PLASTIC  # プラスチックパレット（グレー）
}

enum PalletSize {
	LARGE,  # 大（1.1m × 1.1m）
	SMALL   # 小（0.8m × 0.8m）
}

# ── @export 変数 ────────────────────────────────────────────────────────────
# @export を付けると Godotエディタの Inspector から値を変更できる。
# ゲームを実行しなくても、エディタ上でドロップダウンとして選べる。

@export var pallet_type: PalletType = PalletType.WOOD
@export var pallet_size: PalletSize = PalletSize.LARGE

# ── _ready() ────────────────────────────────────────────────────────────────
# ノードが画面に登場した瞬間に1回だけ自動で呼ばれる特別な関数。

func _ready() -> void:
	_build_pallet()

# ── パレット生成のメイン関数 ─────────────────────────────────────────────────
func _build_pallet() -> void:
	# サイズに応じて幅・奥行きを決める
	# ★ 三項演算子: 条件 if 真の値 else 偽の値
	var w: float = 1.10 if pallet_size == PalletSize.LARGE else 0.80
	var d: float = 1.10 if pallet_size == PalletSize.LARGE else 0.80

	# マテリアル（色）を種類で切り替える
	var mat := StandardMaterial3D.new()
	if pallet_type == PalletType.WOOD:
		mat.albedo_color = Color(0.76, 0.60, 0.42)  # 木材色（明るい茶）
	else:
		mat.albedo_color = Color(0.30, 0.30, 0.34)  # プラスチック色（濃いグレー）

	if pallet_type == PalletType.WOOD:
		_build_wood(w, d, mat)
	else:
		_build_plastic(w, d, mat)

# ── BoxMesh を1つ追加するヘルパー関数 ──────────────────────────────────────
# 同じ処理を何度も書かないよう関数にまとめた。
# pos:  中心位置（Vector3）
# size: 幅・高さ・奥行き（Vector3）
# mat:  色・質感（StandardMaterial3D）

func _add_box(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi   := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.set_surface_override_material(0, mat)
	add_child(mi)

# ── 木製パレット ────────────────────────────────────────────────────────────
# 構造（横から見た図）:
#   [天板 5枚の板]
#   [左桁]  [隙間1]  [中央桁]  [隙間2]  [右桁]
#   桁（ストリンガー）は Z 方向に走る角材。
#   隙間1・2 がフォークリフトのフォークを差し込む穴。

func _build_wood(w: float, d: float, mat: StandardMaterial3D) -> void:
	var beam_h := 0.09  # 桁の高さ
	var deck_h := 0.03  # 天板1枚の厚み
	var beam_y := beam_h * 0.5
	var deck_y := beam_h + deck_h * 0.5

	# s = スケール係数。小サイズ（w=0.80）のとき位置も縮小する。
	var s := w / 1.10

	# ─ 桁3本（Z 方向に走る）─
	_add_box(Vector3(-0.48 * s, beam_y, 0.0), Vector3(0.13 * s, beam_h, d), mat)  # 左
	_add_box(Vector3(  0.0,     beam_y, 0.0), Vector3(0.38 * s, beam_h, d), mat)  # 中央
	_add_box(Vector3( 0.48 * s, beam_y, 0.0), Vector3(0.13 * s, beam_h, d), mat)  # 右
	# ★ フォーク隙間は桁と桁の間（自然に空く）

	# ─ 天板：5枚の板（X 方向に均等配置）─
	var n       := 5
	var gap     := 0.008
	var board_w := (w - gap * (n - 1)) / n

	for i in range(n):
		var x := -w * 0.5 + board_w * 0.5 + i * (board_w + gap)
		_add_box(Vector3(x, deck_y, 0.0), Vector3(board_w, deck_h, d), mat)

# ── プラスチックパレット ────────────────────────────────────────────────────
# 木製と同じ桁構造 + 天板は1枚 + 表面に格子溝を追加。

func _build_plastic(w: float, d: float, mat: StandardMaterial3D) -> void:
	var leg_h  := 0.09
	var deck_h := 0.05  # プラスチックなので天板は少し厚め
	var leg_y  := leg_h * 0.5
	var deck_y := leg_h + deck_h * 0.5

	var s := w / 1.10

	# ─ 脚柱3本（木製の桁と同じ位置）─
	_add_box(Vector3(-0.48 * s, leg_y, 0.0), Vector3(0.13 * s, leg_h, d), mat)
	_add_box(Vector3(  0.0,     leg_y, 0.0), Vector3(0.38 * s, leg_h, d), mat)
	_add_box(Vector3( 0.48 * s, leg_y, 0.0), Vector3(0.13 * s, leg_h, d), mat)

	# ─ 天板（1枚のプレート）─
	_add_box(Vector3(0.0, deck_y, 0.0), Vector3(w, deck_h, d), mat)

	# ─ 格子溝（天板上面に薄い暗色Boxを置いて溝を表現）─
	var groove_mat := StandardMaterial3D.new()
	groove_mat.albedo_color = Color(0.15, 0.15, 0.18)
	var gy := deck_y + deck_h * 0.5 + 0.002

	# 縦溝3本（Z 方向に走る）
	for i in range(-1, 2):  # i = -1, 0, 1
		_add_box(Vector3(i * w * 0.30, gy, 0.0),     Vector3(0.025, 0.005, d * 0.88), groove_mat)

	# 横溝3本（X 方向に走る）
	for i in range(-1, 2):
		_add_box(Vector3(0.0, gy, i * d * 0.30),     Vector3(w * 0.88, 0.005, 0.025), groove_mat)
