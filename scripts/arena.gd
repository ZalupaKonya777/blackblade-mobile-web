extends Node3D

var env:Environment
var floor_mat:Material
var flames:Array=[]
var lights:Array=[]
var moon:DirectionalLight3D
var time:=0.0
var stone:StandardMaterial3D
var trim:StandardMaterial3D
var dark:StandardMaterial3D
var brass:StandardMaterial3D
var fog_gate:Node3D
var radius:=19.0
var fill_light:DirectionalLight3D
var detail_nodes:Array=[]
var reflection_sky:Sky

func _ready() -> void:
	G.arena=self
	stone=_material(Color(.63,.62,.59),.87)
	stone.albedo_texture=load("res://assets/textures/masonry_surface.jpg")
	stone.normal_enabled=true;stone.normal_texture=load("res://assets/textures/masonry_normal.jpg");stone.normal_scale=.45
	stone.roughness_texture=load("res://assets/textures/masonry_orm.png");stone.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	stone.uv1_triplanar=true;stone.uv1_scale=Vector3(.20,.20,.20);stone.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	trim=_material(Color(.36,.35,.32),.76)
	trim.albedo_texture=stone.albedo_texture;trim.uv1_triplanar=true;trim.uv1_scale=Vector3.ONE*.17
	trim.normal_enabled=true;trim.normal_texture=stone.normal_texture;trim.normal_scale=.20
	dark=_material(Color(.043,.046,.050),.96);dark.cull_mode=BaseMaterial3D.CULL_DISABLED
	brass=_material(Color(.36,.29,.16),.33);brass.metallic=.82
	_environment();_floor();_architecture();_lighting();_oculus();_inner_pillars();_ornament();_merge_architecture();apply_quality()
	G.changed.connect(apply_quality)

func _material(color:Color,rough:float) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new();m.albedo_color=color;m.roughness=rough;return m

func _environment() -> void:
	var world:=WorldEnvironment.new();env=Environment.new()
	env.background_mode=Environment.BG_COLOR;env.background_color=Color(.022,.029,.040)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.57,.61,.68);env.ambient_light_energy=.37
	reflection_sky=Sky.new()
	if not G.mobile:
		var panorama:=PanoramaSkyMaterial.new();panorama.panorama=load("res://assets/textures/cathedral_reflection.hdr");panorama.energy_multiplier=.30;reflection_sky.sky_material=panorama
	reflection_sky.radiance_size=Sky.RADIANCE_SIZE_64;reflection_sky.process_mode=Sky.PROCESS_MODE_REALTIME
	env.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;env.tonemap_exposure=1.0
	env.fog_enabled=true;env.fog_light_color=Color(.095,.118,.15);env.fog_density=.0105
	env.fog_height=-1;env.fog_height_density=.045
	world.environment=env;add_child(world)

func _mesh(mesh:Mesh,pos:Vector3,mat:Material,parent:Node=null) -> MeshInstance3D:
	var mi:=MeshInstance3D.new();mi.mesh=mesh;mi.material_override=mat;mi.position=pos
	(parent if parent else self).add_child(mi)
	return mi

func _box(pos:Vector3,size:Vector3,mat:Material,parent:Node=null,collision:=false) -> MeshInstance3D:
	var bm:=BoxMesh.new();bm.size=size
	var mi:=_mesh(bm,pos,mat,parent)
	if collision:
		var body:=StaticBody3D.new();var cs:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size
		cs.shape=shape;body.add_child(cs);mi.add_child(body)
	return mi

func _cyl(pos:Vector3,r:float,h:float,mat:Material,parent:Node=null,top:float=-1) -> MeshInstance3D:
	var cm:=CylinderMesh.new();cm.top_radius=r if top<0 else top;cm.bottom_radius=r;cm.height=h;cm.radial_segments=24
	return _mesh(cm,pos,mat,parent)

