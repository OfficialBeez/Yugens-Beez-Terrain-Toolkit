class_name LodMeshBuilder
extends RefCounted

# Worker-thread safe mesh builder.
# Returns raw surface arrays only (no ArrayMesh creation, no RenderingServer, no scene tree access).

static func build_heightfield(job: Dictionary) -> Dictionary:
	# Required inputs
	var dims_x: int = int(job["dims_x"]) # original sample dims (e.g., 33)
	var dims_z: int = int(job["dims_z"]) # original sample dims (e.g., 33)
	var cell_size: Vector2 = job["cell_size"]
	var heights: PackedFloat32Array = job["heights"] # dims_x * dims_z
	var ground_idx: PackedByteArray = job["ground_idx"] # dims_x * dims_z (may be empty => slot 0)
	var lod: int = int(job.get("lod", 0))
	var skirt_depth: float = float(job.get("skirt_depth", 0.0))
	var cx: int = int(job.get("cx", 0))
	var cz: int = int(job.get("cz", 0))

	var step: int = 1 << max(lod, 0)
	var gx_count: int = int((dims_x - 1) / step) + 1
	var gz_count: int = int((dims_z - 1) / step) + 1
	var vtx_count: int = gx_count * gz_count

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var custom0 := PackedFloat32Array() # RGBA float per-vertex
	var custom1 := PackedFloat32Array()
	var custom2 := PackedFloat32Array()

	vertices.resize(vtx_count)
	normals.resize(vtx_count)
	uvs.resize(vtx_count)
	uv2s.resize(vtx_count)
	colors.resize(vtx_count)
	custom0.resize(vtx_count * 4)
	custom1.resize(vtx_count * 4)
	custom2.resize(vtx_count * 4)

	var h_at := func(ox: int, oz: int) -> float:
		ox = clampi(ox, 0, dims_x - 1)
		oz = clampi(oz, 0, dims_z - 1)
		return heights[oz * dims_x + ox]

	for gz in range(gz_count):
		var oz := gz * step
		for gx in range(gx_count):
			var ox := gx * step
			var i := gz * gx_count + gx
			var h := heights[oz * dims_x + ox]
			vertices[i] = Vector3(float(ox) * cell_size.x, h, float(oz) * cell_size.y)

			# Basic normals from height gradient.
			# Use one-sided differences at chunk edges to reduce lighting seams.
			var hL: float = h if (ox - step) < 0 else h_at.call(ox - step, oz)
			var hR: float = h if (ox + step) > (dims_x - 1) else h_at.call(ox + step, oz)
			var hD: float = h if (oz - step) < 0 else h_at.call(ox, oz - step)
			var hU: float = h if (oz + step) > (dims_z - 1) else h_at.call(ox, oz + step)
			var dx: float = (hL - hR) / max(0.0001, 2.0 * cell_size.x * float(step))
			var dz: float = (hD - hU) / max(0.0001, 2.0 * cell_size.y * float(step))
			normals[i] = Vector3(dx, 1.0, dz).normalized()

			uvs[i] = Vector2.ZERO
			# UV2 matches original sample space so existing MST tiling stays consistent.
			uv2s[i] = Vector2(float(ox), float(oz))

			var slot := 0
			if not ground_idx.is_empty():
				slot = int(ground_idx[oz * dims_x + ox])
			# Legacy COLOR/CUSTOM0 encoding (idx stored in COLOR.r, CUSTOM0 unused)
			colors[i] = Color(float(slot) / 255.0, 0, 0, 0)
			# CUSTOM0: RGBA float. Keep weights = 0.
			custom0[i * 4 + 0] = 0.0
			custom0[i * 4 + 1] = 0.0
			custom0[i * 4 + 2] = 0.0
			custom0[i * 4 + 3] = 0.0
			# CUSTOM1: unused for heightfield; keep wall idx = 0.
			custom1[i * 4 + 0] = 0.0
			custom1[i * 4 + 1] = 0.0
			custom1[i * 4 + 2] = 0.0
			custom1[i * 4 + 3] = 0.0
			# CUSTOM2: dominant material index + weight.
			custom2[i * 4 + 0] = float(slot)
			custom2[i * 4 + 1] = 0.0
			custom2[i * 4 + 2] = 0.0
			custom2[i * 4 + 3] = 1.0

	var quad_count := (gx_count - 1) * (gz_count - 1)
	var indices := PackedInt32Array()
	indices.resize(quad_count * 6)
	var wi := 0
	for gz in range(gz_count - 1):
		for gx in range(gx_count - 1):
			var i0 := gz * gx_count + gx
			var i1 := i0 + 1
			var i2 := i0 + gx_count
			var i3 := i2 + 1
			# Winding must face upward for correct lighting on the top surface.
			indices[wi + 0] = i0
			indices[wi + 1] = i1
			indices[wi + 2] = i2
			indices[wi + 3] = i1
			indices[wi + 4] = i3
			indices[wi + 5] = i2
			wi += 6

	# Optional skirts (hides LOD cracks).
	if skirt_depth > 0.0:
		var skirt_indices := PackedInt32Array()
		# Rough estimate to reduce realloc: 4 edges * (n-1) quads * 6 indices.
		skirt_indices.resize(((gx_count - 1) + (gz_count - 1)) * 4 * 6)
		var si := 0

		var add_skirt_vert := func(src_i: int, nrm: Vector3) -> int:
			var base := vertices.size()
			vertices.push_back(vertices[src_i] + Vector3(0, -skirt_depth, 0))
			# Use outward-facing normals for skirt faces so they don't shade as black seams.
			normals.push_back(nrm)
			uvs.push_back(uvs[src_i])
			uv2s.push_back(uv2s[src_i])
			colors.push_back(colors[src_i])
			custom0.append_array(PackedFloat32Array([custom0[src_i * 4 + 0], custom0[src_i * 4 + 1], custom0[src_i * 4 + 2], custom0[src_i * 4 + 3]]))
			custom1.append_array(PackedFloat32Array([custom1[src_i * 4 + 0], custom1[src_i * 4 + 1], custom1[src_i * 4 + 2], custom1[src_i * 4 + 3]]))
			custom2.append_array(PackedFloat32Array([custom2[src_i * 4 + 0], custom2[src_i * 4 + 1], custom2[src_i * 4 + 2], custom2[src_i * 4 + 3]]))
			return base

		# North edge (gz=0)
		var n_north := Vector3(0, 0, -1)
		for gx in range(gx_count - 1):
			var top0 := gx
			var top1 := gx + 1
			var sk0: int = add_skirt_vert.call(top0, n_north)
			var sk1: int = add_skirt_vert.call(top1, n_north)
			skirt_indices[si + 0] = top0
			skirt_indices[si + 1] = sk0
			skirt_indices[si + 2] = top1
			skirt_indices[si + 3] = top1
			skirt_indices[si + 4] = sk0
			skirt_indices[si + 5] = sk1
			si += 6

		# South edge (gz=gz_count-1)
		var n_south := Vector3(0, 0, 1)
		for gx in range(gx_count - 1):
			var top0 := (gz_count - 1) * gx_count + gx
			var top1 := top0 + 1
			var sk0: int = add_skirt_vert.call(top0, n_south)
			var sk1: int = add_skirt_vert.call(top1, n_south)
			skirt_indices[si + 0] = top1
			skirt_indices[si + 1] = sk0
			skirt_indices[si + 2] = top0
			skirt_indices[si + 3] = top1
			skirt_indices[si + 4] = sk1
			skirt_indices[si + 5] = sk0
			si += 6

		# West edge (gx=0)
		var n_west := Vector3(-1, 0, 0)
		for gz in range(gz_count - 1):
			var top0 := gz * gx_count
			var top1 := (gz + 1) * gx_count
			var sk0: int = add_skirt_vert.call(top0, n_west)
			var sk1: int = add_skirt_vert.call(top1, n_west)
			skirt_indices[si + 0] = top1
			skirt_indices[si + 1] = sk0
			skirt_indices[si + 2] = top0
			skirt_indices[si + 3] = top1
			skirt_indices[si + 4] = sk1
			skirt_indices[si + 5] = sk0
			si += 6

		# East edge (gx=gx_count-1)
		var n_east := Vector3(1, 0, 0)
		for gz in range(gz_count - 1):
			var top0 := gz * gx_count + (gx_count - 1)
			var top1 := (gz + 1) * gx_count + (gx_count - 1)
			var sk0: int = add_skirt_vert.call(top0, n_east)
			var sk1: int = add_skirt_vert.call(top1, n_east)
			skirt_indices[si + 0] = top0
			skirt_indices[si + 1] = sk0
			skirt_indices[si + 2] = top1
			skirt_indices[si + 3] = top1
			skirt_indices[si + 4] = sk0
			skirt_indices[si + 5] = sk1
			si += 6

		skirt_indices.resize(si)
		var merged := PackedInt32Array()
		merged.resize(indices.size() + skirt_indices.size())
		for i in range(indices.size()):
			merged[i] = indices[i]
		for i in range(skirt_indices.size()):
			merged[indices.size() + i] = skirt_indices[i]
		indices = merged

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	arrays[Mesh.ARRAY_CUSTOM1] = custom1
	arrays[Mesh.ARRAY_CUSTOM2] = custom2
	arrays[Mesh.ARRAY_INDEX] = indices

	var fmt := 0
	fmt |= Mesh.ARRAY_FORMAT_VERTEX
	fmt |= Mesh.ARRAY_FORMAT_NORMAL
	fmt |= Mesh.ARRAY_FORMAT_TEX_UV
	fmt |= Mesh.ARRAY_FORMAT_TEX_UV2
	fmt |= Mesh.ARRAY_FORMAT_COLOR
	fmt |= Mesh.ARRAY_FORMAT_INDEX
	fmt |= Mesh.ARRAY_FORMAT_CUSTOM0 | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	fmt |= Mesh.ARRAY_FORMAT_CUSTOM1 | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	fmt |= Mesh.ARRAY_FORMAT_CUSTOM2 | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)

	return {
		"cx": cx,
		"cz": cz,
		"lod": lod,
		"arrays": arrays,
		"format": fmt,
	}
