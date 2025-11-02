extends Node2D

# UI页面节点引用（所有父节点都是Node2D类型）
@onready var main_page = $UI_MainPage
@onready var setting_page = $UI_Setting
@onready var ingame_ui = $UI_Ingame

# 相机引用
@onready var game_camera = $Camera2D

# Gameplay节点引用（Node2D类型）
@onready var gameplay = $Ingame
@onready var gameplay_1p = get_node("Ingame/1P")
@onready var gameplay_2p = get_node("Ingame/2P")
@onready var gameplay_public = $Ingame/Public

# 按钮引用
@onready var start_btn = $UI_MainPage/StartBtn
@onready var setting_btn = $UI_MainPage/SettingBtn
@onready var quit_btn = $UI_MainPage/QuitBtn
@onready var end_drawing_btn = $Ingame/Public/EndDrawingBtn

# Setting界面控件引用
@onready var master_volume_slider = $UI_Setting/MasterVolumeSlider
@onready var master_volume_value = $UI_Setting/MasterVolumeValue
@onready var game_time_30_btn = $UI_Setting/GameTime30Btn
@onready var game_time_60_btn = $UI_Setting/GameTime60Btn
@onready var game_time_90_btn = $UI_Setting/GameTime90Btn
@onready var back_btn = $UI_Setting/BackBtn

# Ingame界面控件引用
@onready var countdown_label = $UI_Ingame/CountdownLabel
@onready var timer_label = $UI_Ingame/TimerLabel

# 结算界面控件引用
@onready var result_ui = $UI_Result
@onready var result_panel = $UI_Result/ResultPanel
@onready var result_1p_label = $UI_Result/ResultPanel/Result_1P_Label
@onready var result_2p_label = $UI_Result/ResultPanel/Result_2P_Label
@onready var result_winner_label = $UI_Result/ResultPanel/Result_Winner_Label
@onready var return_menu_btn = $UI_Result/ReturnMenuBtn

# 钥匙节点引用
@onready var key_1p = get_node("Ingame/1P/Ingame_Key_Origin_1P")
@onready var key_2p = get_node("Ingame/2P/Ingame_Key_Origin_2P")
@onready var actual_key_shape = get_node("Ingame/Public/IngameKeyShining/ActualKeyShape")

# 游戏状态
enum GameState {
	MAIN_MENU,
	SETTING,
	COUNTDOWN,  # 倒计时阶段
	PLAYING,    # 游戏进行中
	RESULT      # 结算阶段
}

var current_state: GameState = GameState.MAIN_MENU
var game_time: float = 0.0
var max_game_time: float = 30.0  # 30秒游戏时间（可在设置中修改）
var countdown_time: float = 3.0  # 倒计时3秒
var result_display_time: float = 10.0  # 结算显示10秒

# 设置数据
var master_volume: float = 80.0  # 主音量 (0-100)

# 临时存储结果数据
var cached_similarity_1p: float = 0.0
var cached_similarity_2p: float = 0.0

func _ready():
	# 验证节点是否存在
	_validate_nodes()
	
	# 绑定按钮信号（添加null检查）
	if start_btn:
		start_btn.pressed.connect(_on_start_btn_pressed)
	else:
		print("错误：StartBtn节点未找到")
		
	if setting_btn:
		setting_btn.pressed.connect(_on_setting_btn_pressed)
	else:
		print("错误：SettingBtn节点未找到")
		
	if quit_btn:
		quit_btn.pressed.connect(_on_quit_btn_pressed)
	else:
		print("错误：QuitBtn节点未找到")
		
	if end_drawing_btn:
		end_drawing_btn.pressed.connect(_on_end_drawing_btn_pressed)
	else:
		print("错误：EndDrawingBtn节点未找到")
	
	# 绑定Setting界面的信号
	if master_volume_slider:
		master_volume_slider.value_changed.connect(_on_volume_changed)
	if game_time_30_btn:
		game_time_30_btn.pressed.connect(_on_game_time_30_pressed)
	if game_time_60_btn:
		game_time_60_btn.pressed.connect(_on_game_time_60_pressed)
	if game_time_90_btn:
		game_time_90_btn.pressed.connect(_on_game_time_90_pressed)
	if back_btn:
		back_btn.pressed.connect(_on_back_btn_pressed)
	
	# 绑定返回主菜单按钮（在结算界面中）
	if return_menu_btn:
		return_menu_btn.pressed.connect(_on_return_menu_btn_pressed)
	
	# 确保Gameplay子节点初始状态为可见（父节点会控制它们的实际显示）
	if gameplay_1p:
		gameplay_1p.show()
	if gameplay_2p:
		gameplay_2p.show()
	if gameplay_public:
		gameplay_public.show()
	
	# 初始状态：显示主菜单
	_switch_to_main_menu()

