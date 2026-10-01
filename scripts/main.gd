extends Node3D
## 主场景:负责地图、UI、波次管理、建塔交互

const CELL := 2.0
const GRID_W := 24
const GRID_H := 16
const TOTAL_WAVES := 15

const PATH_POINTS: Array[Vector3] = [
	Vector3(-26, 0, 10), Vector3(12, 0, 10), Vector3(12, 0, -2),
	Vector3(-12, 0, -2), Vector3(-12, 0, -10), Vector3(26, 0, -10),
]

const TOWER_TYPES := {
	"mg": {
		"label": "机枪塔", "cost": 50, "range": 7.0, "damage": 8.0,
		"rate": 5.0, "bullet_speed": 40.0, "aoe": 0.0,
		"color": Color(0.25, 0.45, 0.25),
	},
	"cannon": {
		"label": "加农炮", "cost": 100, "range": 9.5, "damage": 45.0,
		"rate": 0.8, "bullet_speed": 30.0, "aoe": 0.0,
		"color": Color(0.5, 0.45, 0.25),
	},
	"missile": {
		"label": "导弹车", "cost": 150, "range": 13.0, "damage": 35.0,
		"rate": 0.55, "bullet_speed": 16.0, "aoe": 3.0,
		"color": Color(0.4, 0.4, 0.45),
	},
}

const ENEMY_TYPES := {
	"soldier": {"hp": 30.0, "speed": 3.0, "reward": 8, "kind": "soldier", "lane": -1.3},
	"jeep": {"hp": 24.0, "speed": 5.5, "reward": 10, "kind": "jeep", "lane": 1.2},
	"tank": {"hp": 160.0, "speed": 1.6, "reward": 25, "kind": "tank", "lane": 0.0},
}

var camera: Camera3D
var selected_type: String = ""
var ghost: Tower = null
var occupied: Dictionary = {}  # Vector2i -> Tower

# UI
var money_label: Label
var lives_label: Label
var wave_label: Label
var msg_label: Label
var tower_buttons: Dictionary = {}
var start_button: Button
var overlay: ColorRect
var overlay_label: Label

# 波次状态机: prep -> spawning -> running -> (prep / over)
var wave_state: String = "prep"
var prep_timer: float = 12.0
var spawn_queue: Array = []
var spawn_timer: float = 0.0
var alive_enemies: int = 0
var game_running: bool = true


