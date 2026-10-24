extends "res://tools/motion_reel.gd"
const SPECS=[
 {"kind":"knight","id":"run_front","speed":4.0,"dir":Vector3.BACK,"time":.9,"front":true},
 {"kind":"knight","id":"run_side","speed":4.0,"dir":Vector3.BACK,"time":.9,"front":false},
 {"kind":"knight","id":"sprint_front","speed":6.0,"dir":Vector3.BACK,"time":1.1,"front":true},
 {"kind":"boss","id":"charge_front","speed":5.2,"dir":Vector3.BACK,"time":.9,"front":true},
 {"kind":"boss","id":"charge_side","speed":5.2,"dir":Vector3.BACK,"time":.9,"front":false},
 {"kind":"boss","id":"orbit_front","speed":1.55,"dir":Vector3.RIGHT,"time":1.1,"front":true}]
func _ready() -> void:
	set_process(false);run.call_deferred()
func run() -> void:
	G.mobile=true;G.settings.quality=1;_world()
	var suffix:="before" if "--before" in OS.get_cmdline_user_args() else "after"
	for spec in SPECS:
		var actor:=FighterRig.new();add_child(actor);actor.setup(spec.kind);actor.position.y=.05
		if spec.kind=="boss":actor.scale=Vector3.ONE*1.20
		for i in 12:actor.pose("idle",0,DT,0,Vector3.ZERO)
		for frame in int(spec.time*60)+1:
			var time:=frame*DT;var speed:float=spec.speed*smoothstep(0,.26,time)
			actor.position+=spec.dir*speed*DT;actor.pose("move",time,DT,speed,spec.dir)
		var offset:=Vector3(.1,1.25,4.0) if spec.front else Vector3(-3.4,1.25,.1)
		if spec.kind=="boss":offset*=1.55
		camera.position=actor.position+offset;camera.fov=42;camera.look_at(actor.position+Vector3.UP*(1.2 if spec.kind=="boss" else .95))
		label.text="%s / %s / %s"%[suffix.to_upper(),spec.kind.to_upper(),spec.id.to_upper()]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/gait_v9_%s_%s.png"%[suffix,spec.id])
		print("GAIT REVIEW ",suffix," ",spec.id)
		actor.queue_free();await get_tree().process_frame
	get_tree().quit()
