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
@onready var countdown_label = $Ingame/Public/CountdownLabel
@onready var countdown_overlay = $Ingame/Public/CountdownOverlay
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

# 音频播放器引用
@onready var bgm_player = $BGMPlayer
@onready var click_sound_player = $ClickSoundPlayer
@onready var button_sound_player = $ButtonSoundPlayer
@onready var countdown_sound_player = $CountdownSoundPlayer

# 粒子效果
const SPARK_SCENE = preload("res://Scenes/spark.tscn")

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
var countdown_time: float = 4.0  # 倒计时4秒（3秒倒计时 + 1秒"开始"）
var result_display_time: float = 10.0  # 结算显示10秒
var countdown_overlay_removed: bool = false  # 标记遮罩是否已移除

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
	
	# 初始化音频系统
	_setup_audio()
	
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
	print("Countdown Overlay: ", countdown_overlay != null)
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
			# 倒计时阶段（4秒：3, 2, 1, 开始）
			countdown_time -= delta
			if countdown_label:
				if countdown_time > 3.0:
					countdown_label.text = "3"
				elif countdown_time > 2.0:
					countdown_label.text = "2"
				elif countdown_time > 1.0:
					countdown_label.text = "1"
				else:
					countdown_label.text = "开始"
					# 显示"开始"时（前3秒过后），移除遮罩和限制
					if not countdown_overlay_removed:
						print("⏰ 倒计时进入第4秒（显示\"开始\"）")
						if countdown_overlay:
							countdown_overlay.hide()
							print("✅ CountdownOverlay已隐藏")
						else:
							print("❌ 错误：countdown_overlay节点不存在！")
						_set_lasers_countdown_mode(false)
						countdown_overlay_removed = true
						print("✨ 显示\"开始\" - 遮罩消失，激光解除限制")
			
			if countdown_time <= 0:
				# 倒计时结束，开始游戏
				_start_playing()
		
		GameState.PLAYING:
			# 游戏进行中计时
			game_time += delta
			
			# 更新计时器显示
			if timer_label:
				var remaining_time = max(0, max_game_time - game_time)
				timer_label.text = "剩余时间: " + str(int(ceil(remaining_time))) + "s"
			
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
	_play_button_sound()
	print("开始游戏")
	_switch_to_game()

func _on_setting_btn_pressed():
	"""点击设置按钮"""
	_play_button_sound()
	print("打开设置")
	_switch_to_setting()

func _on_quit_btn_pressed():
	"""点击退出按钮"""
	_play_button_sound()
	print("退出游戏")
	get_tree().quit()

func _on_volume_changed(value: float):
	"""音量滑块值改变"""
	master_volume = value
	if master_volume_value:
		master_volume_value.text = str(int(value))
	
	# 应用音量到AudioServer（0-100 转换为 -80dB 到 0dB）
	var volume_db = -80.0 + (value / 100.0) * 80.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), volume_db)
	print("音量设置为: %d%% (%.1fdB)" % [int(value), volume_db])

func _on_game_time_30_pressed():
	"""设置游戏时长为30秒"""
	_play_button_sound()
	max_game_time = 30.0
	print("游戏时长设置为30秒")

func _on_game_time_60_pressed():
	"""设置游戏时长为60秒"""
	_play_button_sound()
	max_game_time = 60.0
	print("游戏时长设置为60秒")

func _on_game_time_90_pressed():
	"""设置游戏时长为90秒"""
	_play_button_sound()
	max_game_time = 90.0
	print("游戏时长设置为90秒")

func _on_back_btn_pressed():
	"""返回主菜单"""
	_play_button_sound()
	print("返回主菜单")
	_switch_to_main_menu()

func _on_end_drawing_btn_pressed():
	"""点击End按钮（调试用），立即结束游戏"""
	_play_button_sound()
	print("=== 手动结束游戏（调试） ===")
	_end_game()