func _ready() -> void:
	GameState.reset()
	setup_camera()
	build_environment()
	build_grid()
	build_path_visuals()
	build_decorations()
	build_ui()
	GameState.money_changed.connect(_on_money_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	refresh_hud()
	start_button.visible = true


func _process(delta: float) -> void:
	if not game_running:
		return
	# 幽灵预览跟随鼠标
	if ghost != null and selected_type != "":
		var ci := world_to_cell(mouse_ground_pos())
		var affordable := GameState.money >= int(TOWER_TYPES[selected_type].cost)
		ghost.position = cell_to_world(ci)
		ghost.set_ghost_valid(is_valid_build(ci) and affordable)
	# 波次状态机
	match wave_state:
		"prep":
			prep_timer -= delta
			msg_label.text = "第 %d 波来袭倒计时:%d 秒" % [GameState.wave + 1, ceili(prep_timer)]
			if prep_timer <= 0.0:
				start_wave()
		"spawning":
			msg_label.text = "第 %d 波进攻中!剩余敌人:%d" % [GameState.wave, alive_enemies + spawn_queue.size()]
			spawn_timer -= delta
			if spawn_timer <= 0.0 and not spawn_queue.is_empty():
				var item: Dictionary = spawn_queue.pop_front()
				spawn_enemy(item.type)
				spawn_timer = float(item.delay)
			if spawn_queue.is_empty():
				wave_state = "running"
		"running":
			msg_label.text = "第 %d 波进攻中!剩余敌人:%d" % [GameState.wave, alive_enemies]
			if alive_enemies == 0:
				wave_finished()


func _unhandled_input(event: InputEvent) -> void:
	if not game_running:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				toggle_select("mg")
			KEY_2:
				toggle_select("cannon")
			KEY_3:
				toggle_select("missile")
			KEY_ESCAPE:
				toggle_select("")
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and selected_type != "":
		try_place()


# ---------- 建塔 ----------

func toggle_select(k: String) -> void:
	if k == "" or selected_type == k:
		selected_type = ""
	else:
		selected_type = k
	for key in tower_buttons:
		tower_buttons[key].button_pressed = (key == selected_type)
	update_ghost()


func update_ghost() -> void:
	if selected_type == "":
		if ghost:
			ghost.queue_free()
			ghost = null
		return
	if ghost == null or ghost.type_key != selected_type:
		if ghost:
			ghost.queue_free()
		ghost = Tower.new()
		add_child(ghost)
		ghost.setup(selected_type, TOWER_TYPES[selected_type])
		ghost.set_ghost(true)


func try_place() -> void:
	var ci := world_to_cell(mouse_ground_pos())
	if not is_valid_build(ci):
		return
	var cost := int(TOWER_TYPES[selected_type].cost)
	if GameState.money < cost:
		return
	GameState.money -= cost
	var t := Tower.new()
	add_child(t)
	t.setup(selected_type, TOWER_TYPES[selected_type])
	t.position = cell_to_world(ci)
	occupied[ci] = t


func is_valid_build(ci: Vector2i) -> bool:
	if ci.x < 0 or ci.x >= GRID_W or ci.y < 0 or ci.y >= GRID_H:
		return false
	if occupied.has(ci):
		return false
	return not is_path_cell(ci)


func is_path_cell(ci: Vector2i) -> bool:
	var p := cell_to_world(ci)
	var pp := Vector2(p.x, p.z)
	for i in range(PATH_POINTS.size() - 1):
		var a := Vector2(PATH_POINTS[i].x, PATH_POINTS[i].z)
		var b := Vector2(PATH_POINTS[i + 1].x, PATH_POINTS[i + 1].z)
		if dist_to_segment(pp, a, b) < 2.7:
			return true
	return false


func dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	if ab.length_squared() < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func cell_to_world(ci: Vector2i) -> Vector3:
	return Vector3((ci.x - GRID_W / 2.0 + 0.5) * CELL, 0.0, (ci.y - GRID_H / 2.0 + 0.5) * CELL)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floorf(p.x / CELL + GRID_W / 2.0)), int(floorf(p.z / CELL + GRID_H / 2.0)))


func mouse_ground_pos() -> Vector3:
	var from := camera.project_ray_origin(get_viewport().get_mouse_position())
	var dir := camera.project_ray_normal(get_viewport().get_mouse_position())
	if absf(dir.y) < 0.0001:
		return Vector3.ZERO
	return from + dir * (-from.y / dir.y)


# ---------- 波次 ----------

func make_wave(n: int) -> Array:
	var list: Array = []
	var count := 4 + n * 2
	var delay := maxf(0.35, 1.0 - n * 0.03)
	for i in count:
		var t := "soldier"
		if n >= 3 and i % 4 == 3:
			t = "jeep"
		if n >= 5 and i % 6 == 5:
			t = "tank"
		if n >= 8 and i % 10 == 9:
			t = "tank"
		list.append({"type": t, "delay": delay})
	return list


func start_wave() -> void:
	GameState.wave += 1
	spawn_queue = make_wave(GameState.wave)
	spawn_timer = 0.3
	wave_state = "spawning"
	start_button.visible = false


func spawn_enemy(type_key: String) -> void:
	var e := Enemy.new()
	add_child(e)
	e.setup(ENEMY_TYPES[type_key], GameState.wave, PATH_POINTS)
	e.died.connect(_on_enemy_died)
	e.reached_end.connect(_on_enemy_reached_end)
	alive_enemies += 1


func _on_enemy_died(e: Enemy) -> void:
	GameState.money += e.reward
	alive_enemies -= 1


