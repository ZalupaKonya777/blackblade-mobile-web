extends Node3D

var particles:Array=[]
var effects:Array=[]
var projectiles:Array=[]
var waves:Array=[]
var combat_stats:={"waves":0,"projectiles":0,"wave_contacts":0}
var trail_data:={}
var trail_nodes:={}
var mesh:MultiMesh
var spark_mat:StandardMaterial3D
var time:=0.0
var charge_timer:=0.0
var fire_timer:=0.0
var dust:Array=[]
var dust_mesh:QuadMesh

func _ready() -> void:
	G.fx=self
	spark_mat=StandardMaterial3D.new();spark_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;spark_mat.vertex_color_use_as_albedo=true
	var sphere:=SphereMesh.new();sphere.radius=.025;sphere.height=.05;sphere.radial_segments=6;sphere.rings=3
	mesh=MultiMesh.new();mesh.transform_format=MultiMesh.TRANSFORM_3D;mesh.use_colors=true;mesh.mesh=sphere;mesh.instance_count=420;mesh.visible_instance_count=0
	var mi:=MultiMeshInstance3D.new();mi.multimesh=mesh;mi.material_override=spark_mat;mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(mi)
	dust_mesh=QuadMesh.new();dust_mesh.size=Vector2.ONE

func ground_contact(at:Vector3,direction:Vector3,weight:float) -> void:
	for i in 6:
		if dust.size()>=44:break
		var mi:=MeshInstance3D.new();mi.mesh=dust_mesh;mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat:=StandardMaterial3D.new();mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED;mat.no_depth_test=false
		mat.albedo_texture=load("res://assets/textures/dust_soft.png");mat.albedo_color=Color(.46,.43,.37,.20*weight)
		mi.material_override=mat;mi.position=at+Vector3(randf_range(-.20,.20),.09,randf_range(-.20,.20));mi.scale=Vector3.ONE*.20;add_child(mi)
		var v:Vector3=direction*randf_range(.20,.7)+Vector3(randf_range(-.35,.35),randf_range(.12,.4),randf_range(-.35,.35))
		dust.append({"node":mi,"age":0.0,"life":randf_range(.4,.7),"velocity":v,"weight":weight})

func _mat(c:Color) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new();m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;m.blend_mode=BaseMaterial3D.BLEND_MODE_ADD;m.cull_mode=BaseMaterial3D.CULL_DISABLED;m.albedo_color=c;m.vertex_color_use_as_albedo=true
	return m

func burst(at:Vector3,color:Color,count:int=18,force:float=3) -> void:
	for i in count:
		if particles.size()>=420:break
		var v:=Vector3(randf_range(-1,1),randf_range(.1,1.4),randf_range(-1,1)).normalized()*randf_range(force*.3,force)
		particles.append({"p":at,"v":v,"life":randf_range(.25,.65),"age":0.0,"color":color,"scale":randf_range(.5,1.6)})

func trail(id:String,blade:Array,active:bool,color:Color) -> void:
	if not trail_data.has(id):
		trail_data[id]=[]
		var mi:=MeshInstance3D.new();mi.mesh=ImmediateMesh.new();var material:=ShaderMaterial.new();material.shader=load("res://shaders/sword_trail.gdshader");mi.material_override=material;mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(mi);trail_nodes[id]=mi
	if active:trail_data[id].append([blade[0],blade[1],time,color])

func blade_fire(blade:Array) -> void:
	if time<fire_timer:return
	fire_timer=time+.04
	var p:Vector3=blade[0].lerp(blade[1],randf_range(.2,1))
	if particles.size()<400:particles.append({"p":p,"v":Vector3(randf_range(-.4,.4),randf_range(.4,1.4),randf_range(-.4,.4)),"life":.30,"age":0.0,"color":Color(1,.08,.03),"scale":randf_range(1,2)})

func charge(at:Vector3) -> void:
	if time<charge_timer:return
	charge_timer=time+.13;burst(at,Color(1,.65,.22),3,1.2)

func heal(at:Vector3) -> void:
	burst(at+Vector3.UP*.7,Color(1,.65,.22),32,1.8);ring(at,.9,Color(1,.67,.25),.7)

func ring(at:Vector3,radius:float,color:Color,life:float) -> void:
	var tm:=TorusMesh.new();tm.inner_radius=.94;tm.outer_radius=1.0;tm.rings=64;tm.ring_segments=4
	var mi:=MeshInstance3D.new();mi.mesh=tm;mi.material_override=_mat(color);mi.position=Vector3(at.x,.05,at.z);mi.scale=Vector3(.05,.3,.05);add_child(mi)
	effects.append({"node":mi,"age":0.0,"life":life,"r":radius,"kind":"ring"})

