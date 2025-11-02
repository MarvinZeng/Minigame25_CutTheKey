# 多边形工具类：处理多边形分割操作
class_name PolygonUtils

# 用直线分割多边形，返回分割后的多个多边形
# polygon: PackedVector2Array - 原始多边形（按逆时针或顺时针顺序）
# line_start: Vector2 - 切割线起点（本地坐标）
# line_end: Vector2 - 切割线终点（本地坐标）
# 返回: Array[PackedVector2Array] - 分割后的多边形列表
static func split_polygon_by_line(polygon: PackedVector2Array, line_start: Vector2, line_end: Vector2) -> Array:
	if polygon.size() < 3:
		return []
	
	var result_polygons = []
	var intersections = []
	
	# 找到切割线与多边形边的所有交点
	for i in range(polygon.size()):
		var p1 = polygon[i]
		var p2 = polygon[(i + 1) % polygon.size()]
		
		var intersection = line_segment_intersection(line_start, line_end, p1, p2)
		if intersection != null:
			# 存储交点及其所在边的索引
			intersections.append({
				"point": intersection,
				"edge_index": i,
				"t": get_line_parameter(line_start, line_end, intersection)
			})
	
	# 如果没有交点或只有一个交点，无法分割
	if intersections.size() < 2:
		print("  ⚠ 找到的交点数: %d (需要至少2个)" % intersections.size())
		if intersections.size() == 1:
			print("    唯一交点: (%.1f, %.1f) 在边 %d" % [
				intersections[0].point.x,
				intersections[0].point.y,
				intersections[0].edge_index
			])
		return [polygon]  # 返回原多边形
	
	# 按切割线参数t排序交点
	intersections.sort_custom(func(a, b): return a.t < b.t)
	
	# 用两个端点分割多边形
	var split_point1 = intersections[0].point
	var split_point2 = intersections[intersections.size() - 1].point
	
	# 分割多边形
	var polygons = split_polygon_at_points(polygon, split_point1, split_point2, line_start, line_end)
	
	return polygons

# 在多边形的两个交点处分割
static func split_polygon_at_points(polygon: PackedVector2Array, p1: Vector2, p2: Vector2, line_start: Vector2, line_end: Vector2) -> Array:
	var polygon1 = PackedVector2Array()
	var polygon2 = PackedVector2Array()
	
	# 找到p1和p2在多边形中的位置
	var idx1 = -1
	var idx2 = -1
	
	# 找到最接近p1和p2的顶点索引
	var min_dist1 = INF
	var min_dist2 = INF
	for i in range(polygon.size()):
		var dist1 = polygon[i].distance_to(p1)
		var dist2 = polygon[i].distance_to(p2)
		if dist1 < min_dist1:
			min_dist1 = dist1
			idx1 = i
		if dist2 < min_dist2:
			min_dist2 = dist2
			idx2 = i
	
	# 确保idx1 < idx2
	if idx1 > idx2:
		var temp = idx1
		idx1 = idx2
		idx2 = temp
		var temp_p = p1
		p1 = p2
		p2 = temp_p
	
	# 构建第一个多边形：从idx1到idx2，经过p1和p2
	polygon1.append(p1)
	for i in range(idx1 + 1, idx2 + 1):
		polygon1.append(polygon[i])
	polygon1.append(p2)
	
	# 构建第二个多边形：从idx2到idx1，经过p2和p1
	polygon2.append(p2)
	for i in range(idx2 + 1, polygon.size()):
		polygon2.append(polygon[i])
	for i in range(0, idx1 + 1):
		polygon2.append(polygon[i])
	polygon2.append(p1)
	
	# 验证多边形有效性（至少3个点，且面积>0）
	var result = []
	if polygon1.size() >= 3 and calculate_polygon_area(polygon1) > 0:
		# 确保多边形是逆时针（Godot要求）
		if not is_polygon_ccw(polygon1):
			polygon1.reverse()
		result.append(polygon1)
	
	if polygon2.size() >= 3 and calculate_polygon_area(polygon2) > 0:
		if not is_polygon_ccw(polygon2):
			polygon2.reverse()
		result.append(polygon2)
	
	return result if result.size() > 0 else [polygon]

# 计算两条线段的交点（如果没有交点返回 null）
static func line_segment_intersection(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2):
	var d = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
	if abs(d) < 0.0001:  # 线段平行或重合
		return null
	
	var t = ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / d
	var u = -((p1.x - p2.x) * (p1.y - p3.y) - (p1.y - p2.y) * (p1.x - p3.x)) / d
	
	# 检查交点是否在两条线段上
	if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
		return Vector2(p1.x + t * (p2.x - p1.x), p1.y + t * (p2.y - p1.y))
	
	return null

# 获取点在直线上的参数t
static func get_line_parameter(line_start: Vector2, line_end: Vector2, point: Vector2) -> float:
	var line_dir = line_end - line_start
	if line_dir.length_squared() < 0.0001:
		return 0.0
	return (point - line_start).dot(line_dir.normalized()) / line_dir.length()

# 计算多边形面积（带符号，用于判断方向）
static func calculate_polygon_area(polygon: PackedVector2Array) -> float:
	if polygon.size() < 3:
		return 0.0
	
	var area = 0.0
	for i in range(polygon.size()):
		var j = (i + 1) % polygon.size()
		area += polygon[i].x * polygon[j].y
		area -= polygon[j].x * polygon[i].y
	return abs(area) / 2.0

# 判断多边形是否逆时针
static func is_polygon_ccw(polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3:
		return true
	
	var area = 0.0
	for i in range(polygon.size()):
		var j = (i + 1) % polygon.size()
		area += polygon[i].x * polygon[j].y
		area -= polygon[j].x * polygon[i].y
	return area > 0  # 正面积为逆时针

# 从矩形创建多边形
static func create_polygon_from_rect(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y)
	])

# 延长线段使其穿过边界框（扩展1.5倍边界框大小）
static func extend_line_to_bounds(line_start: Vector2, line_end: Vector2, bounds: Rect2) -> Array:
	var direction = (line_end - line_start).normalized()
	
	# 计算需要延伸的距离（取边界框对角线长度的2倍）
	var bounds_diagonal = bounds.size.length()
	var extension = bounds_diagonal * 2.0
	
	# 向两个方向延伸
	var extended_start = line_start - direction * extension
	var extended_end = line_end + direction * extension
	
	return [extended_start, extended_end]

# 计算多边形的边界框
static func get_polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.size() == 0:
		return Rect2()
	
	var min_x = polygon[0].x
	var max_x = polygon[0].x
	var min_y = polygon[0].y
	var max_y = polygon[0].y
	
	for point in polygon:
		min_x = min(min_x, point.x)
		max_x = max(max_x, point.x)
		min_y = min(min_y, point.y)
		max_y = max(max_y, point.y)
	
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