func _on_enemy_reached_end(_e: Enemy) -> void:
	alive_enemies -= 1
	GameState.lives -= 1
	if GameState.lives <= 0:
		end_game(false)


func wave_finished() -> void:
	GameState.money += 20 + GameState.wave * 5
	if GameState.wave >= TOTAL_WAVES:
		end_game(true)
	else:
		wave_state = "prep"
		prep_timer = 10.0
		start_button.visible = true


func end_game(victory: bool) -> void:
	game_running = false
	wave_state = "over"
	msg_label.text = ""
	overlay_label.text = "胜利!你守住了防线!" if victory else "基地沦陷……"
	overlay.visible = true
	if ghost:
		ghost.queue_free()
		ghost = null


# ---------- 场景搭建 ----------

func setup_camera() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0, 26, 20)
	camera.rotation_degrees = Vector3(-52, 0, 0)
	camera.fov = 58
	add_child(camera)
	camera.make_current()


func build_environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	# 优先使用真实 HDRI 天空(来源:Poly Haven,CC0),缺失时回退到程序化天空
	var hdr_path := "res://assets/hdri/sky.hdr"
	if ResourceLoader.exists(hdr_path):
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load(hdr_path) as Texture2D
		pano.energy_multiplier = 1.0
		sky.sky_material = pano
	else:
		var sm := ProceduralSkyMaterial.new()
		sm.sky_top_color = Color(0.3, 0.48, 0.7)
		sm.sky_horizon_color = Color(0.78, 0.75, 0.66)
		sm.ground_bottom_color = Color(0.28, 0.25, 0.2)
		sm.ground_horizon_color = Color(0.78, 0.75, 0.66)
		sm.sun_angle_max = 45.0
		sky.sky_material = sm
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.4
	# 远处沙尘雾,让远景自然消失在地平线
	e.fog_enabled = true
	e.fog_light_color = Color(0.78, 0.75, 0.66)
	e.fog_density = 0.008
	e.fog_aerial_perspective = 0.5
	we.environment = e
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	# 外围荒野地面(贴图)
	var outer := MeshInstance3D.new()
	var opm := PlaneMesh.new()
	opm.size = Vector2(120, 120)
	outer.mesh = opm
	outer.material_override = textured_mat("res://assets/textures/wild/", 26.0)
	outer.position.y = -0.08
	add_child(outer)

	# 防区地面(沙土贴图)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(GRID_W * CELL, GRID_H * CELL)
	ground.mesh = pm
	ground.material_override = textured_mat("res://assets/textures/sand/", 9.0)
	add_child(ground)


## 用目录下的 Color/NormalGL/Roughness 贴图构建 PBR 材质,uv 倍率控制贴图密度
func textured_mat(dir: String, uv_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var color_t := _load_tex(dir + _first_existing(dir, ["_Color.", "_color."]))
	var normal_t := _load_tex(dir + _first_existing(dir, ["_NormalGL.", "_Normal."]))
	var rough_t := _load_tex(dir + _first_existing(dir, ["_Roughness.", "_rough."]))
	if color_t:
		m.albedo_texture = color_t
	if normal_t:
		m.normal_enabled = true
		m.normal_texture = normal_t
	if rough_t:
		m.roughness_texture = rough_t
	m.uv1_scale = Vector3(uv_scale, uv_scale, 1.0)
	m.uv1_triplanar = true
	return m


## 在目录中找出包含指定关键字的文件名
func _first_existing(dir: String, keys: Array) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	var files := d.get_files()
	for key in keys:
		for f in files:
			if f.contains(key):
				return f
	return ""


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## 防区规划网格线(半透明),帮助判断可建造位置
func build_grid() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.93, 0.85, 0.07)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var half_w := GRID_W * CELL / 2.0
	var half_h := GRID_H * CELL / 2.0
	for i in range(GRID_W + 1):
		var line := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 0.01, GRID_H * CELL)
		line.mesh = bm
		line.material_override = mat
		line.position = Vector3(-half_w + i * CELL, 0.03, 0)
		add_child(line)
	for j in range(GRID_H + 1):
		var line := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(GRID_W * CELL, 0.01, 0.04)
		line.mesh = bm
		line.material_override = mat
		line.position = Vector3(0, 0.03, -half_h + j * CELL)
		add_child(line)