func _torus(rad:float,width:float,y:float,mat:Material) -> MeshInstance3D:
	var tm:=TorusMesh.new();tm.inner_radius=rad-width*.5;tm.outer_radius=rad+width*.5;tm.rings=96;tm.ring_segments=6
	var mi:=_mesh(tm,Vector3(0,y,0),mat);mi.scale.y=.22;return mi

func _floor() -> void:
	var cm:=CylinderMesh.new();cm.top_radius=21;cm.bottom_radius=21;cm.height=.6;cm.radial_segments=128
	floor_mat=_material(Color(.37,.43,.53),.55)
	floor_mat.albedo_texture=load("res://assets/textures/floor_color.jpg");floor_mat.normal_enabled=true;floor_mat.normal_texture=load("res://assets/textures/floor_normal.jpg");floor_mat.uv1_scale=Vector3(18,18,18)
	_mesh(cm,Vector3(0,-.30,0),floor_mat)
	_box(Vector3(0,-.50,0),Vector3(100,1,100),stone,null,true).visible=false
	for i in 3:
		_torus(19.0+i*.35,.52,.06+i*.10,trim)
	for r in [3.2,3.4,7.4,7.65,12.0,17.4]:_torus(r,.035,.05,brass)
	_tiles()

func _arch(parent:Node3D,width:float,height:float,base:float) -> void:
	var path:Array[Vector2]=[]
	path.append(Vector2(-width*.5,0));path.append(Vector2(-width*.5,height*.55))
	for i in range(1,9):
		var t:=float(i)/8
		var a:=Vector2(-width*.5,height*.55);var b:=Vector2(-width*.5,height*.80);var c:=Vector2(0,height)
		path.append(a*(1-t)*(1-t)+b*2*(1-t)*t+c*t*t)
	for i in range(1,9):
		var t:=float(i)/8
		var a:=Vector2(0,height);var b:=Vector2(width*.5,height*.80);var c:=Vector2(width*.5,height*.55)
		path.append(a*(1-t)*(1-t)+b*2*(1-t)*t+c*t*t)
	path.append(Vector2(width*.5,0))
	for j in range(1,path.size()):
		var v:=path[j]-path[j-1];var center:Vector2=(path[j]+path[j-1])*.5
		var b:=_box(Vector3(center.x,base+center.y,-.35),Vector3(.42,v.length()+.035,.64),trim,parent)
		b.rotation.z=-atan2(v.x,v.y)
	# Recesses have real depth: inner returns, spandrels and a distant back wall.
	var returns:=SurfaceTool.new();returns.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spandrels:=SurfaceTool.new();spandrels.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1,path.size()):
		var a:Vector2=path[i-1];var b:Vector2=path[i]
		var points:=[Vector3(a.x,base+a.y,-.23),Vector3(b.x,base+b.y,-.23),Vector3(b.x,base+b.y,1.42),Vector3(a.x,base+a.y,1.42)]
		for idx in [0,2,1,0,3,2]:returns.set_uv(Vector2(points[idx].x,points[idx].y)*.35);returns.add_vertex(points[idx])
		if a.y>=height*.54 and b.y>=height*.54:
			var outside:=[Vector3(a.x,base+a.y,-.12),Vector3(b.x,base+b.y,-.12),Vector3(b.x,base+height+.15,-.12),Vector3(a.x,base+height+.15,-.12)]
			for idx in [0,1,2,0,2,3]:spandrels.set_uv(Vector2(outside[idx].x,outside[idx].y)*.20);spandrels.add_vertex(outside[idx])
	returns.generate_normals();returns.generate_tangents();_mesh(returns.commit(),Vector3.ZERO,trim,parent)
	spandrels.generate_normals();spandrels.generate_tangents();_mesh(spandrels.commit(),Vector3.ZERO,stone,parent)
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1,path.size()-1):
		st.add_vertex(Vector3(path[0].x,base+path[0].y,1.45))
		st.add_vertex(Vector3(path[i+1].x,base+path[i+1].y,1.45))
		st.add_vertex(Vector3(path[i].x,base+path[i].y,1.45))
	st.generate_normals();_mesh(st.commit(),Vector3.ZERO,dark,parent)
	_box(Vector3(0,base-.08,.56),Vector3(width,.18,1.9),trim,parent)
	for sx in [-1,1]:
		_box(Vector3(sx*(width*.5+.12),base+height*.27,-.43),Vector3(.52,height*.55,.85),stone,parent)
		_box(Vector3(sx*(width*.5+.12),base+.15,-.45),Vector3(.75,.3,1),trim,parent)

