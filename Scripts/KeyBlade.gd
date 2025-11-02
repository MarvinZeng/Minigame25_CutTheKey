extends RigidBody2D

@onready var sprite: Sprite2D = $Image

# 预加载火花特效场景
const SPARK_SCENE = preload("res://Scenes/spark.tscn")

# 使用遮罩图片实现切割效果（保留用于视觉）
var cut_mask: Image
var original_texture: Texture2D
var original_image: Image

var is_cut: bool = false
var cut_trail: Array[Vector2] = []  # 切割轨迹（像素坐标）
var cut_path_history: Array[Vector2] = []  # 完整的切割路径历史
var current_texture: ImageTexture  # 当前显示的纹理
var texture_update_timer: float = 0.0
var texture_update_delay: float = 0.15  # 每0.15秒更新一次纹理（减少更新频率，提升性能）
var needs_update: bool = false
# 脏区域：记录需要更新的矩形区域 [min_x, min_y, max_x, max_y]
var dirty_rect: Rect2i = Rect2i()
var has_dirty_rect: bool = false

# 多边形物理切割相关
var polygon_shape  # 当前多边形的物理形状（如果可用）
var current_polygon: PackedVector2Array  # 当前多边形的顶点（本地坐标）
var cut_path_world: Array[Vector2] = []  # 世界坐标下的切割路径
var cut_path_start: Vector2  # 切割路径起点（本地坐标）
var min_cut_length: float = 150.0  # 最小切割长度才触发分割（降低阈值）
var is_cutting: bool = false  # 是否正在切割
var last_split_check_time: float = 0.0  # 上次检查分割的时间
var split_check_interval: float = 0.8  # 分割检查间隔（秒，降低频率减少卡顿）
var min_fragment_area: float = 5000.0  # 最小碎片面积（提高阈值，减少小碎片）
var polygon_shape_template  # 模板实例，用于创建新的形状
var enable_fragment_split: bool = false  # 禁用碎片分离（只保留橡皮擦效果）
var use_simple_rect_for_split: bool = false  # 使用简单矩形进行分割测试（调试用）

# 动态多边形更新相关
var needs_polygon_update: bool = false  # 是否需要更新多边形
var polygon_update_timer: float = 0.0  # 多边形更新计时器
var polygon_update_delay: float = 1.0  # 多边形更新延迟（增加到1.0秒，大幅减少更新频率）
var last_polygon_update_time: float = 0.0  # 上次更新多边形的时间

# 火花特效相关
var spark_spawn_interval: float = 0.12  # 火花生成间隔（秒）约8次/秒
var last_spark_time: float = 0.0  # 上次生成火花的时间

func _ready():
	# 根据节点名称添加到不同的分组
	var path_str = str(get_path())
	if "1P" in path_str or "1p" in name.to_lower():
		add_to_group("key_1p")
	elif "2P" in path_str or "2p" in name.to_lower():
		add_to_group("key_2p")
	else:
		# 默认行为
		add_to_group("key")
	
	# 确保钥匙不会掉落 - 设置为静态模式
	gravity_scale = 0.0
	lock_rotation = true  # 锁定旋转
	# 设置为 Kinematic 模式（不受物理影响，但可以检测碰撞）
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	freeze = true
	# 物理设置已完成
	
	# 不再需要初始化多边形（已禁用物理分割功能）
	# initialize_polygon()
	
	if sprite and sprite.texture:
		original_texture = sprite.texture
		
		# 尝试获取图片
		var image = null
		if original_texture is ImageTexture:
			image = (original_texture as ImageTexture).get_image()
		elif original_texture.has_method("get_image"):
			image = original_texture.get_image()
		
		# 如果还是无法获取，尝试从资源路径加载
		if not image:
			var texture_path = original_texture.resource_path
			if texture_path:
				var loaded_texture = load(texture_path)
				if loaded_texture and loaded_texture is ImageTexture:
					image = (loaded_texture as ImageTexture).get_image()
		
		if image:
			original_image = image.duplicate()
			# 创建遮罩图片（白色表示保留区域，透明表示切割区域）
			var img_size = original_image.get_size()
			cut_mask = Image.create(img_size.x, img_size.y, false, Image.FORMAT_RGBA8)
			cut_mask.fill(Color.WHITE)
			
			# 创建初始纹理
			current_texture = ImageTexture.new()
			current_texture.set_image(original_image.duplicate())
			sprite.texture = current_texture
			print("✅ [%s] 钥匙初始化成功（橡皮擦模式 + 火花特效）" % name)