func slam(at:Vector3,radius:float,cursed:=false) -> void:
	burst(at+Vector3.UP*.14,Color(.5,.58,.66) if not cursed else Color(1,.18,.08),40,5)
	ring(at,radius,Color(.36,.56,.81,.6) if not cursed else Color(.95,.12,.08,.7),.65)

func telegraph(at:Vector3,radius:float,life:float,cursed:=false) -> void:
	var torus:=TorusMesh.new();torus.inner_radius=.985;torus.outer_radius=1;torus.rings=64;torus.ring_segments=4
	var mi:=MeshInstance3D.new();mi.mesh=torus;mi.material_override=_mat(Color(.66,.60,.43,.22) if not cursed else Color(.68,.04,.025,.27));mi.position=Vector3(at.x,.038,at.z);mi.scale=Vector3(radius,.12,radius);add_child(mi)
	effects.append({"node":mi,"age":0.0,"life":life,"r":radius,"kind":"tell"})

func shockwave(at:Vector3,radius:float,damage:float,cursed:=false,life:=.60) -> void:
	var torus:=TorusMesh.new();torus.inner_radius=.92;torus.outer_radius=1.0;torus.rings=80;torus.ring_segments=6
	var mi:=MeshInstance3D.new();mi.mesh=torus;mi.material_override=_mat(Color(.6,.7,.9,.65) if not cursed else Color(1,.13,.08,.8));mi.position=Vector3(at.x,.10,at.z);mi.scale=Vector3(.05,.45,.05);add_child(mi)
	var distance:float=G.flat(G.player.global_position-at).length() if G.player else 100.0
	waves.append({"node":mi,"at":at,"r":radius,"damage":damage,"cursed":cursed,"life":life,"age":0.0,"consumed":false,"distance":distance})
	combat_stats.waves+=1

func death_cut(at:Vector3,radius:float,index:int) -> void:
	ring(at,radius,Color(1,.07,.06,.65),.3)
	for i in 5:
		var a:=randf()*TAU;burst(at+Vector3(sin(a)*radius*randf(),randf_range(.2,1.6),cos(a)*radius*randf()),Color(1,.14,.08),3,2.5)

func projectile(at:Vector3,target:Vector3,damage:float,speed:float,orientation:int) -> void:
	var root:=Node3D.new();add_child(root);root.global_position=at
	var im:=ImmediateMesh.new();im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 16:
		var x0:float=lerpf(-1.20,1.20,float(i)/16);var x1:float=lerpf(-1.20,1.20,float(i+1)/16)
		var y0:=x0*x0*.55-.5;var y1:=x1*x1*.55-.5
		for p in [Vector3(x0,y0,0),Vector3(x1,y1,0),Vector3(x0,y0+.18,0),Vector3(x1,y1,0),Vector3(x1,y1+.18,0),Vector3(x0,y0+.18,0)]:
			im.surface_set_color(Color(1,.7,.5,clampf(1-absf(p.x)/1.35,.05,1)))
			im.surface_add_vertex(p)
	im.surface_end()
	var mi:=MeshInstance3D.new();mi.mesh=im;mi.material_override=_mat(Color(1,.055,.04,.95));mi.rotation.z=.35 if orientation==0 else -.35;root.add_child(mi)
	var dir:=(target-at).normalized();root.look_at(at+dir,Vector3.UP)
	projectiles.append({"node":root,"dir":dir,"speed":speed,"damage":damage,"age":0.0})
	combat_stats.projectiles+=1

func reset() -> void:
	for e in effects:if is_instance_valid(e.node):e.node.queue_free()
	for p in projectiles:if is_instance_valid(p.node):p.node.queue_free()
	for w in waves:if is_instance_valid(w.node):w.node.queue_free()
	effects.clear();projectiles.clear();waves.clear();particles.clear();trail_data.clear()
	combat_stats={"waves":0,"projectiles":0,"wave_contacts":0}
	for n in trail_nodes.values():n.queue_free()
	trail_nodes.clear();mesh.visible_instance_count=0
	for d in dust:if is_instance_valid(d.node):d.node.queue_free()
	dust.clear()