func build_path_visuals() -> void:
	var mat := textured_mat("res://assets/textures/gravel/", 4.0)
	mat.albedo_color = Color(0.75, 0.7, 0.6)
	var track := StandardMaterial3D.new()
	track.albedo_color = Color(0.3, 0.26, 0.2)
	for i in range(PATH_POINTS.size() - 1):
		var a := PATH_POINTS[i]
		var b := PATH_POINTS[i + 1]
		var length := a.distance_to(b)
		var mid := Vector3((a.x + b.x) / 2.0, 0.0, (a.z + b.z) / 2.0)
		# 路基
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4.4, 0.14, length + CELL)
		seg.mesh = bm
		seg.material_override = mat
		seg.position = mid + Vector3(0, 0.07, 0)
		seg.look_at_from_position(seg.position, Vector3(b.x, 0.07, b.z), Vector3.UP)
		add_child(seg)
		# 两道车辙
		var dir := (Vector3(b.x, 0, b.z) - Vector3(a.x, 0, a.z)).normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		for s in [-0.75, 0.75]:
			var t := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(0.5, 0.02, length + CELL)
			t.mesh = tm
			t.material_override = track
			t.position = mid + side * s + Vector3(0, 0.145, 0)
			t.look_at_from_position(t.position, Vector3(t.position.x + dir.x, 0.145, t.position.z + dir.z), Vector3.UP)
			add_child(t)