func _architecture() -> void:
	var count:=16
	for i in count:
		var a:=TAU*i/count
		var segment:=Node3D.new();segment.position=Vector3(sin(a)*20.1,0,cos(a)*20.1);segment.rotation.y=a;add_child(segment)
		for sx in [-1,1]:_box(Vector3(sx*3.46,8.0,.55),Vector3(1.25,16,1.4),stone,segment,true)
		for band in [Vector2(.0,.55),Vector2(6.75,7.65),Vector2(13.55,16)]:
			_box(Vector3(0,(band.x+band.y)*.5,.55),Vector3(8.15,band.y-band.x,1.4),stone,segment)
		_arch(segment,5.5,6.2,.55)
		_arch(segment,5.5,5.9,7.65)
		for h in [.22,6.85,7.20,13.90,15.6]:_box(Vector3(0,h,-.15),Vector3(8.4,.22,.8),trim,segment)
		var ca:=a+PI/count
		var dir:=Vector3(sin(ca),0,cos(ca))
		var pillar:=Node3D.new();pillar.position=dir*19.6;pillar.rotation.y=ca;add_child(pillar)
		_box(Vector3(0,7.8,0),Vector3(.9,15.6,1.4),trim,pillar)
		for sx in [-.33,0,.33]:_cyl(Vector3(sx,7.7,-.67),.13,14.8,stone,pillar)
		for h in [.2,1.0,6.85,7.2,13.9,15.7]:_box(Vector3(0,h,-.1),Vector3(1.5,.30,1.8),trim,pillar)
		if i%2==0:
			var bm:=QuadMesh.new();bm.size=Vector2(1.65,5.2);bm.subdivide_depth=18;bm.subdivide_width=3
			var sm:=ShaderMaterial.new();sm.shader=load("res://shaders/banner.gdshader");sm.set_shader_parameter("cloth",load("res://assets/textures/banner.png"))
			var flag:=_mesh(bm,Vector3(0,10,-1.1),sm,pillar);flag.rotation.y=PI
			_box(Vector3(0,12.7,-1.08),Vector3(2.0,.08,.08),brass,pillar)
		if i in [0,8]:
			for j in range(-4,5):_box(Vector3(j*.5,2.65,-.2),Vector3(.07,5.15,.08),brass,segment)
			for h in [1.1,2.5,4.0]:_box(Vector3(0,h,-.25),Vector3(4.4,.09,.10),brass,segment)
		if i==0:
			fog_gate=Node3D.new();segment.add_child(fog_gate)
			var qm:=QuadMesh.new();qm.size=Vector2(4.5,5.4)
			var fm:=ShaderMaterial.new();fm.shader=load("res://shaders/fog.gdshader")
			var gate:=_mesh(qm,Vector3(0,2.7,-.43),fm,fog_gate);gate.rotation.y=PI
	for h in [7.15,13.8,16.0]:_torus(19.35,.46,h,trim)