func cut_at_position(world_position: Vector2, radius: float = 20.0):
	if not original_image or not cut_mask:
		print("❌ 切割失败：原始图片或遮罩未初始化")
		return
	
	# 首次切割时打印信息
	if not is_cutting:
		print("🔪 [%s] 开始切割" % name)
	
	# 将世界坐标转换为相对于Image（Sprite2D）的本地坐标
	# Image是Ingame_Key_Origin的子节点，需要从世界坐标->钥匙本地坐标->Image本地坐标
	var sprite_local_pos = sprite.to_local(world_position)
	
	# 获取Image精灵的rect（这是相对于Image节点的本地坐标）
	var sprite_rect = sprite.get_rect()
	var sprite_scale = sprite.scale
	var img_size = original_image.get_size()
	
	# sprite_rect 是从 (-width/2, -height/2) 到 (width/2, height/2)
	# 所以精灵中心在 (0, 0)，左上角在 (-width/2, -height/2)
	# 需要将sprite_local_pos转换为相对于rect的UV坐标 (0-1)
	
	# 计算rect在世界中的实际尺寸
	var rect_size = sprite_rect.size * sprite_scale
	
	# 将sprite_local_pos转换为UV坐标（0-1）
	# sprite_local_pos相对于Image中心，rect中心也在(0,0)
	var uv_x = (sprite_local_pos.x / rect_size.x) + 0.5
	var uv_y = (sprite_local_pos.y / rect_size.y) + 0.5
	
	# 转换为图片像素坐标
	var image_pos = Vector2(
		uv_x * img_size.x,
		uv_y * img_size.y
	)
	
	# 确保坐标在图片范围内
	image_pos.x = clamp(image_pos.x, 0, img_size.x - 1)
	image_pos.y = clamp(image_pos.y, 0, img_size.y - 1)
	
	# 计算切割半径（在图片像素空间中）
	# 半径在世界空间中，需要转换为像素空间
	var scale_factor = img_size.x / rect_size.x
	var pixel_radius = max(1.0, radius * scale_factor)  # 至少1像素
	
	# 在遮罩上绘制切割区域（设置为透明）
	# 只更新切割区域，不立即更新纹理
	var min_x = max(0, int(image_pos.x - pixel_radius))
	var max_x = min(cut_mask.get_width(), int(image_pos.x + pixel_radius) + 1)
	var min_y = max(0, int(image_pos.y - pixel_radius))
	var max_y = min(cut_mask.get_height(), int(image_pos.y + pixel_radius) + 1)
	
	# 更新脏区域（合并新切割区域）
	var new_rect = Rect2i(min_x, min_y, max_x - min_x, max_y - min_y)
	if has_dirty_rect:
		# 合并矩形：计算包含两个矩形的最小矩形
		var min_dirty_x = min(dirty_rect.position.x, new_rect.position.x)
		var min_dirty_y = min(dirty_rect.position.y, new_rect.position.y)
		var max_dirty_x = max(dirty_rect.position.x + dirty_rect.size.x, new_rect.position.x + new_rect.size.x)
		var max_dirty_y = max(dirty_rect.position.y + dirty_rect.size.y, new_rect.position.y + new_rect.size.y)
		dirty_rect = Rect2i(min_dirty_x, min_dirty_y, max_dirty_x - min_dirty_x, max_dirty_y - min_dirty_y)
	else:
		dirty_rect = new_rect
		has_dirty_rect = true
	
	var pixels_cut = 0
	for x in range(min_x, max_x):
		for y in range(min_y, max_y):
			var pixel_pos = Vector2(x, y)
			var distance = pixel_pos.distance_to(image_pos)
			if distance <= pixel_radius:
				# 只更新还未被切割的像素
				if cut_mask.get_pixel(x, y).a > 0.5:
					cut_mask.set_pixel(x, y, Color.TRANSPARENT)
					pixels_cut += 1
	
	# 标记需要更新纹理
	if pixels_cut > 0:
		needs_update = true
		# 标记需要更新多边形（视觉切割改变了形状）
		needs_polygon_update = true
		
		# 记录切割点（像素坐标）
		cut_trail.append(image_pos)
		cut_path_history.append(image_pos)
		
		# 记录世界坐标下的切割路径（用于多边形分割）
		cut_path_world.append(world_position)
		
		if not is_cutting:
			is_cutting = true
		
		# 生成火花特效（固定频率）
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_spark_time >= spark_spawn_interval:
			spawn_spark_at_position(world_position)
			last_spark_time = current_time