func _validate_nodes():
	"""验证所有节点是否正确加载"""
	print("=== 验证节点 ===")
	print("MainPage: ", main_page != null)
	print("Setting Page: ", setting_page != null)
	print("Ingame UI: ", ingame_ui != null)
	print("Result UI: ", result_ui != null)
	print("Game Camera: ", game_camera != null)
	print("Gameplay: ", gameplay != null)
	print("Gameplay 1P: ", gameplay_1p != null)
	print("Gameplay 2P: ", gameplay_2p != null)
	print("Gameplay Public: ", gameplay_public != null)
	print("Start Button: ", start_btn != null)
	print("Setting Button: ", setting_btn != null)
	print("Quit Button: ", quit_btn != null)
	print("End Drawing Button: ", end_drawing_btn != null)
	print("Countdown Label: ", countdown_label != null)
	print("Timer Label: ", timer_label != null)
	print("Result 1P Label: ", result_1p_label != null)
	print("Result 2P Label: ", result_2p_label != null)
	print("Result Winner Label: ", result_winner_label != null)
	print("Return Menu Button: ", return_menu_btn != null)
	print("Key 1P: ", key_1p != null)
	print("Key 2P: ", key_2p != null)
	print("Actual Key Shape: ", actual_key_shape != null)
	print("===============")

func _process(delta):
	match current_state:
		GameState.COUNTDOWN:
			# 倒计时阶段
			countdown_time -= delta
			if countdown_label:
				countdown_label.text = str(int(ceil(countdown_time)))
			
			if countdown_time <= 0:
				# 倒计时结束，开始游戏
				_start_playing()
		
		GameState.PLAYING:
			# 游戏进行中计时
			game_time += delta
			
			# 更新计时器显示
			if timer_label:
				var remaining_time = max(0, max_game_time - game_time)
				timer_label.text = "时间: " + str(int(ceil(remaining_time))) + "s"
			
			# 时间到，自动结束
			if game_time >= max_game_time:
				_end_game()
		
		GameState.RESULT:
			# 结算阶段倒计时
			result_display_time -= delta
			
			# 结算时间结束，但保持显示直到玩家点击返回按钮
			# （不自动返回主菜单）

# ========== 按钮回调函数 ==========

func _on_start_btn_pressed():
	"""点击开始按钮，开始游戏"""
	print("开始游戏")
	_switch_to_game()

func _on_setting_btn_pressed():
	"""点击设置按钮"""
	print("打开设置")
	_switch_to_setting()

func _on_quit_btn_pressed():
	"""点击退出按钮"""
	print("退出游戏")
	get_tree().quit()

func _on_volume_changed(value: float):
	"""音量滑块值改变"""
	master_volume = value
	if master_volume_value:
		master_volume_value.text = str(int(value))
	# TODO: 应用音量到AudioServer
	print("音量设置为: ", value)

func _on_game_time_30_pressed():
	"""设置游戏时长为30秒"""
	max_game_time = 30.0
	print("游戏时长设置为30秒")

func _on_game_time_60_pressed():
	"""设置游戏时长为60秒"""
	max_game_time = 60.0
	print("游戏时长设置为60秒")

func _on_game_time_90_pressed():
	"""设置游戏时长为90秒"""
	max_game_time = 90.0
	print("游戏时长设置为90秒")

func _on_back_btn_pressed():
	"""返回主菜单"""
	print("返回主菜单")
	_switch_to_main_menu()

func _on_end_drawing_btn_pressed():
	"""点击End按钮（调试用），立即结束游戏"""
	print("=== 手动结束游戏（调试） ===")
	_end_game()

func _on_return_menu_btn_pressed():
	"""点击返回主菜单按钮"""
	print("返回主菜单")
	_switch_to_main_menu()

# ========== 页面切换函数 ==========

func _switch_to_main_menu():
	"""切换到主菜单"""
	current_state = GameState.MAIN_MENU
	
	# 显示主菜单UI，隐藏其他界面
	if main_page:
		main_page.show()
	if ingame_ui:
		ingame_ui.hide()
	if setting_page:
		setting_page.hide()
	if result_ui:
		result_ui.hide()
	
	# 隐藏Gameplay
	if gameplay:
		gameplay.hide()
	
	# 调整相机到主菜单位置（保持zoom = 0.285不变）
	if game_camera:
		game_camera.zoom = Vector2(0.285, 0.285)  # 保持固定缩放
		game_camera.position = Vector2(0, 0)  # 主菜单显示位置
	
	print("切换到主菜单")