func build_decorations() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	# ===== 终点基地(防御目标):混凝土指挥所 =====
	var conc := Color(0.55, 0.55, 0.5)
	var dark_conc := Color(0.38, 0.38, 0.35)
	var win := Color(0.15, 0.22, 0.28)
	var hq := box(5.0, 3.4, 5.0, conc)
	hq.position = Vector3(22, 1.7, -10)
	add_child(hq)
	var roof := box(5.4, 0.35, 5.4, dark_conc)
	roof.position = Vector3(22, 3.55, -10)
	add_child(roof)
	# 面向道路一侧(-X)的门窗
	var door := box(0.12, 1.8, 1.4, Color(0.2, 0.2, 0.18))
	door.position = Vector3(19.45, 0.9, -10)
	add_child(door)
	for wz in [-2.2, 1.2]:
		for wy in [0.9, 2.3]:
			var window := box(0.12, 0.7, 0.9, win)
			window.position = Vector3(19.45, wy, -10 + wz)
			add_child(window)
	# 侧面窗
	for wx in [-1.5, 0, 1.5]:
		var window2 := box(0.9, 0.7, 0.12, win)
		window2.position = Vector3(22 + wx, 2.3, -12.55)
		add_child(window2)
	# 楼顶雷达
	var radar_pole := cyl(0.09, 0.09, 1.6, dark_conc)
	radar_pole.position = Vector3(23.4, 4.5, -11.4)
	add_child(radar_pole)
	var dish := sph(0.55, Color(0.78, 0.78, 0.74))
	dish.position = Vector3(23.4, 5.2, -11.4)
	dish.scale = Vector3(1, 0.45, 1)
	add_child(dish)
	# 旗杆
	var pole := cyl(0.06, 0.06, 3.2, Color(0.7, 0.7, 0.7))
	pole.position = Vector3(22, 5.2, -8.6)
	add_child(pole)
	var flag := box(1.2, 0.7, 0.03, Color(0.8, 0.15, 0.1))
	flag.position = Vector3(22.65, 6.2, -8.6)
	add_child(flag)
	# 岗楼
	var tower_prop := place_model(P_WATCHTOWER, Vector3(18.0, 0, -14.0), 6.0, 150.0)
	tint_model(tower_prop, Color(0.45, 0.44, 0.38))
	# 沙袋掩体环
	for p in [Vector2(19, -7.5), Vector2(19, -12.5), Vector2(25.5, -10.5), Vector2(22, -5.0),
			Vector2(22, -15.0), Vector2(25.5, -13.5)]:
		place_model(P_SANDBAGS, Vector3(p.x, 0.0, p.y), 2.2, rng.randf_range(0, 360))
	# 补给箱与油桶
	for p in [Vector2(25.0, -6.0), Vector2(25.8, -7.6), Vector2(24.4, -7.2)]:
		place_model(P_CRATE, Vector3(p.x, 0.0, p.y), 1.3, rng.randf_range(0, 360))
	for i in 3:
		place_model(P_BARREL, Vector3(24.0 + i * 0.85, 0.0, -12.4), 1.1, rng.randf_range(0, 360))

	# ===== 起点军营 =====
	place_model(P_TENT, Vector3(-22, 0, 10), 3.4, 130.0)
	place_model(P_TENT, Vector3(-22, 0, 13.6), 2.8, 90.0)
	for i in 4:
		place_model(P_BARREL, Vector3(-19.5 + i * 0.9, 0.0, 8.2), 1.1, rng.randf_range(0, 360))
	place_model(P_SANDBAGS, Vector3(-20, 0, 11.8), 2.2, 20.0)
	place_model(P_CRATE, Vector3(-19.0, 0, 13.5), 1.3, 45.0)

	# ===== 防区外围:沙袋与铁丝网(路径缺口自动留出) =====
	build_perimeter(rng)

	# ===== 地图边缘松树林 =====
	for i in 52:
		var side := i % 4
		var p := Vector3.ZERO
		match side:
			0: p = Vector3(rng.randf_range(-58, 58), 0, rng.randf_range(-58, -18))
			1: p = Vector3(rng.randf_range(-58, 58), 0, rng.randf_range(18, 58))
			2: p = Vector3(rng.randf_range(-58, -27), 0, rng.randf_range(-18, 18))
			3: p = Vector3(rng.randf_range(27, 58), 0, rng.randf_range(-18, 18))
		place_model(P_PINE, p, rng.randf_range(4.0, 7.5), rng.randf_range(0, 360))

	# ===== 防区内:岩石与零星松树(沿防区边缘分布,避开道路与中心战场) =====
	var inner_spots := [Vector2(-20, -13), Vector2(-15, -12), Vector2(17, 13), Vector2(20, 13),
			Vector2(20, -13), Vector2(19, 4), Vector2(-21, 1), Vector2(1, 14),
			Vector2(-4, -13), Vector2(7, -13), Vector2(-8, 13), Vector2(15, 1),
			Vector2(-17, 5), Vector2(-14, 2), Vector2(11, 13), Vector2(-12, 13),
			Vector2(13, -9), Vector2(-13, -9)]
	for s in inner_spots:
		var pos := Vector3(s.x + rng.randf_range(-1, 1), 0.0, s.y + rng.randf_range(-1, 1))
		if is_path_cell(world_to_cell(pos)):
			continue
		var r := rng.randf()
		if r < 0.45:
			var rock := place_model(P_ROCKS, pos, rng.randf_range(1.2, 2.0), rng.randf_range(0, 360))
			tint_model(rock, Color(0.58, 0.55, 0.47))
		elif r < 0.62:
			var big := place_model(P_ROCKS_LARGE, pos, rng.randf_range(1.8, 2.6), rng.randf_range(0, 360))
			tint_model(big, Color(0.54, 0.51, 0.44))
		else:
			place_model(P_PINE, pos, rng.randf_range(3.5, 5.5), rng.randf_range(0, 360))

	# ===== 地面色斑(干燥/湿沙差异,让地面不那么单调) =====
	for i in 9:
		var p := Vector3(rng.randf_range(-20, 20), 0.0, rng.randf_range(-13, 13))
		if is_path_cell(world_to_cell(p)):
			continue
		var r := rng.randf_range(1.8, 3.4)
		var disc := cyl(r, r, 0.02,
				Color(0.565, 0.515, 0.385) if rng.randf() < 0.5 else Color(0.6, 0.55, 0.4))
		disc.position = p + Vector3(0, 0.02, 0)
		add_child(disc)