func _process(delta):
	# 定期更新纹理，而不是每次切割都更新
	if needs_update:
		texture_update_timer += delta
		# 如果延迟时间到了，立即更新
		if texture_update_timer >= texture_update_delay:
			apply_mask_to_texture()
			texture_update_timer = 0.0
			needs_update = false
		# 如果已经累积了很多切割（延迟较长），强制更新
		elif texture_update_timer >= texture_update_delay * 2.0:
			apply_mask_to_texture()
			texture_update_timer = 0.0
			needs_update = false
	
	# 禁用自动多边形更新（性能杀手，卡顿主因）
	# 多边形现在只在初始化时设置，不再动态更新
	# if needs_polygon_update:
	# 	polygon_update_timer += delta
	# 	if polygon_update_timer >= polygon_update_delay:
	# 		update_polygon_from_mask()
	# 		polygon_update_timer = 0.0
	# 		needs_polygon_update = false

func _physics_process(_delta):
	# 强制确保钥匙保持 Kinematic 模式（不受物理影响）
	if not freeze:
		freeze = true
		freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	if gravity_scale != 0.0:
		gravity_scale = 0.0
	if not lock_rotation:
		lock_rotation = true

func apply_mask_to_texture():
	if not original_image or not cut_mask or not current_texture:
		return
	
	# 获取当前纹理的图片（避免重复创建）
	var masked_image = current_texture.get_image()
	if not masked_image:
		masked_image = original_image.duplicate()
	
	var img_size = masked_image.get_size()
	
	# 如果有脏区域，只更新脏区域；否则更新整个图片（第一次更新）
	if has_dirty_rect:
		# 确保脏区域在图片范围内
		var update_rect = Rect2i(
			max(0, dirty_rect.position.x),
			max(0, dirty_rect.position.y),
			min(img_size.x - dirty_rect.position.x, dirty_rect.size.x),
			min(img_size.y - dirty_rect.position.y, dirty_rect.size.y)
		)
		
		# 只更新脏区域内的像素
		for x in range(update_rect.position.x, update_rect.position.x + update_rect.size.x):
			for y in range(update_rect.position.y, update_rect.position.y + update_rect.size.y):
				var mask_alpha = cut_mask.get_pixel(x, y).a
				# 如果遮罩是透明的且图片像素还没被设置为透明
				if mask_alpha < 0.5:
					var current_color = masked_image.get_pixel(x, y)
					if current_color.a > 0.0:
						current_color.a = 0.0
						masked_image.set_pixel(x, y, current_color)
		
		# 重置脏区域
		has_dirty_rect = false
	else:
		# 首次完整更新（遍历整个图片，但只在需要时更新）
		for x in range(img_size.x):
			for y in range(img_size.y):
				var mask_alpha = cut_mask.get_pixel(x, y).a
				if mask_alpha < 0.5:
					var current_color = masked_image.get_pixel(x, y)
					if current_color.a > 0.0:
						current_color.a = 0.0
						masked_image.set_pixel(x, y, current_color)
	
	# 更新纹理（Godot 4使用set_image或update）
	if current_texture.has_method("update"):
		current_texture.update(masked_image)
	else:
		current_texture.set_image(masked_image)
	is_cut = true

