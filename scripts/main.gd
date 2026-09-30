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
	"soldier": {"hp": 30.0, "speed": 3.0, "reward": 8, "kind": "soldier"},
	"jeep": {"hp": 24.0, "speed": 5.5, "reward": 10, "kind": "jeep"},
	"tank": {"hp": 160.0, "speed": 1.6, "reward": 25, "kind": "tank"},
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
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.35, 0.55, 0.8)
	sm.sky_horizon_color = Color(0.75, 0.8, 0.85)
	sm.ground_bottom_color = Color(0.3, 0.28, 0.25)
	sm.ground_horizon_color = Color(0.75, 0.8, 0.85)
	sky.sky_material = sm
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	we.environment = e
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(GRID_W * CELL, GRID_H * CELL)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.52, 0.48, 0.34)
	ground.material_override = gm
	add_child(ground)


func build_path_visuals() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.33, 0.26)
	for i in range(PATH_POINTS.size() - 1):
		var a := PATH_POINTS[i]
		var b := PATH_POINTS[i + 1]
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.8, 0.1, a.distance_to(b) + CELL)
		seg.mesh = bm
		seg.material_override = mat
		seg.position = Vector3((a.x + b.x) / 2.0, 0.05, (a.z + b.z) / 2.0)
		seg.look_at_from_position(seg.position, Vector3(b.x, 0.05, b.z), Vector3.UP)
		add_child(seg)


func build_decorations() -> void:
	# 终点基地(要防守的目标)
	var base := box(4.0, 3.0, 4.0, Color(0.45, 0.45, 0.42))
	base.position = Vector3(22, 1.5, -10)
	add_child(base)
	var roof := box(4.4, 0.3, 4.4, Color(0.3, 0.35, 0.3))
	roof.position = Vector3(22, 3.15, -10)
	add_child(roof)
	var pole := cyl(0.06, 0.06, 3.0, Color(0.7, 0.7, 0.7))
	pole.position = Vector3(22, 4.8, -10)
	add_child(pole)
	var flag := box(1.2, 0.7, 0.03, Color(0.8, 0.15, 0.1))
	flag.position = Vector3(22.65, 5.8, -10)
	add_child(flag)
	# 起点军帐
	var tent := cyl(0.05, 1.6, 1.8, Color(0.35, 0.4, 0.28))
	tent.position = Vector3(-22, 0.9, 10)
	add_child(tent)
	# 随机散布的板条箱装饰(避开路径和建造区中心)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var spots := [Vector2(-20, -14), Vector2(-16, -13), Vector2(18, 13), Vector2(20, 6),
			Vector2(-21, 2), Vector2(2, 14), Vector2(21, -3), Vector2(-2, -14)]
	for s in spots:
		var crate := box(1.2, 1.2, 1.2, Color(0.45, 0.35, 0.2))
		crate.position = Vector3(s.x + rng.randf_range(-0.5, 0.5), 0.6, s.y + rng.randf_range(-0.5, 0.5))
		crate.rotation_degrees.y = rng.randf_range(0, 90)
		add_child(crate)


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