## 防区外围的沙袋与铁丝网,自动避开道路出入口
func build_perimeter(rng: RandomNumberGenerator) -> void:
	var ex := GRID_W * CELL / 2.0 - 0.6
	var ez := GRID_H * CELL / 2.0 - 0.6
	var along_x := Vector3(1, 0, 0)
	var along_z := Vector3(0, 0, 1)
	var t := -ex
	while t <= ex:
		perimeter_item(Vector3(t, 0, -ez), along_x, rng)
		perimeter_item(Vector3(t, 0, ez), along_x, rng)
		t += 5.0
	t = -ez + 5.0
	while t <= ez - 5.0:
		perimeter_item(Vector3(-ex, 0, t), along_z, rng)
		perimeter_item(Vector3(ex, 0, t), along_z, rng)
		t += 5.0


func perimeter_item(pos: Vector3, along: Vector3, rng: RandomNumberGenerator) -> void:
	if is_path_cell(world_to_cell(pos)):
		return
	if rng.randf() < 0.62:
		var bag := place_model_aligned(P_SANDBAGS, pos, 2.0, along)
		tint_model(bag, Color(0.52, 0.48, 0.4))
	else:
		var wire := place_model_aligned(P_BARBEDWIRE, pos, 3.2, along)
		tint_model(wire, Color(0.4, 0.38, 0.34))


# ---------- 模型加载工具 ----------

const P_SANDBAGS := "res://assets/models/prop_sandbags.glb"
const P_TENT := "res://assets/models/prop_tent.glb"
const P_BARREL := "res://assets/models/prop_barrel.glb"
const P_WATCHTOWER := "res://assets/models/prop_watchtower.glb"
const P_CRATE := "res://assets/models/prop_crate.glb"
const P_BARBEDWIRE := "res://assets/models/prop_barbedwire.glb"
const P_PINE := "res://assets/models/prop_pine.glb"
const P_TREE := "res://assets/models/detail_tree.glb"
const P_TREE_LARGE := "res://assets/models/detail_tree_large.glb"
const P_ROCKS := "res://assets/models/detail_rocks.glb"
const P_ROCKS_LARGE := "res://assets/models/detail_rocks_large.glb"
const P_DIRT := "res://assets/models/detail_dirt.glb"


## 给模型内所有网格统一换色(用于修正与场景不搭的贴图颜色)
func tint_model(n: Node, c: Color) -> void:
	if n == null:
		return
	for child in n.get_children():
		if child is MeshInstance3D:
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			(child as MeshInstance3D).material_override = m
		tint_model(child, c)


## 加载并摆放一个模型:自动缩放到 target 最长边、中心对齐 pos、底部贴地。失败返回 null。
func place_model(path: String, pos: Vector3, target: float, yaw: float = 0.0) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var model := (load(path) as PackedScene).instantiate() as Node3D
	add_child(model)
	model.rotation_degrees.y = yaw
	var a := node_aabb(model)
	var longest := maxf(a.size.x, maxf(a.size.y, a.size.z))
	if longest > 0.001:
		model.scale = Vector3.ONE * (target / longest)
	recenter_model(model, pos)
	return model


## 把模型的包围盒中心对齐到 pos 的 xz、底面贴合 pos.y
func recenter_model(m: Node3D, pos: Vector3) -> void:
	var a := node_aabb(m)
	var c := a.get_center()
	m.position += Vector3(pos.x - c.x, pos.y - a.position.y, pos.z - c.z)


## 摆放模型,并让其长边沿 along 方向(用于围墙、铁丝网)
func place_model_aligned(path: String, pos: Vector3, target: float, along: Vector3) -> Node3D:
	var m := place_model(path, pos, target, 0.0)
	if m == null:
		return null
	var a := node_aabb(m)
	var long_is_x := a.size.x >= a.size.z
	var want_x := absf(along.x) >= absf(along.z)
	if long_is_x != want_x:
		m.rotation_degrees.y += 90.0
		recenter_model(m, pos)
	return m