# ========== 多边形物理切割相关函数 ==========

# 从cut_mask更新current_polygon（使物理形状跟随视觉切割）
func update_polygon_from_mask():
	"""从cut_mask提取当前轮廓，更新current_polygon和物理碰撞形状"""
	if not cut_mask or not sprite:
		return
	
	# 提取当前的钥匙轮廓
	var new_polygon = get_cut_polygon_from_image()
	
	# 验证多边形有效性
	if new_polygon.size() < 3:
		print("⚠ [%s] 提取的多边形顶点数不足（%d个），跳过更新" % [name, new_polygon.size()])
		return
	
	# 计算面积，确保多边形不是退化的
	var area = abs(PolygonUtils.calculate_polygon_area(new_polygon))
	if area < 100.0:  # 面积太小，可能是噪声
		print("⚠ [%s] 多边形面积太小（%.1f），跳过更新" % [name, area])
		return
	
	# 更新多边形顶点（即使没有 polygon_shape 也更新）
	current_polygon = new_polygon
	print("✓ [%s] 多边形已更新：顶点数=%d, 面积=%.1f" % [name, current_polygon.size(), area])
	
	# 尝试更新物理碰撞形状（如果有的话）
	if polygon_shape:
		polygon_shape.polygon = current_polygon
		var collision = get_node_or_null("CollisionShape2D")
		if collision:
			collision.shape = polygon_shape
			print("✓ [%s] 物理碰撞形状已同步" % name)
	
	last_polygon_update_time = Time.get_ticks_msec() / 1000.0

# 创建形状资源（优先多边形，降级到矩形）
func create_polygon_shape_resource():
	# 如果已有模板，复制模板
	if polygon_shape_template:
		var new_shape = polygon_shape_template.duplicate()
		return new_shape
	
	# 如果有现有的 polygon_shape，复制它
	if polygon_shape:
		var new_shape = polygon_shape.duplicate()
		return new_shape
	
	# 没有多边形形状，返回 null（碎片会使用矩形形状）
	return null

# 递归查找场景中所有的CollisionShape2D节点
func _find_all_collision_shapes(node: Node) -> Array:
	var result = []
	for child in node.get_children():
		if child is CollisionShape2D:
			result.append(child)
		result.append_array(_find_all_collision_shapes(child))
	return result

# 初始化多边形（从CollisionShape2D获取或创建）
func initialize_polygon():
	var collision = get_node_or_null("CollisionShape2D")
	if not collision:
		print("❌ [%s] 未找到CollisionShape2D节点" % name)
		return
	
	if not collision.shape:
		print("❌ [%s] CollisionShape2D没有shape" % name)
		return
	
	# 使用 is 操作符进行安全的类型检查
	print("🔍 [%s] 检查CollisionShape2D的shape类型..." % name)
	
	# 如果是 RectangleShape2D，转换为多边形数据
	if collision.shape is RectangleShape2D:
		print("🔄 [%s] 从RectangleShape2D创建多边形数据..." % name)
		var rect_shape = collision.shape as RectangleShape2D
		var rect_size = rect_shape.size * collision.scale
		var rect_pos = collision.position
		var rect = Rect2(rect_pos - rect_size / 2, rect_size)
		current_polygon = PolygonUtils.create_polygon_from_rect(rect)
		print("✓ [%s] 多边形数据已创建，顶点数: %d (矩形边界: %s)" % [name, current_polygon.size(), rect])
		
		# 保持使用 RectangleShape2D（碎片也会使用矩形，性能更好）
		print("  ✓ 使用RectangleShape2D作为物理形状")
		# polygon_shape_template 保持为 null，碎片将使用矩形形状
		return
	
	# 不支持的形状类型
	print("❌ [%s] CollisionShape2D的shape类型不支持" % name)