func _lighting() -> void:
	moon=DirectionalLight3D.new();moon.light_color=Color(.81,.87,1);moon.light_energy=.84;moon.rotation_degrees=Vector3(-54,-34,0)
	moon.shadow_enabled=true;moon.shadow_bias=.035;moon.shadow_normal_bias=1.2;moon.directional_shadow_max_distance=48;moon.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS;add_child(moon)
	fill_light=DirectionalLight3D.new();fill_light.light_color=Color(1,.80,.57);fill_light.light_energy=.18;fill_light.rotation_degrees=Vector3(-24,140,0);add_child(fill_light)
	var sky:=OmniLight3D.new();sky.position=Vector3(0,10,0);sky.omni_range=28;sky.light_energy=.85;sky.light_color=Color(.67,.76,.94);add_child(sky)
	for i in 16:
		var a:=TAU*(i+.5)/16;var dir:=Vector3(sin(a),0,cos(a))
		_brazier(dir*17.8,1.35)
		if i%2==0:_brazier(dir*18.6+Vector3.UP*6.3,.65)

func _brazier(pos:Vector3,height:float) -> void:
	var root:=Node3D.new();root.position=pos;add_child(root)
	_cyl(Vector3(0,height*.4,0),.28,height*.8,trim,root,.19)
	_cyl(Vector3(0,height*.82,0),.31,.25,brass,root,.43)
	_cyl(Vector3(0,.06,0),.47,.12,trim,root)
	for i in 5:
		var a:=TAU*i/5;var b:=_box(Vector3(sin(a)*.34,height*.95,cos(a)*.34),Vector3(.045,.43,.045),brass,root)
		b.rotation.z=sin(a)*-.22;b.rotation.x=cos(a)*.22
	var qm:=QuadMesh.new();qm.size=Vector2(.7,1.05);qm.subdivide_depth=8
	var fm:=ShaderMaterial.new();fm.shader=load("res://shaders/flame.gdshader")
	for a in [0,PI*.5]:
		var f:=_mesh(qm,Vector3(0,height+.28,0),fm,root);f.rotation.y=a;flames.append(f)
	var halo_mesh:=QuadMesh.new();halo_mesh.size=Vector2(1.7,1.7)
	var halo:=StandardMaterial3D.new();halo.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;halo.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;halo.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;halo.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	halo.albedo_texture=load("res://assets/textures/light_halo.png");halo.albedo_color=Color(.20,.49,1,.28)
	var glow:=_mesh(halo_mesh,Vector3(0,height+.31,0),halo,root);glow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light:=OmniLight3D.new();light.position=Vector3(0,height+.40,0);light.omni_range=6;light.light_color=Color(.29,.59,1);light.light_energy=2.0
	root.add_child(light);lights.append(light)

func _beam(a:Vector3,b:Vector3,r:float,mat:Material) -> void:
	var mi:=_cyl((a+b)*.5,r,a.distance_to(b),mat)
	var dir:=(b-a).normalized();mi.basis=Basis(Quaternion(Vector3.UP,dir))

func _oculus() -> void:
	_torus(6.2,.5,19.2,trim);_torus(6.05,.08,19.05,brass)
	# The ribs support a continuous vaulted stone ceiling around the open oculus.
	var vault:=SurfaceTool.new();vault.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sector in 64:
		for ring in 10:
			var corners:Array[Vector3]=[]
			for uv in [Vector2(sector/64.0,ring/10.0),Vector2((sector+1)/64.0,ring/10.0),Vector2((sector+1)/64.0,(ring+1)/10.0),Vector2(sector/64.0,(ring+1)/10.0)]:
				var a:float=uv.x*TAU;var r:=lerpf(19.4,6.2,uv.y)
				corners.append(Vector3(sin(a)*r,15.7+sin(uv.y*PI*.5)*3.5,cos(a)*r))
			for idx in [0,1,2,0,2,3]:vault.set_uv(Vector2(corners[idx].x,corners[idx].z)*.20);vault.add_vertex(corners[idx])
	vault.generate_normals();vault.generate_tangents();_mesh(vault.commit(),Vector3.ZERO,stone)
	for i in 16:
		var a:=TAU*i/16;var dir:=Vector3(sin(a),0,cos(a));var prior:=dir*19.4+Vector3.UP*15.7
		for j in range(1,6):
			var t:=float(j)/5;var p:=dir*lerpf(19.4,6.2,t)+Vector3.UP*(15.7+sin(t*PI*.5)*3.5)
			_beam(prior,p,.16,trim);prior=p
		# Hanging metal teeth around the opening echo the arena reference.
		var tip:=dir*6.18+Vector3.UP*18.7
		_beam(tip,tip+Vector3.DOWN*.85,.055,brass)
	var qm:=QuadMesh.new();qm.size=Vector2(12,12)
	var glow:=_material(Color(.23,.37,.57),1);glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;glow.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;glow.albedo_color.a=.24
	var mi:=_mesh(qm,Vector3(0,19.5,0),glow);mi.rotation.x=PI*.5

