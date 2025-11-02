extends RigidBody2D

@onready var sprite: Sprite2D = $Image

# 使用遮罩图片实现切割效果（保留用于视觉）
var cut_mask: Image
var original_texture: Texture2D
var original_image: Image

var is_cut: bool = false
var cut_trail: Array[Vector2] = []  # 切割轨迹（像素坐标）
var cut_path_history: Array[Vector2] = []  # 完整的切割路径历史
var current_texture: ImageTexture  # 当前显示的纹理
var texture_update_timer: float = 0.0
var texture_update_delay: float = 0.05  # 每0.05秒更新一次纹理（20 FPS更新频率）
var needs_update: bool = false
# 脏区域：记录需要更新的矩形区域 [min_x, min_y, max_x, max_y]
var dirty_rect: Rect2i = Rect2i()
var has_dirty_rect: bool = false

# 多边形物理切割相关
var polygon_shape  # 当前多边形的物理形状（PolygonShape2D）
var current_polygon: PackedVector2Array  # 当前多边形的顶点（本地坐标）
var cut_path_world: Array[Vector2] = []  # 世界坐标下的切割路径
var cut_path_start: Vector2  # 切割路径起点（本地坐标）
var min_cut_length: float = 100.0  # 最小切割长度才触发分割（避免误分割）
var is_cutting: bool = false  # 是否正在切割
var last_split_check_time: float = 0.0  # 上次检查分割的时间
var split_check_interval: float = 0.5  # 分割检查间隔（秒）

func _ready():
	# 添加到key组以便查找
	add_to_group("key")
	
	# 初始化多边形：从CollisionShape2D获取或创建默认矩形
	initialize_polygon()
	
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
			print("钥匙初始化成功，图片大小: ", img_size)
		else:
			print("警告：无法读取钥匙图片")
	else:
		print("警告：钥匙精灵或纹理未找到")

func cut_at_position(world_position: Vector2, radius: float = 20.0):
	if not original_image or not cut_mask:
		print("切割失败：原始图片或遮罩未初始化")
		return
	
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
		# 记录切割点（像素坐标）
		cut_trail.append(image_pos)
		cut_path_history.append(image_pos)
		
		# 记录世界坐标下的切割路径（用于多边形分割）
		cut_path_world.append(world_position)
		
		if not is_cutting:
			is_cutting = true
			cut_path_start = to_local(world_position)
		
		# 定期检查是否应该触发多边形分割（避免频繁检查）
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_split_check_time >= split_check_interval:
			check_and_split_polygon()
			last_split_check_time = current_time

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

# 创建PolygonShape2D资源
func create_polygon_shape_resource():
	# 方法1：如果已有多边形形状，直接复制
	var collision = get_node_or_null("CollisionShape2D")
	if collision and collision.shape:
		if collision.shape.get_class() == "PolygonShape2D" or collision.shape.has_method("get_polygon"):
			var new_shape = collision.shape.duplicate()
			new_shape.polygon = PackedVector2Array()
			return new_shape
	
	# 方法2：直接使用new()（不指定类型声明）
	# 在Godot 4中，这应该可以工作
	var shape = _create_polygon_shape_new()
	return shape

# 直接创建PolygonShape2D（不使用类型注解）
func _create_polygon_shape_new():
	# 在Godot 4中，直接使用类型名应该可以工作
	# 但如果不行，我们需要其他方法
	var shape = PolygonShape2D.new()
	return shape

# 初始化多边形（从CollisionShape2D获取或创建默认矩形）
func initialize_polygon():
	var collision = get_node_or_null("CollisionShape2D")
	if collision and collision.shape:
		# 检查是否是多边形形状
		if collision.shape.get_class() == "PolygonShape2D" or collision.shape.has_method("get_polygon"):
			polygon_shape = collision.shape
			current_polygon = polygon_shape.polygon
			print("从CollisionShape2D加载多边形，顶点数: ", current_polygon.size())
		elif collision.shape is RectangleShape2D:
			# 从矩形创建多边形
			var rect_shape = collision.shape as RectangleShape2D
			var rect_size = rect_shape.size * collision.scale
			var rect_pos = collision.position
			var rect = Rect2(rect_pos - rect_size / 2, rect_size)
			current_polygon = PolygonUtils.create_polygon_from_rect(rect)
			
			# 创建PolygonShape2D（在Godot 4中直接使用new()）
			# 注意：不使用类型注解，避免编译错误
			var new_polygon_shape = create_polygon_shape_resource()
			if new_polygon_shape != null:
				new_polygon_shape.polygon = current_polygon
				polygon_shape = new_polygon_shape
				collision.shape = new_polygon_shape
				print("从矩形创建多边形: ", rect)
			else:
				print("错误：无法创建PolygonShape2D，保持矩形形状")
			print("从矩形创建多边形: ", rect)
		else:
			print("警告：不支持的形状类型，使用默认矩形")
			create_default_polygon()
	else:
		print("警告：未找到CollisionShape2D，使用默认矩形")
		create_default_polygon()