# 检查并分割多边形（定期调用）
func check_and_split_polygon():
	if not enable_fragment_split:
		return
		
	if cut_path_world.size() < 2:
		return
	
	# 计算切割路径长度
	var path_length = 0.0
	for i in range(1, cut_path_world.size()):
		path_length += cut_path_world[i].distance_to(cut_path_world[i - 1])
	
	# 只有当切割路径足够长时才尝试分割
	if path_length < min_cut_length:
		return
	
	print("📏 [%s] 切割路径长度: %.1f (阈值: %.1f)" % [name, path_length, min_cut_length])
	
	# 尝试执行分割
	attempt_split()

# 激光离开钥匙时调用，强制尝试分割
func finalize_cut():
	# 只重置切割状态（不再执行分割）
	is_cutting = false
	cut_path_world.clear()

# 尝试执行多边形分割
func attempt_split():
	if cut_path_world.size() < 2:
		print("⚠ 分割失败：切割路径点数不足（%d个）" % cut_path_world.size())
		return
	
	# 获取切割线的起点和终点
	# 需要转换到与 current_polygon 相同的坐标系（Sprite 的本地坐标）
	var cut_start_local = sprite.to_local(cut_path_world[0])
	var cut_end_local = sprite.to_local(cut_path_world[cut_path_world.size() - 1])
	
	# 计算多边形边界
	var poly_bounds = PolygonUtils.get_polygon_bounds(current_polygon)
	
	# 延长切割线，确保它穿过多边形边界
	var extended_line = PolygonUtils.extend_line_to_bounds(cut_start_local, cut_end_local, poly_bounds)
	cut_start_local = extended_line[0]
	cut_end_local = extended_line[1]
	
	# 调试选项：使用简单矩形进行分割测试
	var test_polygon = current_polygon
	if use_simple_rect_for_split:
		# 使用多边形的边界框创建简单矩形
		test_polygon = PolygonUtils.create_polygon_from_rect(poly_bounds)
	
	# 执行多边形分割
	var split_result = PolygonUtils.split_polygon_by_line(
		test_polygon,
		cut_start_local,
		cut_end_local
	)
	
	# 如果成功分割（返回多个多边形）
	if split_result.size() > 1:
		print("✅ 切割成功！产生 %d 个碎片" % split_result.size())
		create_split_fragments(split_result, cut_start_local, cut_end_local)
		
		# 清空切割路径
		cut_path_world.clear()
		is_cutting = false
	else:
		print("❌ 分割失败：切割线未穿过多边形或交点不足")
		# 分割失败，可能是切割线没有真正穿过多边形
		# 清空旧的路径点，保留最近的一些点
		if cut_path_world.size() > 10:
			cut_path_world = cut_path_world.slice(-10)  # 只保留最后10个点
		print("━━━━━━━━━━━━━━━━━━━━━━")

