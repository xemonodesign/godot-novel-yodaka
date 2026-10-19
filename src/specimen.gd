extends SubViewportContainer

var pivot: Node3D
var phase: float = 0.0
var hardness: int = 100
var model: String = ""

func setup(kind: String, tint: Color, grown: bool = false, strength: int = 100) -> void:
    hardness = strength
    model = kind
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    stretch = true
    var viewport := SubViewport.new()
    viewport.size = Vector2i(160, 120)
    viewport.transparent_bg = true
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    add_child(viewport)
    var world := Node3D.new()
    viewport.add_child(world)
    var camera := Camera3D.new()
    camera.position = Vector3(0, 0.25, 4.4)
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 2.7 if grown else 3.2
    world.add_child(camera)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-35, -25, 0)
    light.light_energy = 1.9 if grown else 1.5
    world.add_child(light)
    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(25, 130, 0)
    fill.light_color = Color("a4c6d0")
    fill.light_energy = 0.65
    world.add_child(fill)
    pivot = Node3D.new()
    world.add_child(pivot)
    if kind == "thorn":
        # A trauma: a dark core with shards pushing outward. Hardness sets the shard count.
        var shards: int = clampi(int(round(hardness / 20.0)), 1, 5)
        _rock(pivot, tint, Vector3.ZERO, Vector3(0.62, 0.72, 0.58))
        for i in range(shards):
            var angle := i * TAU / shards + 0.6
            var shard := _rock(pivot, tint.lightened(0.18), Vector3(cos(angle) * 0.5, 0.15 + (i % 2) * 0.35, sin(angle) * 0.5), Vector3(0.14, 0.62, 0.14))
            shard.rotation.z = cos(angle) * 0.9
            shard.rotation.x = -sin(angle) * 0.9
        _rock(pivot, Color("8c3a3a"), Vector3(0.05, 0.1, 0.45), Vector3(0.12, 0.12, 0.12))
    elif kind == "rock":
        _rock(pivot, tint, Vector3.ZERO, Vector3(0.85, 1.05, 0.75))
        _rock(pivot, tint.darkened(0.3), Vector3(0.45, -0.62, 0.2), Vector3(0.45, 0.35, 0.45))
    else:
        var stem := CylinderMesh.new()
        stem.top_radius = 0.032
        stem.bottom_radius = 0.05
        stem.height = 1.55
        stem.radial_segments = 5
        _mesh(pivot, stem, Color("709780"), Vector3(0, -0.22, 0))
        for i in range(5):
            var angle := i * TAU / 5
            var petal := _rock(pivot, tint, Vector3(cos(angle) * 0.38, 0.57, sin(angle) * 0.38), Vector3(0.43, 0.2, 0.33))
            petal.rotation.y = -angle
            petal.rotation.z = 0.2
        _rock(pivot, Color("f3d79e"), Vector3(0, 0.69, 0), Vector3(0.2, 0.19, 0.2))
        var leaf := _rock(pivot, Color("719b82"), Vector3(0.26, -0.3, 0), Vector3(0.43, 0.1, 0.18))
        leaf.rotation.z = 0.45
        var leaf2 := _rock(pivot, Color("527566"), Vector3(-0.22, -0.57, 0), Vector3(0.35, 0.08, 0.15))
        leaf2.rotation.z = -0.35
    if grown and kind != "thorn":
        # A grown word carries a small bright crystal: the meaning Yodaka found in it.
        var crystal := _rock(pivot, tint.lightened(0.45), Vector3(-0.55, 0.95, 0.1), Vector3(0.16, 0.26, 0.16))
        crystal.rotation.z = 0.4
    pivot.rotation.x = 0.16

func _mesh(parent: Node3D, mesh: Mesh, tint: Color, pos: Vector3) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = tint
    material.roughness = 0.88
    instance.material_override = material
    instance.position = pos
    parent.add_child(instance)
    return instance

func _rock(parent: Node3D, tint: Color, pos: Vector3, shape: Vector3) -> MeshInstance3D:
    # An octahedron with independent face normals produces actual flat-shaded geometry.
    var vertices := [Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(1, 0, 0),
        Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1)]
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    surface.set_smooth_group(-1)
    for face in [[0, 3, 2], [0, 4, 3], [0, 5, 4], [0, 2, 5],
                 [1, 2, 3], [1, 3, 4], [1, 4, 5], [1, 5, 2]]:
        face.reverse()
        for index in face:
            surface.add_vertex(vertices[index])
    surface.generate_normals()
    var instance := _mesh(parent, surface.commit(), tint, pos)
    instance.scale = shape
    return instance

func _process(delta: float) -> void:
    phase += delta
    if is_instance_valid(pivot):
        pivot.rotation.y += delta * (0.18 if model == "thorn" else 0.45)
        pivot.position.y = sin(phase * 1.3) * 0.055