func _ornament() -> void:
	var rng:=RandomNumberGenerator.new();rng.seed=428
	var wear:=StandardMaterial3D.new();wear.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;wear.albedo_texture=load("res://assets/textures/ground_wear.png");wear.albedo_color=Color(.50,.46,.38,.65);wear.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 26:
		var a:=rng.randf()*TAU;var r:=rng.randf_range(9,18)
		var qm:=QuadMesh.new();qm.size=Vector2(rng.randf_range(1.8,4.5),rng.randf_range(1.5,3.2))
		var decal:=_mesh(qm,Vector3(sin(a)*r,.063,cos(a)*r),wear);decal.rotation=Vector3(-PI*.5,rng.randf()*TAU,0);decal.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 16:
		var a:=TAU*(i+.5)/16;var dir:=Vector3(sin(a),0,cos(a));var pos:=dir*19.6
		var arch_angle:=TAU*i/16;var arch_dir:=Vector3(sin(arch_angle),0,cos(arch_angle))
		for h in [1.1,6.55,7.45,13.7]:
			_cyl(pos+Vector3.UP*h,.62,.16,trim,null,.48)
			_cyl(pos+Vector3.UP*(h+.14),.47,.12,stone,null,.38)
		if i%2==0:
			var niche:=Node3D.new();niche.position=arch_dir*20.7;niche.rotation.y=arch_angle+PI;add_child(niche)
			var statue:Node3D=load("res://assets/characters/warden_statue.glb").instantiate();statue.position=Vector3(0,7.5,0);statue.scale=Vector3.ONE*1.25;niche.add_child(statue)
			for mi in statue.find_children("*","MeshInstance3D",true,false):mi.material_override=trim
			_cyl(Vector3(0,7.43,0),.62,.20,trim,niche)
			_box(Vector3(0,7.17,0),Vector3(1.25,.32,1.25),stone,niche)
		if i%2==1:
			var lower:=Node3D.new();lower.position=arch_dir*20.5;lower.rotation.y=arch_angle+PI;add_child(lower)
			var statue:Node3D=load("res://assets/characters/warden_statue.glb").instantiate();statue.position.y=.78;statue.scale=Vector3.ONE*1.42;lower.add_child(statue)
			for mi in statue.find_children("*","MeshInstance3D",true,false):mi.material_override=trim
			_box(Vector3(0,.40,0),Vector3(1.65,.8,1.45),stone,lower)
			if i%4==1:
				var shrine:=OmniLight3D.new();shrine.position=arch_dir*19.3+Vector3.UP*2.8;shrine.omni_range=4.5;shrine.light_color=Color(1,.72,.43);shrine.light_energy=.85;add_child(shrine);detail_nodes.append(shrine)
		# Small warm votives give the cold braziers a second lighting colour.
		if i%2==0:
			var candle_mat:=_material(Color(.38,.27,.12),.95)
			for j in 3:
				var cp:Vector3=dir*18.7+Vector3(cos(a),0,-sin(a))*(j-1)*.23
				var h:=.20+float(j%2)*.16
				_cyl(cp+Vector3.UP*(h*.5+.06),.055,h,candle_mat)
				var qm:=QuadMesh.new();qm.size=Vector2(.055,.17)
				var flame:=_material(Color(1,.65,.22),1);flame.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;flame.emission_enabled=true;flame.emission=Color(1,.48,.08);flame.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
				_mesh(qm,cp+Vector3.UP*(h+.13),flame)
			var warm:=OmniLight3D.new();warm.position=dir*18.3+Vector3.UP*.65;warm.omni_range=4.2;warm.light_color=Color(1,.53,.19);warm.light_energy=.65;add_child(warm);detail_nodes.append(warm)
	# Chips and broken masonry accumulate at the edge, away from the combat space.
	for i in 85:
		var a:=rng.randf()*TAU;var r:=rng.randf_range(15.9,18.7)
		var size:=Vector3(rng.randf_range(.09,.38),rng.randf_range(.04,.15),rng.randf_range(.10,.42))
		var chip:=_box(Vector3(sin(a)*r,size.y*.5+.035,cos(a)*r),size,trim)
		chip.rotation=Vector3(rng.randf_range(-.3,.3),rng.randf()*TAU,rng.randf_range(-.3,.3))

