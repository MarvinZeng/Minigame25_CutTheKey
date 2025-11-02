extends RigidBody2D

@export var move_speed: float = 300.0
@export var laser_active: bool = true
@export var cutting_radius: float = 15.0

var velocity: Vector2 = Vector2.ZERO
var previous_position: Vector2
var last_cut_position: Vector2 = Vector2.ZERO
var cut_cooldown: float = 0.0
var min_cut_distance: float = 5.0  # 最小切割距离，让切割更连续（减少以提高连续性）
var was_touching_key: bool = false  # 上一帧是否接触钥匙

# 移动距离统计（用于胜负判定）
var total_move_distance: float = 0.0

# 倒计时期间限制移动
var is_countdown_active: bool = false

func _ready():
	# 添加到1P激光分组
	add_to_group("laser_1p")
	
	# 设置为字符模式（不受物理影响，手动控制）
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	freeze = true
	# 禁用物理碰撞层，避免推动钥匙（设置为0表示不参与碰撞）
	collision_layer = 0
	# 但仍可以通过代码检测碰撞
	previous_position = global_position

func _physics_process(delta):
	if not laser_active:
		return
	
	# WASD输入（1P控制，不支持方向键）
	velocity = Vector2.ZERO
	
	if Input.is_key_pressed(KEY_W):
		velocity.y -= 1
	if Input.is_key_pressed(KEY_S):
		velocity.y += 1
	if Input.is_key_pressed(KEY_A):
		velocity.x -= 1
	if Input.is_key_pressed(KEY_D):
		velocity.x += 1
	
	# 归一化并应用速度
	if velocity.length() > 0:
		velocity = velocity.normalized() * move_speed
		var old_pos = position
		var new_pos = position + velocity * delta
		
		# 倒计时期间检测是否会进入钥匙区域
		if is_countdown_active and _would_enter_key_area(new_pos):
			# 不允许移动
			velocity = Vector2.ZERO
		else:
			# 允许移动
			position = new_pos
			# 累加移动距离
			total_move_distance += old_pos.distance_to(position)
	else:
		velocity = Vector2.ZERO
	
	# 检查是否与钥匙接触并进行切割（降低频率以提高性能）
	cut_cooldown -= delta
	if cut_cooldown <= 0:
		check_cutting()
		cut_cooldown = 0.033  # 约30次/秒，提高检测频率以保持连续性
	
	previous_position = global_position

func check_cutting():
	# 直接通过分组查找1P钥匙节点
	var key = get_tree().get_first_node_in_group("key_1p")
	if not key:
		# 如果没找到，通过名称查找
		var parent = get_parent()
		if parent:
			key = parent.find_child("Ingame_Key_Origin_1P", true, false)
	
	if not key or not key is RigidBody2D:
		return
	
	# 获取钥匙的碰撞形状
	var key_collision = key.get_node_or_null("CollisionShape2D")
	if not key_collision or not key_collision.shape:
		return
	
	# 使用物理空间检测激光是否与钥匙的碰撞形状重叠
	var space_state = get_world_2d().direct_space_state
	
	# 获取激光的碰撞形状位置（这是实际检测位置）
	var laser_collision = get_node_or_null("CollisionShape2D")
	var laser_detection_pos: Vector2
	if laser_collision:
		# 使用碰撞形状的全局位置（考虑偏移）
		laser_detection_pos = laser_collision.global_position
	else:
		# 如果没有碰撞形状，使用激光主体位置
		laser_detection_pos = global_position
	
	var is_touching = false
	
	# 方法1：使用激光的碰撞形状进行形状查询（最准确）
	if laser_collision and laser_collision.shape:
		var query = PhysicsShapeQueryParameters2D.new()
		query.shape = laser_collision.shape
		# 使用碰撞形状的实际全局位置
		query.transform = Transform2D(0, laser_detection_pos)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.collision_mask = 0xFFFFFFFF
		
		var results = space_state.intersect_shape(query)
		for result in results:
			if result.collider == key:
				is_touching = true
				# 激光与钥匙的碰撞形状接触，触发切割
				# 限制切割频率：只有当激光移动了一定距离才切割
				var distance_moved = laser_detection_pos.distance_to(last_cut_position)
				if distance_moved >= min_cut_distance:
					if key.has_method("cut_at_position"):
						key.cut_at_position(laser_detection_pos, cutting_radius)
					last_cut_position = laser_detection_pos
				break  # 找到钥匙，跳出循环
	
	# 方法2：如果形状查询没找到，使用点查询（使用碰撞形状的位置，不是主体位置）
	if not is_touching:
		var query_point = PhysicsPointQueryParameters2D.new()
		query_point.position = laser_detection_pos  # 使用碰撞形状的位置，不是global_position
		query_point.collide_with_areas = false
		query_point.collide_with_bodies = true
		query_point.collision_mask = 0xFFFFFFFF
		
		var point_results = space_state.intersect_point(query_point)
		for result in point_results:
			if result.collider == key:
				is_touching = true
				# 激光位置在钥匙的碰撞形状内，触发切割
				var distance_moved = laser_detection_pos.distance_to(last_cut_position)
				if distance_moved >= min_cut_distance:
					if key.has_method("cut_at_position"):
						key.cut_at_position(laser_detection_pos, cutting_radius)
					last_cut_position = laser_detection_pos
				break  # 找到钥匙，跳出循环
	
	# 检测激光是否刚离开钥匙（从接触到不接触）
	if was_touching_key and not is_touching:
		# 激光刚离开钥匙，触发最终分割检查
		if key.has_method("finalize_cut"):
			key.finalize_cut()
	
	# 更新状态
	was_touching_key = is_touching

func _would_enter_key_area(test_position: Vector2) -> bool:
	"""检测指定位置是否会进入钥匙区域"""
	# 查找1P钥匙
	var key = get_tree().get_first_node_in_group("key_1p")
	if not key:
		return false
	
	# 获取钥匙的碰撞形状
	var key_collision = key.get_node_or_null("CollisionShape2D")
	if not key_collision or not key_collision.shape:
		return false
	
	# 使用物理查询检测测试位置是否与钥匙重叠
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = test_position
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var results = space_state.intersect_point(query, 1)
	
	# 检查是否与钥匙碰撞
	for result in results:
		if result.collider == key:
			return true
	
	return false