# 创建默认矩形多边形（基于纹理大小）
func create_default_polygon():
	if sprite and sprite.texture:
		var tex_size = sprite.texture.get_size() * sprite.scale
		var rect = Rect2(-tex_size / 2, tex_size)
		current_polygon = PolygonUtils.create_polygon_from_rect(rect)
		
		# 更新CollisionShape2D
		var collision = get_node_or_null("CollisionShape2D")
		if collision:
			var new_polygon_shape = create_polygon_shape_resource()
			if new_polygon_shape != null:
				new_polygon_shape.polygon = current_polygon
				polygon_shape = new_polygon_shape
				collision.shape = new_polygon_shape
				print("创建默认矩形多边形: ", rect)
			else:
				print("错误：无法创建PolygonShape2D")

# 检查并分割多边形（定期调用）
func check_and_split_polygon():
	if cut_path_world.size() < 2:
		return
	
	# 计算切割路径长度
	var path_length = 0.0
	for i in range(1, cut_path_world.size()):
		path_length += cut_path_world[i].distance_to(cut_path_world[i - 1])
	
	# 只有当切割路径足够长时才尝试分割
	if path_length < min_cut_length:
		return
	
	# 尝试执行分割
	attempt_split()

# 激光离开钥匙时调用，强制尝试分割
func finalize_cut():
	if cut_path_world.size() >= 2:
		attempt_split()
	is_cutting = false

# 尝试执行多边形分割
func attempt_split():
	if cut_path_world.size() < 2:
		return
	
	# 获取切割线的起点和终点（本地坐标）
	var cut_start_local = to_local(cut_path_world[0])
	var cut_end_local = to_local(cut_path_world[cut_path_world.size() - 1])
	
	# 执行多边形分割
	var split_result = PolygonUtils.split_polygon_by_line(
		current_polygon,
		cut_start_local,
		cut_end_local
	)
	
	# 如果成功分割（返回多个多边形）
	if split_result.size() > 1:
		print("多边形分割成功，产生 ", split_result.size(), " 个碎片")
		create_split_fragments(split_result, cut_start_local, cut_end_local)
		
		# 清空切割路径
		cut_path_world.clear()
		is_cutting = false
	else:
		# 分割失败，可能是切割线没有真正穿过多边形
		# 清空旧的路径点，保留最近的一些点
		if cut_path_world.size() > 10:
			cut_path_world = cut_path_world.slice(-10)  # 只保留最后10个点

# 创建分割后的碎片
func create_split_fragments(polygons: Array, cut_start: Vector2, cut_end: Vector2):
	if polygons.size() < 2:
		return
	
	# 为每个碎片创建新的RigidBody2D
	for i in range(polygons.size()):
		var fragment_polygon = polygons[i] as PackedVector2Array
		if fragment_polygon.size() < 3:
			continue
		
		# 计算碎片的多边形边界框
		var bounds = PolygonUtils.get_polygon_bounds(fragment_polygon)
		
		# 创建新的RigidBody2D
		var fragment = RigidBody2D.new()
		fragment.gravity_scale = 1.0  # 启用重力，让碎片掉落
		fragment.position = global_position + bounds.get_center()
		
		# 添加CollisionShape2D
		var fragment_collision = CollisionShape2D.new()
		var fragment_shape = create_polygon_shape_resource()
		if fragment_shape == null:
			print("错误：无法为碎片创建PolygonShape2D")
			continue
		# 将多边形坐标转换为相对于碎片中心的坐标
		var relative_polygon = PackedVector2Array()
		var center = bounds.get_center()
		for point in fragment_polygon:
			relative_polygon.append(point - center)
		fragment_shape.polygon = relative_polygon
		fragment_collision.shape = fragment_shape
		fragment.add_child(fragment_collision)
		
		# 添加Sprite2D显示纹理片段
		var fragment_sprite = Sprite2D.new()
		if sprite and sprite.texture:
			# 创建裁剪后的纹理
			var cropped_texture = create_cropped_texture(fragment_polygon, bounds)
			fragment_sprite.texture = cropped_texture
			fragment_sprite.position = -center  # 调整位置使纹理对齐
		fragment.add_child(fragment_sprite)
		
		# 添加到场景
		get_tree().current_scene.add_child(fragment)
		fragment.set_owner(get_tree().current_scene)
	
	# 隐藏或删除原始钥匙
	queue_free()

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