func _on_return_menu_btn_pressed():
	"""点击返回主菜单按钮"""
	_play_button_sound()
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
	if countdown_overlay:
		countdown_overlay.hide()
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
	countdown_time = 4.0  # 重置倒计时为4秒（3秒倒计时 + 1秒"开始"）
	game_time = 0.0
	countdown_overlay_removed = false  # 重置遮罩移除标记
	
	# 播放倒计时音效
	if countdown_sound_player:
		countdown_sound_player.play()
		print("🔊 播放倒计时音效")
	
	# 设置激光倒计时状态（限制移动，前3秒）
	_set_lasers_countdown_mode(true)
	
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
	if countdown_overlay:
		countdown_overlay.show()
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
	
	# 隐藏倒计时和遮罩，显示计时器
	if countdown_label:
		countdown_label.hide()
	if countdown_overlay:
		countdown_overlay.hide()
		print("🔒 游戏开始 - 确保CountdownOverlay已隐藏")
	if timer_label:
		timer_label.show()
		timer_label.text = "剩余时间: " + str(int(max_game_time)) + "s"
	
	# 启用激光控制（实际上在第4秒时已经启用）
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
	
	print("游戏结束 - 开始计算结果")
	
	# 等待一帧，让UI更新
	await get_tree().process_frame
	
	# 获取1P和2P激光的移动距离
	var laser_1p = get_tree().get_first_node_in_group("laser_1p")
	var laser_2p = get_tree().get_first_node_in_group("laser_2p")
	
	var distance_1p = 0.0
	var distance_2p = 0.0
	
	if laser_1p and laser_1p.has_method("get"):
		distance_1p = laser_1p.get("total_move_distance")
	if laser_2p and laser_2p.has_method("get"):
		distance_2p = laser_2p.get("total_move_distance")
	
	print("📊 移动距离统计 - 1P: %.1f, 2P: %.1f" % [distance_1p, distance_2p])
	
	# 基于移动距离计算胜负和显示数值
	var result_data = _calculate_result_by_distance(distance_1p, distance_2p)
	cached_similarity_1p = result_data["display_1p"]
	cached_similarity_2p = result_data["display_2p"]
	
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

# ========== 胜负判定 ==========

func _calculate_result_by_distance(distance_1p: float, distance_2p: float) -> Dictionary:
	"""基于移动距离计算胜负和显示数值"""
	var total_distance = distance_1p + distance_2p
	if total_distance < 100.0:
		# 两人都几乎不动，平局
		return {
			"display_1p": 0.50,
			"display_2p": 0.50,
			"winner": 0
		}
	
	# 计算距离比例
	var ratio_1p = distance_1p / total_distance
	var ratio_2p = distance_2p / total_distance
	
	# 确定获胜方（新规则：75%距离多的获胜，15%距离少的获胜，10%随机）
	var winner = 0
	var rand_value = randf()
	
	if distance_1p > distance_2p:
		# 1P移动更多
		if rand_value < 0.75:
			winner = 1  # 75%概率1P获胜
		elif rand_value < 0.90:
			winner = 2  # 15%概率2P逆袭
		else:
			winner = 1 if randf() < 0.5 else 2  # 10%随机
	elif distance_2p > distance_1p:
		# 2P移动更多
		if rand_value < 0.75:
			winner = 2  # 75%概率2P获胜
		elif rand_value < 0.90:
			winner = 1  # 15%概率1P逆袭
		else:
			winner = 1 if randf() < 0.5 else 2  # 10%随机
	else:
		# 距离完全相同，随机决定
		winner = 1 if randf() < 0.5 else 2
	
	# 生成显示数值（基于移动距离比例缩放，范围30%-95%）
	# 移动距离越多，完成度越高
	var display_1p = 0.0
	var display_2p = 0.0
	
	# 基础分数基于距离比例（30%-95%）
	# ratio = 0.0 → 30%, ratio = 1.0 → 95%
	var base_score_1p = 0.30 + ratio_1p * 0.65
	var base_score_2p = 0.30 + ratio_2p * 0.65
	
	# 获胜方额外加分，失败方减分
	var winner_bonus = 0.08  # 获胜方+8%
	var loser_penalty = 0.05  # 失败方-5%
	
	if winner == 1:
		# 1P获胜
		display_1p = base_score_1p + winner_bonus
		display_2p = base_score_2p - loser_penalty
	elif winner == 2:
		# 2P获胜
		display_2p = base_score_2p + winner_bonus
		display_1p = base_score_1p - loser_penalty
	else:
		# 平局（不应该发生）
		display_1p = base_score_1p
		display_2p = base_score_2p
	
	# 随机波动 ±2%
	display_1p += (randf() - 0.5) * 0.04
	display_2p += (randf() - 0.5) * 0.04
	
	# 确保数值在30%-95%范围内
	display_1p = clamp(display_1p, 0.30, 0.95)
	display_2p = clamp(display_2p, 0.30, 0.95)
	
	# 确保获胜方数值一定大于失败方
	if winner == 1 and display_1p <= display_2p:
		display_1p = display_2p + 0.03
	elif winner == 2 and display_2p <= display_1p:
		display_2p = display_1p + 0.03
	
	# 再次限制范围
	display_1p = clamp(display_1p, 0.30, 0.95)
	display_2p = clamp(display_2p, 0.30, 0.95)
	
	print("🎮 判定结果 - 获胜方: %s, 显示分数: 1P=%.1f%%, 2P=%.1f%%" % [
		"1P" if winner == 1 else "2P",
		display_1p * 100,
		display_2p * 100
	])
	
	return {
		"display_1p": display_1p,
		"display_2p": display_2p,
		"winner": winner
	}

