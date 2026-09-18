@tool
class_name HD2DTerrainData
extends Resource
## CPU authoring data is the source of truth; render/collision data is disposable.
@export_range(64, 512, 1) var size_m: float = 256.0
@export_enum("129:129", "257:257", "513:513") var resolution: int = 257
@export var heights: PackedFloat32Array
@export var weights: PackedColorArray
@export var textures: Array[Texture2D] = []
@export var colors: PackedColorArray = PackedColorArray([
	Color("77723d"), Color("aa8954"), Color("52652d"), Color("686b72")])
@export_range(0.1, 32) var texture_scale: float = 2.0

func initialize(samples: int = 257, meters: float = 256.0) -> void:
	resolution = samples
	size_m = meters
	heights.resize(samples * samples)
	heights.fill(0.0)
	weights.resize(samples * samples)
	weights.fill(Color(1, 0, 0, 0))
	emit_changed()

func ensure_valid() -> void:
	if resolution not in [129, 257, 513]:
		resolution = 257
	if heights.size() != resolution * resolution:
		initialize(resolution, size_m)
	if weights.size() != heights.size():
		weights.resize(heights.size())
		weights.fill(Color(1, 0, 0, 0))

func cell_size() -> float:
	return size_m / float(resolution - 1)

func sample(x: int, z: int) -> float:
	return heights[clampi(z, 0, resolution - 1) * resolution + clampi(x, 0, resolution - 1)]

func height_at(x: float, z: float) -> float:
	var gx := clampf((x + size_m * 0.5) / cell_size(), 0, resolution - 1)
	var gz := clampf((z + size_m * 0.5) / cell_size(), 0, resolution - 1)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	# Same piecewise planar interpolation as the rendered/collision triangles.
	if fx + fz <= 1.0:
		return sample(ix, iz) + fx * (sample(ix+1, iz)-sample(ix, iz)) + fz * (sample(ix, iz+1)-sample(ix, iz))
	return sample(ix+1, iz+1) + (1-fx)*(sample(ix, iz+1)-sample(ix+1, iz+1)) + (1-fz)*(sample(ix+1, iz)-sample(ix+1, iz+1))

func snapshot() -> Dictionary:
	return {"heights": heights.duplicate(), "weights": weights.duplicate()}

func restore(state: Dictionary) -> void:
	heights = state.heights.duplicate()
	weights = state.weights.duplicate()
	emit_changed()

func brush(center: Vector3, radius: float, amount: float, mode: String, layer: int = 0,
		level: float = 0.0, ramp_origin: Vector3 = Vector3.ZERO) -> Rect2i:
	var step := cell_size()
	var gc := Vector2(center.x, center.z) / step + Vector2.ONE * ((resolution-1)*0.5)
	var r := radius / step
	var lo := Vector2i(maxi(0, int(floor(gc.x-r))), maxi(0, int(floor(gc.y-r))))
	var hi := Vector2i(mini(resolution-1, int(ceil(gc.x+r))), mini(resolution-1, int(ceil(gc.y+r))))
	var before := heights.duplicate() if mode == "smooth" else heights
	for z in range(lo.y, hi.y+1):
		for x in range(lo.x, hi.x+1):
			var distance := Vector2(x, z).distance_to(gc) / maxf(r, 0.001)
			if distance > 1.0: continue
			var falloff := 1.0 - smoothstep(0.0, 1.0, distance)
			var index := z*resolution+x
			match mode:
				"raise": heights[index] += amount*falloff
				"lower": heights[index] -= amount*falloff
				"smooth":
					var mean := 0.0
					for dz in range(-1, 2):
						for dx in range(-1, 2):
							mean += before[clampi(z+dz,0,resolution-1)*resolution+clampi(x+dx,0,resolution-1)] / 9.0
					heights[index] = lerpf(before[index], mean, clampf(amount*falloff,0,1))
				"flatten": heights[index] = lerpf(heights[index], level, clampf(amount*falloff,0,1))
				"ramp":
					var a := Vector2(ramp_origin.x, ramp_origin.z)
					var b := Vector2(center.x, center.z)
					var p := Vector2(x*step-size_m*0.5, z*step-size_m*0.5)
					var t := clampf((p-a).dot(b-a) / maxf((b-a).length_squared(),0.001),0,1)
					heights[index] = lerpf(heights[index], lerpf(ramp_origin.y,level,t), clampf(amount*falloff,0,1))
				"paint":
					var target := Color(0,0,0,0)
					target[clampi(layer,0,3)] = 1.0
					weights[index] = weights[index].lerp(target, clampf(amount*falloff,0,1))
	return Rect2i(lo, hi-lo+Vector2i.ONE)