func _inner_pillars() -> void:
	for v in [Vector3(-10,0,-7),Vector3(10,0,-7),Vector3(-11,0,7),Vector3(11,0,7)]:
		var h:=3.4 if v.z>0 else 4.7
		_box(v+Vector3.UP*.20,Vector3(2.1,.4,2.1),trim,null,true)
		_box(v+Vector3.UP*(h*.5+.4),Vector3(1.0,h,1.1),stone,null,true)
		for sx in [-.40,.40]:_cyl(v+Vector3(sx,h*.5+.4,-.5),.12,h,trim)
		_box(v+Vector3.UP*(h+.5),Vector3(1.45,.25,1.55),trim)
		for j in 5:
			var p:Vector3=v+Vector3(randf_range(-1.7,1.7),.12,randf_range(-1.7,1.7))
			var b:=_box(p,Vector3(randf_range(.15,.45),randf_range(.15,.32),randf_range(.15,.45)),trim);b.rotation.y=randf()*PI

func rage(on:bool) -> void:
	var tw:=create_tween();tw.set_parallel(true)
	tw.tween_property(moon,"light_color",Color(.90,.74,.76) if on else Color(.81,.87,1),2.0)
	tw.tween_property(floor_mat,"albedo_color",Color(.62,.57,.56) if on else Color(.65,.64,.61),2.0)

func _process(dt:float) -> void:
	time+=dt
	for i in lights.size():lights[i].light_energy=2.2+sin(time*7+i)*.24+sin(time*17+i*.8)*.12

func _merge_architecture() -> void:
	var groups:={}
	var materials:={}
	for mi in find_children("*","MeshInstance3D",true,false):
		if mi.skin!=null:continue
		if mi.material_override not in [stone,trim,dark,brass] or not mi.visible:continue
		var p:Vector3=mi.global_position
		var sector:=int(floor((atan2(p.x,p.z)+PI)/TAU*8))
		var key:=str(mi.material_override.get_instance_id())+"_"+str(sector)
		if not groups.has(key):
			var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);groups[key]=st;materials[key]=mi.material_override
		groups[key].append_from(mi.mesh,0,mi.global_transform)
		mi.visible=false
	for key in groups:
		var m:Mesh=groups[key].commit()
		_mesh(m,Vector3.ZERO,materials[key])