# ========== 相似度计算（已弃用，保留兼容）==========

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
	"""对比两个多边形的相似度（增强版本 - 多维度评分）"""
	# 1. 面积相似度（30%权重）
	var area1 = _polygon_area(polygon1)
	var area2 = _polygon_area(polygon2)
	print("📊 面积 - 玩家: %.2f, 目标: %.2f" % [area1, area2])
	
	var area_diff_ratio = abs(area1 - area2) / max(area1, area2) if max(area1, area2) > 0 else 1.0
	var area_similarity = 1.0 - area_diff_ratio
	
	# 2. 周长相似度（10%权重）- 检测轮廓复杂度
	var perimeter1 = _polygon_perimeter(polygon1)
	var perimeter2 = _polygon_perimeter(polygon2)
	var perimeter_diff_ratio = abs(perimeter1 - perimeter2) / max(perimeter1, perimeter2) if max(perimeter1, perimeter2) > 0 else 1.0
	var perimeter_similarity = 1.0 - perimeter_diff_ratio
	
	# 3. 重合度检测（40%权重）- 使用更密集的采样
	var sample_count = 100  # 增加采样点数，提高精度
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
	var overlap_similarity = (inclusion_1_to_2 + inclusion_2_to_1) / 2.0
	
	# 4. 边界距离相似度（20%权重）- 检测边界匹配程度
	var boundary_similarity = _calculate_boundary_distance_similarity(polygon1, polygon2)
	
	print("📊 重合度 - 玩家→目标: %.1f%%, 目标→玩家: %.1f%%" % [inclusion_1_to_2 * 100, inclusion_2_to_1 * 100])
	print("📊 周长相似度: %.1f%%, 边界匹配度: %.1f%%" % [perimeter_similarity * 100, boundary_similarity * 100])
	
	# 综合相似度（多维度加权）
	# 面积30% + 周长10% + 重合度40% + 边界匹配20%
	var final_similarity = (
		area_similarity * 0.30 + 
		perimeter_similarity * 0.10 + 
		overlap_similarity * 0.40 + 
		boundary_similarity * 0.20
	)
	
	print("✨ 综合相似度: %.1f%% (面积:%.1f%% 周长:%.1f%% 重合:%.1f%% 边界:%.1f%%)" % [
		final_similarity * 100,
		area_similarity * 100,
		perimeter_similarity * 100,
		overlap_similarity * 100,
		boundary_similarity * 100
	])
	
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

func _polygon_perimeter(polygon: PackedVector2Array) -> float:
	"""计算多边形周长"""
	if polygon.size() < 2:
		return 0.0
	
	var perimeter = 0.0
	for i in range(polygon.size()):
		var j = (i + 1) % polygon.size()
		perimeter += polygon[i].distance_to(polygon[j])
	
	return perimeter