func _switch_to_setting():
	"""切换到设置界面"""
	current_state = GameState.SETTING
	
	# 隐藏主菜单和游戏UI
	if main_page:
		main_page.hide()
	if ingame_ui:
		ingame_ui.hide()
	
	# 显示设置界面
	if setting_page:
		setting_page.show()
	
	# 隐藏Gameplay
	if gameplay:
		gameplay.hide()
	
	# 调整相机到设置界面位置（保持zoom = 0.285不变）
	if game_camera:
		game_camera.zoom = Vector2(0.285, 0.285)  # 保持固定缩放
		game_camera.position = Vector2(0, 0)  # 设置界面显示位置
	
	print("切换到设置界面")

func _switch_to_game():
	"""切换到游戏界面，开始倒计时"""
	current_state = GameState.COUNTDOWN
	countdown_time = 3.0  # 重置倒计时为3秒
	game_time = 0.0
	
	# 隐藏主菜单UI和设置界面
	if main_page:
		main_page.hide()
	if setting_page:
		setting_page.hide()
	
	# 显示游戏UI和Gameplay
	if ingame_ui:
		ingame_ui.show()
	if gameplay:
		gameplay.show()
	
	# 确保Gameplay的子节点也显示（1P、2P、Public）
	if gameplay_1p:
		gameplay_1p.show()
	if gameplay_2p:
		gameplay_2p.show()
	if gameplay_public:
		gameplay_public.show()
	
	# 显示倒计时，隐藏计时器和结算界面
	if countdown_label:
		countdown_label.show()
		countdown_label.text = "3"
	if timer_label:
		timer_label.hide()
	if result_ui:
		result_ui.hide()
	
	# 调整相机到游戏区域（保持zoom = 0.285不变）
	if game_camera:
		game_camera.zoom = Vector2(0.285, 0.285)  # 保持固定缩放
		game_camera.position = Vector2(0, 0)  # 游戏区域显示位置
	
	# 重置游戏状态
	_reset_game()
	
	print("切换到游戏界面 - 倒计时开始")

func _start_playing():
	"""倒计时结束，开始游戏"""
	current_state = GameState.PLAYING
	game_time = 0.0
	
	# 隐藏倒计时，显示计时器
	if countdown_label:
		countdown_label.hide()
	if timer_label:
		timer_label.show()
		timer_label.text = "时间: " + str(int(max_game_time)) + "s"
	
	# 启用激光控制
	_enable_laser_control(true)
	
	print("游戏开始 - 制作时间: ", max_game_time, "秒")

func _end_game():
	"""游戏时间结束，进入结算"""
	current_state = GameState.RESULT
	result_display_time = 10.0  # 重置结算显示时间为10秒
	
	# 禁用激光控制
	_enable_laser_control(false)
	
	# 隐藏计时器
	if timer_label:
		timer_label.hide()
	
	# 显示"计算中"提示
	if countdown_label:
		countdown_label.show()
		countdown_label.text = "计算中..."
	
	print("游戏结束 - 开始计算相似度")
	
	# 等待一帧，让UI更新
	await get_tree().process_frame
	
	# 计算相似度（可能会有短暂卡顿）
	print("正在计算1P相似度...")
	cached_similarity_1p = _calculate_similarity(key_1p)
	
	# 等待一帧
	await get_tree().process_frame
	
	print("正在计算2P相似度...")
	cached_similarity_2p = _calculate_similarity(key_2p)
	
	# 隐藏计算中提示
	if countdown_label:
		countdown_label.hide()
	
	# 显示结果
	_show_result(cached_similarity_1p, cached_similarity_2p)
	
	print("计算完成 - 显示结算")

func _enable_laser_control(enabled: bool):
	"""启用/禁用激光控制"""
	# 这里可以通过信号或直接访问LaserController来启用/禁用控制
	# 目前保留为空，激光默认始终可控
	pass

func _reset_game():
	"""重置游戏状态"""
	# TODO: 重置钥匙到初始状态
	# 目前KeyBlade脚本没有reset方法，可能需要重新加载场景或添加reset功能
	print("游戏状态已重置")

# ========== 相似度计算 ==========

func _calculate_similarity(key_body: RigidBody2D) -> float:
	"""计算钥匙与目标形状的相似度"""
	if not key_body or not key_body.has_method("get_cut_polygon_from_image"):
		print("警告：无法获取钥匙多边形")
		return 0.0
	
	# 从被切割后的Image中提取多边形轮廓
	var key_polygon = key_body.get_cut_polygon_from_image()
	var actual_polygon = actual_key_shape.polygon
	
	print("钥匙多边形顶点数: ", key_polygon.size())
	print("实际形状多边形顶点数: ", actual_polygon.size())
	
	if key_polygon.size() < 3:
		print("警告：钥匙多边形顶点数不足")
		return 0.0
	
	# 计算相似度（简化版本）
	var similarity = _compare_polygons(key_polygon, actual_polygon)
	
	return similarity

