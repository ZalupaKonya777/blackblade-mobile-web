extends Node3D
## Small local effects keep contact, scale and depth visible at either quality level.
var contacts:Array=[]
var motes:MultiMesh
var clock:=0.0
var ray_mat:StandardMaterial3D

func _ready() -> void:
	for actor in [G.player,G.boss]:
		for i in 3:
			var qm:=QuadMesh.new();qm.size=Vector2.ONE
			var mi:=MeshInstance3D.new();mi.mesh=qm;mi.rotation.x=-PI*.5;mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat:=StandardMaterial3D.new();mat.albedo_texture=load("res://assets/textures/contact_shadow.png");mat.albedo_color=Color(.014,.018,.024,.48);mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.material_override=mat;add_child(mi);contacts.append({"node":mi,"actor":actor,"part":i})
	motes=MultiMesh.new();motes.transform_format=MultiMesh.TRANSFORM_3D;motes.use_colors=true
	var sphere:=SphereMesh.new();sphere.radius=.008;sphere.height=.016;sphere.radial_segments=4;sphere.rings=2;motes.mesh=sphere;motes.instance_count=90
	var mi:=MultiMeshInstance3D.new();mi.multimesh=motes
	var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.vertex_color_use_as_albedo=true;mat.albedo_color=Color(.40,.42,.44);mi.material_override=mat;mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(mi)
	# Soft shafts descend from the oculus. These are faint transparent volumes,
	# not a full-screen fog pass, so their edges remain out of the player's face.
	ray_mat=StandardMaterial3D.new();ray_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;ray_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;ray_mat.albedo_color=Color(.56,.66,.83,.035);ray_mat.albedo_texture=load("res://assets/textures/dust_soft.png");ray_mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	for i in 3:
		var qm:=QuadMesh.new();qm.size=Vector2(3.2,18)
		var ray:=MeshInstance3D.new();ray.mesh=qm;ray.material_override=ray_mat;ray.position=Vector3(-1.0+i*1.7,10,0);ray.rotation=Vector3(.12,float(i)*PI/3,.22);ray.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(ray)

func _process(dt:float) -> void:
	clock+=dt
	for e in contacts:
		var actor:Node3D=e.actor
		if not is_instance_valid(actor):continue
		var unit:=1.0 if actor==G.player else 2.0
		var pos:Vector3=actor.global_position
		var width:=1.05*unit
		var length:=.72*unit
		if e.part>0:
			var side:="l" if e.part==1 else "r"
			if actor.rig.feet.has(side):pos=actor.rig.motion.to_global(actor.rig.feet[side])
			width=.45*unit;length=.48*unit
		e.node.position=Vector3(pos.x,.068+e.part*.002,pos.z)
		e.node.rotation.y=actor.yaw
		e.node.scale=Vector3(width,length,1)
		var height:=maxf(0,pos.y-.1)
		(e.node.material_override as StandardMaterial3D).albedo_color.a=(.38 if e.part==0 else .48)*exp(-height*2.2)
	for i in motes.instance_count:
		var seed:=float(i)
		var p:=Vector3(sin(seed*12.37)*16, fposmod(seed*.531+clock*.032,13)+.5,cos(seed*8.73)*16)
		p+=Vector3(sin(clock*.31+seed)*.23,0,cos(clock*.24+seed)*.2)
		motes.set_instance_transform(i,Transform3D(Basis(),p))
		var flicker:=.28+sin(clock*.7+seed)*.12
		motes.set_instance_color(i,Color(flicker*.85,flicker*.91,flicker))