# 创建分割后的碎片
func create_split_fragments(polygons: Array, cut_start: Vector2, cut_end: Vector2):
	if polygons.size() < 2:
		return
	
	# 找出面积最大的多边形作为主体（保留），其他作为碎片（掉落）
	var areas = []
	for i in range(polygons.size()):
		var poly = polygons[i] as PackedVector2Array
		var area = abs(PolygonUtils.calculate_polygon_area(poly))
		areas.append({"index": i, "polygon": poly, "area": area})
	
	# 按面积排序（降序）
	areas.sort_custom(func(a, b): return a.area > b.area)
	
	# 最大的保留为主体
	var main_body = areas[0]
	
	# 更新原钥匙的多边形为主体部分
	current_polygon = main_body.polygon
	
	# 强制确保钥匙保持 Kinematic 模式（完全不受物理影响）
	gravity_scale = 0.0
	freeze = true
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	lock_rotation = true
	
	if polygon_shape:
		polygon_shape.polygon = current_polygon
		var collision = get_node_or_null("CollisionShape2D")
		if collision:
			collision.shape = polygon_shape
	
	# 其他部分创建为掉落的碎片
	var created_count = 0
	for i in range(1, areas.size()):
		var fragment_data = areas[i]
		var fragment_polygon = fragment_data.polygon
		var fragment_area = fragment_data.area
		
		if fragment_polygon.size() < 3:
			continue
		
		# 忽略太小的碎片（可能是切割误差）
		if fragment_area < min_fragment_area:
			continue
		
		# 计算碎片的边界框
		var bounds = PolygonUtils.get_polygon_bounds(fragment_polygon)
		
		# 计算碎片中心（在所有分支外定义）
		var center = bounds.get_center()
		
		# 创建新的RigidBody2D
		var fragment = RigidBody2D.new()
		fragment.name = "KeyFragment_%d" % (Time.get_ticks_msec())
		
		# 先添加到场景（这样 global_position 才有效）
		get_tree().current_scene.add_child(fragment)
		
		# 设置物理属性
		fragment.gravity_scale = 1.0  # 启用重力
		fragment.mass = 0.5  # 设置质量
		fragment.linear_damp = 0.5  # 添加空气阻力
		
		# center 是相对于 sprite 的坐标，转换到世界坐标
		var key_world_pos = global_position
		var sprite_world_pos = sprite.global_position
		var world_pos = sprite.to_global(center)
		fragment.global_position = world_pos
		
		print("  🔹 碎片%d: center_local=(%.1f,%.1f) key_world=(%.1f,%.1f) sprite_world=(%.1f,%.1f) fragment_world=(%.1f,%.1f)" % [
			i, center.x, center.y, 
			key_world_pos.x, key_world_pos.y,
			sprite_world_pos.x, sprite_world_pos.y,
			world_pos.x, world_pos.y
		])
		
		# 添加CollisionShape2D（使用矩形，简单高效）
		var fragment_collision = CollisionShape2D.new()
		
		# 使用矩形形状
		var rect_shape = RectangleShape2D.new()
		# 确保最小尺寸
		var collision_size = Vector2(max(bounds.size.x, 50.0), max(bounds.size.y, 50.0))
		rect_shape.size = collision_size
		fragment_collision.shape = rect_shape
		
		fragment.add_child(fragment_collision)
		
		# 添加简单的可视化（彩色矩形，跳过纹理避免卡顿）
		var fragment_sprite = Sprite2D.new()
		# 确保最小尺寸（避免太小看不见）
		var sprite_size = Vector2(max(bounds.size.x, 50.0), max(bounds.size.y, 50.0))
		var debug_image = Image.create(int(sprite_size.x), int(sprite_size.y), false, Image.FORMAT_RGBA8)
		debug_image.fill(Color(1.0, 0.5, 0.0, 0.8))  # 橙色半透明
		var debug_texture = ImageTexture.create_from_image(debug_image)
		fragment_sprite.texture = debug_texture
		fragment_sprite.offset = Vector2.ZERO
		fragment.add_child(fragment_sprite)
		
		created_count += 1
	
	if created_count > 0:
		print("  ✅ 创建了 %d 个橙色碎片（应该可见并掉落）" % created_count)

