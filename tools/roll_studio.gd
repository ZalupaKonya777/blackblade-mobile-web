extends Node3D
var rig:FighterRig
var frames:=0
var sample_id:=0
var phase:=0.0
var cam:Camera3D
var samples:Array=[]
const PHASES=[0.0,.10,.20,.30,.40,.50,.60,.70,.80,.90,.999]

func _ready() -> void:
	var world:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.12,.13,.15);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.7,.73,.78);env.ambient_light_energy=.65;world.environment=env;add_child(world)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-42,-32,0);light.light_color=Color(1,.94,.83);light.light_energy=1.0;add_child(light)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(200,200);ground.mesh=plane
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.22,.23,.25);mat.roughness=.85;ground.material_override=mat;ground.position.y=.0;add_child(ground)
	cam=Camera3D.new();cam.position=Vector3(2.7,1.35,1.5);add_child(cam);cam.look_at(Vector3(0,.86,0));cam.current=true;cam.fov=43
	var shadow:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(1.6,1.3);shadow.mesh=quad;shadow.rotation.x=-PI*.5;shadow.position.y=.003
	var shadow_mat:=StandardMaterial3D.new();shadow_mat.albedo_texture=load("res://assets/textures/contact_shadow.png");shadow_mat.albedo_color=Color(0,0,0,.6);shadow_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;shadow_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;shadow.material_override=shadow_mat;add_child(shadow)
	rig=FighterRig.new();add_child(rig);rig.setup("knight")
	print("ROLL STUDIO READY")

func _process(_dt:float) -> void:
	frames+=1
	if frames%5==1:print("STUDIO FRAME ",frames)
	if frames<3:return
	if frames%4==0:
		if sample_id>=PHASES.size():
			var f:=FileAccess.open("res://artifacts/roll_mesh_audit.json",FileAccess.WRITE);f.store_string(JSON.stringify(samples,"  "));f.close();get_tree().quit();return
		phase=PHASES[sample_id];rig.initialized=false
	rig.pose("roll",phase*.70,1.0/60.0,0,Vector3.ZERO)
	if frames%4==3:
		if DisplayServer.get_name()!="headless":get_viewport().get_texture().get_image().save_png("res://artifacts/roll_pose_%02d.png"%sample_id)
		var result:=audit_mesh();result.phase=phase;samples.append(result);print("MESH AUDIT ",result)
		sample_id+=1

func audit_mesh() -> Dictionary:
	rig.skel.force_update_all_bone_transforms()
	var low:=100.0;var head_low:=100.0;var cloth_low:=100.0;var high:=-100.0
	var vertex_count:=0;var invalid_count:=0
	for mi in rig.model.find_children("*","MeshInstance3D",true,false):
		if not mi.skin:continue
		var transforms:Array[Transform3D]=[]
		for bind in mi.skin.get_bind_count():
			var bone:int=mi.skin.get_bind_bone(bind)
			if bone<0:bone=rig.skel.find_bone(mi.skin.get_bind_name(bind))
			transforms.append(rig.skel.global_transform*rig.skel.get_bone_global_pose(bone)*mi.skin.get_bind_pose(bind))
		for surface in mi.mesh.get_surface_count():
			var arr:Array=mi.mesh.surface_get_arrays(surface)
			var vertices:PackedVector3Array=arr[Mesh.ARRAY_VERTEX]
			var bones:PackedInt32Array=arr[Mesh.ARRAY_BONES]
			var weights:PackedFloat32Array=arr[Mesh.ARRAY_WEIGHTS]
			if bones.is_empty():continue
			for v in vertices.size():
				var point:=Vector3.ZERO;var is_head:=false;var is_cloth:=false
				for k in 4:
					var bi:int=bones[v*4+k];var w:float=weights[v*4+k]
					point+=(transforms[bi]*vertices[v])*w
					var bone:int=mi.skin.get_bind_bone(bi)
					if bone<0:bone=rig.skel.find_bone(mi.skin.get_bind_name(bi))
					var bn:String=rig.skel.get_bone_name(bone)
					if bn=="head" and w>.5:is_head=true
					if bn.begins_with("cape") and w>.3:is_cloth=true
				vertex_count+=1
				if not point.is_finite():invalid_count+=1;continue
				low=minf(low,point.y);high=maxf(high,point.y)
				if is_head:head_low=minf(head_low,point.y)
				if is_cloth:cloth_low=minf(cloth_low,point.y)
	return {"min_y":low,"helmet_min_y":head_low,"cloth_min_y":cloth_low,"max_y":high,"support":rig.roll_support,"finite":invalid_count==0,"vertices":vertex_count,"invalid_vertices":invalid_count}