func _process(dt:float) -> void:
	time+=dt
	for i in range(dust.size()-1,-1,-1):
		var d:Dictionary=dust[i];d.age+=dt
		if d.age>=d.life:d.node.queue_free();dust.remove_at(i);continue
		var f:float=d.age/d.life
		d.node.position+=d.velocity*dt;d.velocity*=exp(-3*dt)
		d.node.scale=Vector3.ONE*(.20+f*.75)
		(d.node.material_override as StandardMaterial3D).albedo_color.a=sin(f*PI)*.24*d.weight
	for i in range(particles.size()-1,-1,-1):
		var p:Dictionary=particles[i];p.age+=dt
		if p.age>=p.life:particles.remove_at(i);continue
		p.v.y-=7*dt;p.p+=p.v*dt
		if p.p.y<.03:p.p.y=.03;p.v.y=absf(p.v.y)*.25;p.v*=.7
	mesh.visible_instance_count=particles.size()
	for i in particles.size():
		var p:Dictionary=particles[i];var f:float=1-p.age/p.life
		var stretch:Vector3=Vector3(.60,clampf(p.v.length()*.45,1.1,3.8),.60)*p.scale*f
		var orient:=Basis(Quaternion(Vector3.UP,p.v.normalized())) if p.v.length()>.02 else Basis()
		var tr:=Transform3D(orient.scaled(stretch),p.p)
		mesh.set_instance_transform(i,tr);mesh.set_instance_color(i,p.color*f)
	for i in range(effects.size()-1,-1,-1):
		var e:Dictionary=effects[i];e.age+=dt
		if e.age>=e.life:e.node.queue_free();effects.remove_at(i);continue
		var f:float=e.age/e.life
		if e.kind=="tell":
			e.node.scale=Vector3(e.r,.12,e.r)
			(e.node.material_override as StandardMaterial3D).albedo_color.a=.10+.20*f+sin(f*TAU*3)*.025
		else:
			e.node.scale=Vector3.ONE*lerpf(.1,e.r,sqrt(f));e.node.scale.y=.3
			(e.node.material_override as StandardMaterial3D).albedo_color.a=(1-f)*.65
	for id in trail_data:
		var data:Array=trail_data[id]
		while data.size()>0 and time-data[0][2]>.17:data.pop_front()
		var im:ImmediateMesh=trail_nodes[id].mesh;im.clear_surfaces()
		if data.size()<2:continue
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in range(1,data.size()):
			var a:Array=data[j-1];var b:Array=data[j];var color:Color=b[3];color.a*=clampf(1-(time-b[2])/.17,0,1)
			var uv:=[Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
			var vertices:=[a[0],a[1],b[0],a[1],b[1],b[0]]
			for k in 6:
				var old:bool=uv[k].y==0
				var tint:Color=color;tint.a*=clampf(1-(time-a[2])/.17,0,1) if old else 1.0
				im.surface_set_color(tint);im.surface_set_uv(uv[k]);im.surface_add_vertex(vertices[k])
		im.surface_end()

func _physics_process(dt:float) -> void:
	if not G.playing or G.freeze>0:return
	if G.boss and not G.boss.alive():
		for w in waves:w.node.queue_free()
		for p in projectiles:p.node.queue_free()
		waves.clear();projectiles.clear();return
	for i in range(waves.size()-1,-1,-1):
		var w:Dictionary=waves[i]
		var old_radius:float=w.r*clampf(w.age/w.life,0,1)
		w.age+=dt
		var radius:float=w.r*clampf(w.age/w.life,0,1)
		w.node.scale=Vector3(maxf(.025,radius),.45,maxf(.025,radius))
		(w.node.material_override as StandardMaterial3D).albedo_color.a=.80*(1-smoothstep(.78,1.0,w.age/w.life))
		if not w.consumed and G.player and G.player.alive():
			var distance:float=G.flat(G.player.global_position-w.at).length()
			var before:float=w.distance-old_radius;var after:float=distance-radius
			var crossed:=minf(absf(before),absf(after))<.52 or before*after<0
			if crossed and distance<float(w.r)+.52:
				# A successful roll/jump consumes this crossing too: no late repeat hit.
				w.consumed=true;combat_stats.wave_contacts+=1
				if G.player.global_position.y<.4:G.player.receive_hit(w.damage,w.at,65,w.cursed,false,true)
			w.distance=distance
		if w.age>=w.life:w.node.queue_free();waves.remove_at(i)
	for i in range(projectiles.size()-1,-1,-1):
		var p:Dictionary=projectiles[i];p.age+=dt
		var old:Vector3=p.node.global_position;var next:Vector3=old+p.dir*p.speed*dt
		var query:=PhysicsRayQueryParameters3D.create(old,next,1)
		var hit:=get_world_3d().direct_space_state.intersect_ray(query)
		var remove:bool=not hit.is_empty() or p.age>4
		if not remove and G.player and G.player.alive():
			var center:Vector3=G.player.global_position+Vector3.UP*.9
			if center.distance_to(CombatMath.point_segment(center,old,next))<.83:
				G.player.receive_hit(p.damage,old,70,true);remove=true
		p.node.global_position=next
		if remove:
			burst(next,Color(.85,.12,.07),8,2);p.node.queue_free();projectiles.remove_at(i)
