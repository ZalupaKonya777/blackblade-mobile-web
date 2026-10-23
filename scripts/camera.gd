extends Node3D

var cam:Camera3D
var yaw:=0.0
var pitch:=.13
var distance:=4.7
var pivot:=Vector3.ZERO
var trauma:=0.0
var cinematic:=true
var cine_position:=Vector3(7,3.1,2.5)
var cine_target:=Vector3(0,1.5,-6)
var mouse_delta:=Vector2.ZERO
var clock:=0.0
var landing_spring:=0.0
var landing_velocity:=0.0
var smoothed_zoom:=4.9
var camera_ready:=false
var post:ShaderMaterial
var impact_offset:=Vector3.ZERO
var impact_velocity:=Vector3.ZERO

func _ready() -> void:
	G.camera=self
	cam=Camera3D.new();cam.fov=59;cam.near=.07;cam.far=110;cam.current=true;add_child(cam)
	var fill:=OmniLight3D.new();fill.light_color=Color(.90,.88,.82);fill.light_energy=.23;fill.omni_range=11;fill.light_specular=.65;cam.add_child(fill)
	var grading:=CanvasLayer.new();grading.layer=5;add_child(grading)
	var screen:=ColorRect.new();screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);screen.mouse_filter=Control.MOUSE_FILTER_IGNORE
	post=ShaderMaterial.new();post.shader=load("res://shaders/mobile_grade.gdshader" if G.mobile else "res://shaders/grade.gdshader");screen.material=post;grading.add_child(screen)
	if "--raw" in OS.get_cmdline_user_args():grading.visible=false
	process_physics_priority=30

func _unhandled_input(e:InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:mouse_delta+=e.relative

func shake(amount:float) -> void:
	if G.settings.shake:trauma=minf(1,trauma+amount)

func landing(weight:float) -> void:
	if G.settings.shake:landing_velocity-=weight*.40

func hit_recoil(direction:Vector3,weight:float) -> void:
	if not G.settings.shake:return
	impact_velocity+=direction.normalized()*clampf(weight,0,1)*1.6
	shake(.12*weight)

func _physics_process(dt:float) -> void:
	clock+=dt;trauma=maxf(0,trauma-dt*1.8)
	landing_velocity+=(-landing_spring*180-landing_velocity*19)*dt
	landing_spring+=landing_velocity*dt
	impact_velocity+=(-impact_offset*185-impact_velocity*24)*dt
	impact_offset+=impact_velocity*dt
	impact_offset=impact_offset.limit_length(.09)
	if cinematic:
		cam.global_position=cam.global_position.lerp(cine_position,1-exp(-4*dt))
		if cam.global_position.distance_to(cine_target)>.1:cam.look_at(cine_target)
		mouse_delta=Vector2.ZERO;return
	if not G.player:return
	var p:Vector3=G.player.global_position+Vector3.UP*1.27
	if pivot==Vector3.ZERO:pivot=p
	pivot.x=lerpf(pivot.x,p.x,1-exp(-12*dt));pivot.z=lerpf(pivot.z,p.z,1-exp(-12*dt));pivot.y=lerpf(pivot.y,p.y,1-exp(-6*dt))
	var look:=pivot+Vector3(-sin(yaw),0,-cos(yaw))*1.2
	var pad:=Input.get_vector("cam_left","cam_right","cam_up","cam_down")
	var zoom:=5.0
	if G.player.target:
		var bp:Vector3=G.player.target.lock_point()
		var to:=bp-pivot
		var desired:=atan2(-to.x,-to.z)
		if Vector2(to.x,to.z).length()>1:yaw=lerp_angle(yaw,desired,1-exp(-8*dt))
		look=(pivot+Vector3.UP*.13).lerp(bp+Vector3.UP*.10,.34)
		pitch=lerpf(pitch,clampf(.19-to.y*.025,.06,.27),1-exp(-4*dt))
		zoom+=smoothstep(5.5,2.0,to.length())*.30+clampf(to.y-2,0,2)*.15
	else:
		yaw-=mouse_delta.x*.0022*float(G.settings.sensitivity)+pad.x*dt*2.3
		pitch+=mouse_delta.y*.0022*float(G.settings.sensitivity)+pad.y*dt*1.7
		pitch=clampf(pitch,-.65,1.05)
		look=pivot+Vector3(-sin(yaw),0,-cos(yaw))*1.1
	mouse_delta=Vector2.ZERO
	smoothed_zoom=lerpf(smoothed_zoom,zoom,1-exp(-4*dt))
	cam.fov=lerpf(cam.fov,61.0 if G.player.sprinting else 59.0,1-exp(-4*dt))
	var offset:=Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*smoothed_zoom
	var shoulder:=Vector3(cos(yaw),0,-sin(yaw))*.28
	var desired:=pivot+offset+shoulder
	var arm:Vector3=desired-pivot
	var arm_length:=arm.length()
	for side in [Vector3.ZERO,Vector3.UP*.16,Vector3.RIGHT*.16,Vector3.LEFT*.16]:
		var query:=PhysicsRayQueryParameters3D.create(pivot+side,desired+side,1)
		var hit:=get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():arm_length=minf(arm_length,pivot.distance_to(hit.position)-.24)
	desired=pivot+arm.normalized()*maxf(.35,arm_length)+Vector3.UP*landing_spring
	cam.global_position=desired+impact_offset
	if trauma>.01:
		var amount:=trauma*trauma*.10;cam.global_position+=Vector3(sin(clock*85),cos(clock*103),0)*amount
	cam.look_at(look)

func reset() -> void:
	yaw=0;pitch=.19;pivot=Vector3.ZERO;trauma=0;mouse_delta=Vector2.ZERO;landing_spring=0;landing_velocity=0;smoothed_zoom=5.0
	impact_offset=Vector3.ZERO;impact_velocity=Vector3.ZERO