# 为碎片创建裁剪后的纹理
func create_cropped_texture(polygon: PackedVector2Array, bounds: Rect2) -> ImageTexture:
	if not original_image:
		return null
	
	var img_size = original_image.get_size()
	var sprite_rect = sprite.get_rect()
	var sprite_scale = sprite.scale
	var rect_size = sprite_rect.size * sprite_scale
	
	# 计算边界框在图片中的像素坐标
	var bounds_pixel = Rect2i(
		int((bounds.position.x / rect_size.x + 0.5) * img_size.x),
		int((bounds.position.y / rect_size.y + 0.5) * img_size.y),
		int((bounds.size.x / rect_size.x) * img_size.x),
		int((bounds.size.y / rect_size.y) * img_size.y)
	)
	
	# 创建裁剪后的图片
	var cropped_image = Image.create(bounds_pixel.size.x, bounds_pixel.size.y, false, Image.FORMAT_RGBA8)
	
	# 复制像素并应用多边形遮罩
	for x in range(bounds_pixel.size.x):
		for y in range(bounds_pixel.size.y):
			var world_x = bounds_pixel.position.x + x
			var world_y = bounds_pixel.position.y + y
			
			if world_x >= 0 and world_x < img_size.x and world_y >= 0 and world_y < img_size.y:
				# 检查点是否在多边形内
				var local_point = Vector2(
					(world_x / img_size.x - 0.5) * rect_size.x,
					(world_y / img_size.y - 0.5) * rect_size.y
				)
				
				if is_point_in_polygon(local_point, polygon):
					cropped_image.set_pixel(x, y, original_image.get_pixel(world_x, world_y))
				else:
					cropped_image.set_pixel(x, y, Color.TRANSPARENT)
	
	var texture = ImageTexture.new()
	texture.set_image(cropped_image)
	return texture

# 判断点是否在多边形内（射线法）
static func is_point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	"""判断点是否在多边形内（射线法）"""
	if polygon.size() < 3:
		return false
	
	var inside = false
	var j = polygon.size() - 1
	
	for i in range(polygon.size()):
		var pi = polygon[i]
		var pj = polygon[j]
		
		if ((pi.y > point.y) != (pj.y > point.y)):
			if (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x):
				inside = !inside
		j = i
	
	return inside

# 公共方法：获取当前的切割后的多边形
func get_current_polygon() -> PackedVector2Array:
	"""返回当前多边形的顶点（本地坐标）"""
	return current_polygon

# 公共方法：获取钥匙的全局位置
func get_key_global_position() -> Vector2:
	"""返回钥匙的全局位置"""
	return global_position