func _tiles() -> void:
	var under:=_material(Color(.06,.08,.11),.9)
	for mi in get_children():
		if mi is MeshInstance3D and mi.material_override==floor_mat:mi.material_override=under
	floor_mat=_material(Color(.65,.64,.61),.78)
	floor_mat.albedo_texture=load("res://assets/textures/slate_surface.jpg")
	floor_mat.normal_enabled=true;floor_mat.normal_texture=load("res://assets/textures/slate_normal.jpg");floor_mat.normal_scale=.38
	floor_mat.roughness_texture=load("res://assets/textures/slate_orm.png");floor_mat.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	floor_mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	floor_mat.vertex_color_use_as_albedo=true
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in 11:
		var inner:=maxf(.025,ring*1.7+.02);var outer:float=(ring+1)*1.7-.02
		var count:=maxi(8,roundi(TAU*(inner+outer)*.5/2.1))
		for j in count:
			var a0:=TAU*j/count+.002;var a1:=TAU*(j+1)/count-.002
			var points:=[Vector3(sin(a0)*inner,.030,cos(a0)*inner),Vector3(sin(a1)*inner,.030,cos(a1)*inner),Vector3(sin(a1)*outer,.030,cos(a1)*outer),Vector3(sin(a0)*outer,.030,cos(a0)*outer)]
			var shade:=randf_range(.73,1.06);st.set_color(Color(shade,shade,shade))
			for idx in [0,1,2,0,2,3]:
				var p:Vector3=points[idx];st.set_uv(Vector2(p.x,p.z)*.40);st.add_vertex(p)
			for edge in 4:
				var p0:Vector3=points[edge];var p1:Vector3=points[(edge+1)%4]
				var q0:=p0-Vector3.UP*.026;var q1:=p1-Vector3.UP*.026
				for v in [p0,q0,p1,p1,q0,q1]:st.set_uv(Vector2(v.x,v.z)*.40);st.add_vertex(v)
	st.generate_normals();st.generate_tangents();_mesh(st.commit(),Vector3.ZERO,floor_mat)
	# Eight-point inlaid seal at the centre of the circular paving.
	var star:=SurfaceTool.new();star.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 16:
		var a:=i*TAU/16;var b:=(i+1)*TAU/16
		var r0:=2.85 if i%2==0 else .66;var r1:=2.85 if (i+1)%2==0 else .66
		var p0:=Vector3(sin(a)*r0,.055,cos(a)*r0);var p1:=Vector3(sin(b)*r1,.055,cos(b)*r1)
		var side:=Vector3(-(p1-p0).z,0,(p1-p0).x).normalized()*.045
		for v in [p0-side,p0+side,p1-side,p1-side,p0+side,p1+side]:star.add_vertex(v)
	star.generate_normals();_mesh(star.commit(),Vector3.ZERO,brass)

func apply_quality() -> void:
	var quality:int=G.settings.get("quality",1)
	if "--low" in OS.get_cmdline_user_args():quality=0
	if "--beauty" in OS.get_cmdline_user_args():quality=1
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY if quality>0 else Environment.REFLECTION_SOURCE_DISABLED
	env.sky=reflection_sky if quality>0 else null
	moon.shadow_enabled=quality>0
	for l in lights:l.visible=quality>0
	for l in detail_nodes:l.visible=quality>0
	get_viewport().scaling_3d_scale=.85 if quality==0 else 1.0
	get_viewport().msaa_3d=Viewport.MSAA_DISABLED if quality==0 else Viewport.MSAA_4X
	stone.normal_enabled=quality>0
	trim.normal_enabled=quality>0
	stone.uv1_triplanar=quality>0;trim.uv1_triplanar=quality>0
	stone.roughness_texture=load("res://assets/textures/masonry_orm.png") if quality>0 else null
	var software:=RenderingServer.get_video_adapter_name().to_lower().contains("llvmpipe")
	var filter:=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if software or quality==0 else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	stone.texture_filter=filter;trim.texture_filter=filter
	if floor_mat is StandardMaterial3D:floor_mat.texture_filter=filter
	if floor_mat is StandardMaterial3D:floor_mat.normal_enabled=quality>0
	if G.mobile:
		# Preserve the stone response; save the phone's budget on shadows and fill lights.
		moon.shadow_enabled=false
		for l in lights:l.visible=false
		for l in detail_nodes:l.visible=false
		get_viewport().msaa_3d=Viewport.MSAA_DISABLED
		get_viewport().scaling_3d_scale=.85
		stone.normal_enabled=true;trim.normal_enabled=true
		if floor_mat is StandardMaterial3D:floor_mat.normal_enabled=true