func _compare_polygons(polygon1: PackedVector2Array, polygon2: PackedVector2Array) -> float:
	"""对比两个多边形的相似度（优化版本）"""
	# 计算面积
	var area1 = _polygon_area(polygon1)
	var area2 = _polygon_area(polygon2)
	
	print("多边形面积 - 玩家: %.2f, 目标: %.2f" % [area1, area2])
	
	# 面积相似度
	var area_diff_ratio = abs(area1 - area2) / max(area1, area2) if max(area1, area2) > 0 else 1.0
	var area_similarity = 1.0 - area_diff_ratio
	
	# 优化：点包含检测使用采样，不检测所有点
	# 只检测部分采样点来估算重合度，大大减少计算量
	var sample_count = 50  # 每个多边形最多采样50个点
	var points_1_in_2 = 0
	var points_2_in_1 = 0
	
	# 采样polygon1的点
	var step1 = max(1, int(polygon1.size() / float(sample_count)))
	var sampled_count1 = 0
	for i in range(0, polygon1.size(), step1):
		if _is_point_in_polygon(polygon1[i], polygon2):
			points_1_in_2 += 1
		sampled_count1 += 1
	
	# 采样polygon2的点
	var step2 = max(1, int(polygon2.size() / float(sample_count)))
	var sampled_count2 = 0
	for i in range(0, polygon2.size(), step2):
		if _is_point_in_polygon(polygon2[i], polygon1):
			points_2_in_1 += 1
		sampled_count2 += 1
	
	var inclusion_1_to_2 = float(points_1_in_2) / sampled_count1 if sampled_count1 > 0 else 0.0
	var inclusion_2_to_1 = float(points_2_in_1) / sampled_count2 if sampled_count2 > 0 else 0.0
	var bidirectional_similarity = (inclusion_1_to_2 + inclusion_2_to_1) / 2.0
	
	print("重合度 - 玩家→目标: %.1f%%, 目标→玩家: %.1f%%" % [inclusion_1_to_2 * 100, inclusion_2_to_1 * 100])
	
	# 综合相似度（面积权重40%，重合度权重60%）
	var final_similarity = (area_similarity * 0.4 + bidirectional_similarity * 0.6)
	
	return clamp(final_similarity, 0.0, 1.0)

func _polygon_area(polygon: PackedVector2Array) -> float:
	"""计算多边形面积"""
	if polygon.size() < 3:
		return 0.0
	
	var area = 0.0
	for i in range(polygon.size()):
		var j = (i + 1) % polygon.size()
		area += polygon[i].x * polygon[j].y
		area -= polygon[j].x * polygon[i].y
	
	return abs(area) / 2.0

func _is_point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	"""判断点是否在多边形内"""
	if polygon.size() < 3:
		return false
	
	var inside = false
	var j = polygon.size() - 1
	
	for i in range(polygon.size()):
		var pi = polygon[i]
		var pj = polygon[j]
		
		if ((pi.y > point.y) != (pj.y > point.y)) and \
		   (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x):
			inside = !inside
		j = i
	
	return inside

# ========== 结果显示 ==========

func _show_result(similarity_1p: float, similarity_2p: float):
	"""显示比赛结果"""
	var percentage_1p = int(similarity_1p * 100)
	var percentage_2p = int(similarity_2p * 100)
	
	print("========== 游戏结束 ==========")
	print("1P 相似度: %d%%" % percentage_1p)
	print("2P 相似度: %d%%" % percentage_2p)
	
	# 判断胜者
	var winner_text = ""
	if percentage_1p > percentage_2p:
		winner_text = "1P 获胜！"
		print("🏆 1P 获胜！")
	elif percentage_2p > percentage_1p:
		winner_text = "2P 获胜！"
		print("🏆 2P 获胜！")
	else:
		winner_text = "平局！"
		print("🤝 平局！")
	print("=============================")
	
	# 显示结算界面
	if result_ui:
		result_ui.show()
	
	# 更新结算文本
	if result_1p_label:
		result_1p_label.text = "1P: %d%%" % percentage_1p
	if result_2p_label:
		result_2p_label.text = "2P: %d%%" % percentage_2p
	if result_winner_label:
		result_winner_label.text = winner_text
	
	# 显示返回主菜单按钮
	if return_menu_btn:
		return_menu_btn.show()