## 计算节点树的包围盒,结果位于 root 父节点的局部坐标系(不依赖 global_transform)
func node_aabb(root: Node3D) -> AABB:
	var stack: Array = [[root, root.transform]]
	var result := AABB()
	var has := false
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var node: Node3D = entry[0]
		var xf: Transform3D = entry[1]
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				var a: AABB = xf * mi.mesh.get_aabb()
				if has:
					result = result.merge(a)
				else:
					result = a
					has = true
		for c in node.get_children():
			if c is Node3D:
				stack.append([c, xf * (c as Node3D).transform])
	return result


# ---------- UI ----------

func build_ui() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)

	var ls := LabelSettings.new()
	ls.font_size = 22
	ls.font_color = Color.WHITE
	ls.shadow_color = Color(0, 0, 0, 0.85)
	ls.shadow_offset = Vector2(2, 2)

	# 左上角状态
	var top := VBoxContainer.new()
	top.position = Vector2(16, 10)
	cl.add_child(top)
	money_label = Label.new()
	lives_label = Label.new()
	wave_label = Label.new()
	for l in [money_label, lives_label, wave_label]:
		l.label_settings = ls
		top.add_child(l)

	# 顶部中间消息
	msg_label = Label.new()
	msg_label.label_settings = ls
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msg_label.offset_left = -300
	msg_label.offset_right = 300
	msg_label.offset_top = 10
	msg_label.offset_bottom = 40
	cl.add_child(msg_label)

	# 底部塔选择按钮
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -66
	bar.offset_bottom = -12
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 12)
	cl.add_child(bar)
	var keys := ["mg", "cannon", "missile"]
	for i in keys.size():
		var k: String = keys[i]
		var cfg: Dictionary = TOWER_TYPES[k]
		var b := Button.new()
		b.text = "%s  $%d  [%d]" % [cfg.label, cfg.cost, i + 1]
		b.custom_minimum_size = Vector2(160, 50)
		b.toggle_mode = true
		b.pressed.connect(toggle_select.bind(k))
		bar.add_child(b)
		tower_buttons[k] = b

	# 立即开始按钮
	start_button = Button.new()
	start_button.text = "立即开始下一波"
	start_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	start_button.offset_left = -216
	start_button.offset_right = -16
	start_button.offset_top = -66
	start_button.offset_bottom = -20
	start_button.visible = false
	start_button.pressed.connect(func():
		if wave_state == "prep":
			prep_timer = 0.0)
	cl.add_child(start_button)

	# 结束遮罩
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	cl.add_child(overlay)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	overlay.add_child(vbox)
	overlay_label = Label.new()
	var big := LabelSettings.new()
	big.font_size = 52
	big.font_color = Color.WHITE
	overlay_label.label_settings = big
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(overlay_label)
	var restart := Button.new()
	restart.text = "重新开始"
	restart.custom_minimum_size = Vector2(200, 56)
	restart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart.pressed.connect(func():
		GameState.reset()
		get_tree().reload_current_scene())
	vbox.add_child(restart)


func _on_money_changed(v: int) -> void:
	money_label.text = "资金:$%d" % v


func _on_lives_changed(v: int) -> void:
	lives_label.text = "基地生命:%d" % v


func _on_wave_changed(v: int) -> void:
	wave_label.text = "波次:%d / %d" % [v, TOTAL_WAVES]


func refresh_hud() -> void:
	_on_money_changed(GameState.money)
	_on_lives_changed(GameState.lives)
	_on_wave_changed(GameState.wave)


# ---------- 小工具 ----------

func make_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func box(sx: float, sy: float, sz: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(sx, sy, sz)
	mi.mesh = bm
	mi.material_override = make_mat(c)
	return mi


func cyl(rt: float, rb: float, h: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rt
	cm.bottom_radius = rb
	cm.height = h
	mi.mesh = cm
	mi.material_override = make_mat(c)
	return mi


func sph(r: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = make_mat(c)
	return mi
