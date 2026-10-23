extends Node3D
## A deliberately plain stage for reviewing the actual supplied skinned mesh.
var rig:FighterRig
var cam:Camera3D
var frame:=0
var sample_id:=0
var current:Dictionary={}
var samples:Array=[]
const SHOTS=[
 {"id":"idle","t":0.0}, {"id":"sweep","t":.52}, {"id":"sweep","t":.76},
 {"id":"combo","t":1.46}, {"id":"overhead","t":.82}, {"id":"overhead","t":1.18},
 {"id":"lunge","t":.69}, {"id":"leap","t":.80}, {"id":"leap","t":1.60},
 {"id":"air_blades","t":1.44}, {"id":"spin","t":1.31}, {"id":"death_storm","t":1.28}, {"id":"dead","t":2.0}]

func _ready() -> void:
	var world:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.075,.085,.10);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.68,.75,.86);env.ambient_light_energy=.62;world.environment=env;add_child(world)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-42,-32,0);light.light_color=Color(1,.89,.72);light.light_energy=1.2;add_child(light)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-24,148,0);fill.light_color=Color(.34,.52,1);fill.light_energy=.6;add_child(fill)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(100,100);ground.mesh=plane
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.16,.18,.21);mat.roughness=.85;ground.material_override=mat;add_child(ground)
	var shadow:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(3.1,3.5);shadow.mesh=quad;shadow.rotation.x=-PI*.5;shadow.position=Vector3(0,.005,.20)
	var sm:=StandardMaterial3D.new();sm.albedo_texture=load("res://assets/textures/contact_shadow.png");sm.albedo_color=Color(0,0,0,.65);sm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;sm.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;shadow.material_override=sm;add_child(shadow)
	cam=Camera3D.new();cam.position=Vector3(4.8,2.9,6.2);add_child(cam);cam.look_at(Vector3(0,1.4,.4));cam.current=true;cam.fov=44
	rig=FighterRig.new();add_child(rig);rig.setup("boss");rig.scale=Vector3.ONE*1.2
	print("BEAST STUDIO READY")
	if "--bench" in OS.get_cmdline_user_args():
		for enabled in [true,false]:
			var probes:Array=rig.beast_cloth_probes
			if not enabled:rig.beast_cloth_probes=[]
			var start:=Time.get_ticks_usec()
			for i in 120:rig.pose("combo",float(i)/60,1.0/60.0,0,Vector3.ZERO)
			print("BEAST POSE BENCH probes=",enabled," ms=",(Time.get_ticks_usec()-start)/120000.0)
			rig.beast_cloth_probes=probes
		get_tree().quit()

func _process(_dt:float) -> void:
	frame+=1
	if frame<3:return
	if frame%3==0:
		if sample_id>=SHOTS.size():
			var file:=FileAccess.open("res://artifacts/beast_mesh_audit.json",FileAccess.WRITE);file.store_string(JSON.stringify(samples,"  "));file.close();get_tree().quit();return
		current=SHOTS[sample_id];rig.initialized=false
		# Warm the cloth at this pose without blending from an unrelated attack.
		for i in 8:rig.pose(current.id,current.t,1.0/60.0,0,Vector3.ZERO)
	if frame%3==2 and not current.is_empty():
		if DisplayServer.get_name()!="headless":get_viewport().get_texture().get_image().save_png("res://artifacts/beast_pose_%02d_%s.png"%[sample_id,current.id])
		var auditor=load("res://tools/roll_studio.gd").new();auditor.rig=rig
		var result:Dictionary=auditor.audit_mesh();auditor.free();result.id=current.id;result.t=current.t;result.paw=rig.beast_contacts.paw
		samples.append(result);print("BEAST AUDIT ",result);sample_id+=1