# 公共方法：从被切割后的Image提取多边形轮廓
func get_cut_polygon_from_image() -> PackedVector2Array:
	"""
	从cut_mask提取被保留（未擦除）的像素轮廓（优化版本：使用采样）
	cut_mask: 白色(alpha>0.5) = 被保留，透明(alpha<=0.5) = 被擦除
	返回相对于Sprite中心的本地坐标
	"""
	if not cut_mask or not sprite:
		print("警告：无法提取多边形，cut_mask或精灵不存在")
		return PackedVector2Array()
	
	var img_size = cut_mask.get_size()
	var outline_points: Array[Vector2] = []
	
	# 优化：使用采样步长来减少像素遍历（每隔N个像素采样一次）
	# 采样步长根据图像大小动态调整，图像越大步长越大
	# 增加步长以提高性能（从 /100 改为 /50）
	var sample_step = max(4, int(sqrt(img_size.x * img_size.y) / 50.0))  # 更大的步长
	
	# 只在首次或每10次打印一次日志，减少控制台输出
	if cut_path_history.size() % 100 == 0:
		print("图像大小: %dx%d, 采样步长: %d" % [img_size.x, img_size.y, sample_step])
	
	# 只采样部分像素来找边界
	for y in range(0, img_size.y, sample_step):
		for x in range(0, img_size.x, sample_step):
			var pixel = cut_mask.get_pixel(x, y)
			# 如果像素未被擦除（alpha > 0.5 = 白色）
			if pixel.a > 0.5:
				# 检查这个像素是否在边界上（至少有一个邻近像素被擦除）
				if _is_boundary_pixel_fast(x, y, img_size):
					outline_points.append(Vector2(x, y))
	
	# 如果采样点太少（可能图像太小或切割太少），降低步长重新采样
	if outline_points.size() < 20 and sample_step > 1:
		outline_points.clear()
		sample_step = max(1, sample_step / 2)
		print("轮廓点太少，降低采样步长到: %d" % sample_step)
		
		for y in range(0, img_size.y, sample_step):
			for x in range(0, img_size.x, sample_step):
				var pixel = cut_mask.get_pixel(x, y)
				if pixel.a > 0.5:
					if _is_boundary_pixel_fast(x, y, img_size):
						outline_points.append(Vector2(x, y))
	
	# 将像素坐标转换为Sprite本地坐标
	var sprite_rect = sprite.get_rect()
	var sprite_scale = sprite.scale
	var polygon = PackedVector2Array()
	
	for point in outline_points:
		# 转换为UV坐标(0-1)
		var uv_x = float(point.x) / img_size.x
		var uv_y = float(point.y) / img_size.y
		
		# 转换为Sprite本地坐标（中心在(0,0)）
		var local_x = (uv_x - 0.5) * sprite_rect.size.x * sprite_scale.x
		var local_y = (uv_y - 0.5) * sprite_rect.size.y * sprite_scale.y
		
		polygon.append(Vector2(local_x, local_y))
	
	print("从cut_mask提取多边形点数: %d（采样边界点数）" % polygon.size())
	return polygon

# 辅助函数：检查像素是否在被保留区域的边界上（快速版本，只检查4个方向）
func _is_boundary_pixel_fast(x: int, y: int, img_size: Vector2i) -> bool:
	"""检查像素是否是被保留区域的边界（周围有被擦除的像素） - 优化版本"""
	# 只检查4个主方向，不检查对角线（更快）
	var directions = [
		Vector2i(0, -1),  # 上
		Vector2i(-1, 0),  # 左
		Vector2i(1, 0),   # 右
		Vector2i(0, 1)    # 下
	]
	
	for dir in directions:
		var nx = x + dir.x
		var ny = y + dir.y
		
		# 边界像素（超出图片范围的视为被擦除）
		if nx < 0 or nx >= img_size.x or ny < 0 or ny >= img_size.y:
			return true
		
		# 相邻像素被擦除（透明）
		var neighbor = cut_mask.get_pixel(nx, ny)
		if neighbor.a <= 0.5:
			return true
	
	return false

# 辅助函数：检查像素是否在被保留区域的边界上（完整版本，保留以备使用）
func _is_boundary_pixel(x: int, y: int, img_size: Vector2i) -> bool:
	"""检查像素是否是被保留区域的边界（周围有被擦除的像素）"""
	var directions = [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0),                   Vector2i(1, 0),
		Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1)
	]
	
	for dir in directions:
		var nx = x + dir.x
		var ny = y + dir.y
		
		# 边界像素（超出图片范围的视为被擦除）
		if nx < 0 or nx >= img_size.x or ny < 0 or ny >= img_size.y:
			return true
		
		# 相邻像素被擦除（透明）
		var neighbor = cut_mask.get_pixel(nx, ny)
		if neighbor.a <= 0.5:
			return true
	
	return false

# 在指定位置生成火花特效
func spawn_spark_at_position(world_position: Vector2):
	var spark = SPARK_SCENE.instantiate()
	spark.global_position = world_position
	spark.emitting = true
	
	# 将火花添加到场景树（添加到根节点，避免跟随钥匙移动）
	get_tree().current_scene.add_child(spark)
	
	# 设置自动删除（粒子生命周期结束后删除节点）
	spark.finished.connect(func(): spark.queue_free())