func _calculate_boundary_distance_similarity(polygon1: PackedVector2Array, polygon2: PackedVector2Array) -> float:
	"""计算边界距离相似度（检测边界的匹配程度）"""
	if polygon1.size() < 3 or polygon2.size() < 3:
		return 0.0
	
	# 采样两个多边形的边界点，计算最近点距离
	var sample_count = 50  # 采样点数
	var total_distance_1_to_2 = 0.0
	var total_distance_2_to_1 = 0.0
	
	# polygon1的点到polygon2的平均最短距离
	var step1 = max(1, int(polygon1.size() / float(sample_count)))
	var count1 = 0
	for i in range(0, polygon1.size(), step1):
		var min_dist = INF
		for j in range(polygon2.size()):
			var dist = polygon1[i].distance_to(polygon2[j])
			min_dist = min(min_dist, dist)
		total_distance_1_to_2 += min_dist
		count1 += 1
	
	# polygon2的点到polygon1的平均最短距离
	var step2 = max(1, int(polygon2.size() / float(sample_count)))
	var count2 = 0
	for i in range(0, polygon2.size(), step2):
		var min_dist = INF
		for j in range(polygon1.size()):
			var dist = polygon2[i].distance_to(polygon1[j])
			min_dist = min(min_dist, dist)
		total_distance_2_to_1 += min_dist
		count2 += 1
	
	var avg_distance_1_to_2 = total_distance_1_to_2 / count1 if count1 > 0 else 1000.0
	var avg_distance_2_to_1 = total_distance_2_to_1 / count2 if count2 > 0 else 1000.0
	var avg_distance = (avg_distance_1_to_2 + avg_distance_2_to_1) / 2.0
	
	# 归一化：距离越小，相似度越高
	# 假设300像素是完全不匹配，0像素是完全匹配
	var max_acceptable_distance = 300.0
	var normalized_distance = clamp(avg_distance / max_acceptable_distance, 0.0, 1.0)
	var similarity = 1.0 - normalized_distance
	
	return similarity

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
		result_1p_label.text = "1P完成度: %d%%" % percentage_1p
	if result_2p_label:
		result_2p_label.text = "2P完成度: %d%%" % percentage_2p
	if result_winner_label:
		result_winner_label.text = winner_text
	
	# 显示返回主菜单按钮
	if return_menu_btn:
		return_menu_btn.show()

# ========== 音频系统 ==========

func _setup_audio():
	"""初始化音频系统"""
	# BGM循环播放
	if bgm_player:
		bgm_player.volume_db = -6.0  # 50%音量约等于-6dB
		bgm_player.finished.connect(_on_bgm_finished)
		print("✅ BGM已初始化（音量50%，循环播放）")
	
	print("🔊 音频系统已初始化")

func _on_bgm_finished():
	"""BGM播放完毕时重新播放（实现循环）"""
	if bgm_player:
		bgm_player.play()

func _input(event):
	"""监听输入事件（鼠标点击）"""
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_play_click_sound()
			# 在鼠标点击位置生成火花效果
			_spawn_click_spark(event.position)

func _play_click_sound():
	"""播放鼠标点击音效"""
	if click_sound_player and not click_sound_player.playing:
		click_sound_player.play()

func _play_button_sound():
	"""播放按钮点击音效"""
	if button_sound_player:
		button_sound_player.play()

func _spawn_click_spark(screen_position: Vector2):
	"""在鼠标点击位置生成火花效果"""
	if not game_camera:
		return
	
	# 将屏幕坐标转换为世界坐标
	var world_position = game_camera.get_global_mouse_position()
	
	# 创建火花粒子
	var spark = SPARK_SCENE.instantiate()
	spark.global_position = world_position
	spark.emitting = true
	
	# 添加到场景
	get_tree().current_scene.add_child(spark)
	
	# 粒子播放完毕后自动删除
	spark.finished.connect(func(): spark.queue_free())

func _set_lasers_countdown_mode(is_countdown: bool):
	"""设置激光的倒计时模式（限制移动范围）"""
	var laser_1p = get_tree().get_first_node_in_group("laser_1p")
	var laser_2p = get_tree().get_first_node_in_group("laser_2p")
	
	if laser_1p and "is_countdown_active" in laser_1p:
		laser_1p.is_countdown_active = is_countdown
	
	if laser_2p and "is_countdown_active" in laser_2p:
		laser_2p.is_countdown_active = is_countdown
	
	if is_countdown:
		print("🚫 倒计时期间 - 激光不能进入钥匙区域")
	else:
		print("✅ 倒计时结束 - 激光可以自由移动")
