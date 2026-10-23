extends Node
## An engine-recorded rehearsal: uses the real command buffer and combat states.
var main:Node
var elapsed:=0.0
var events:={}
var release_move_at:=0.0
var report_second:=-1

func _ready() -> void:main=get_parent()

func event(id:String,at:float) -> bool:
	if elapsed>=at and not events.has(id):events[id]=true;return true
	return false

func dodge(direction:Vector3) -> void:
	var yaw:float=main.camera.yaw
	var forward:=Vector3(-sin(yaw),0,-cos(yaw));var right:=Vector3(cos(yaw),0,-sin(yaw))
	main.player.bot_move=Vector2(direction.dot(right),direction.dot(forward))
	main.player._queue("dodge");release_move_at=elapsed+.12

func _physics_process(dt:float) -> void:
	elapsed+=dt
	if int(elapsed)/2!=report_second:
		report_second=int(elapsed)/2;print("POLISH REEL ",elapsed," seconds")
	if release_move_at>0 and elapsed>=release_move_at:main.player.bot_move=Vector2.ZERO;release_move_at=0
	if event("start",.10):
		main.start(true,true);main.boss.ai_enabled=false;main.boss.visible=false
		# Keep the full material/lighting pass; two coverage samples are sufficient
		# for the server's offline 768p-wide review recording.
		get_viewport().msaa_3d=Viewport.MSAA_2X
		main.player.bot_move=Vector2.ZERO;main.player.reset(Vector3(0,.05,0));main.player.target=null;main.player.yaw=PI
		main.boss.global_position=Vector3(-12,.05,-12);main.camera.cinematic=true;main.ui.visible=false
	if elapsed<4.65:
		var pos:Vector3=main.player.global_position
		main.camera.cam.fov=48
		main.camera.cine_position=pos+Vector3(3.0,1.45,1.85);main.camera.cine_target=pos+Vector3.UP*.82
		main.camera.cam.global_position=main.camera.cine_position;main.camera.cam.look_at(main.camera.cine_target)
	if event("forward_roll",.70):dodge(Vector3(0,0,-1))
	if event("side_roll",1.85):dodge(Vector3(-1,0,0))
	if event("diagonal_roll",3.0):dodge(Vector3(.65,0,-.76).normalized())
	if event("roll_attack",3.60):main.player._queue("light")
	if event("fight",4.80):
		main.ui.visible=true;main.player.reset(Vector3(0,.05,3));main.boss.reset(Vector3(0,.05,-6));main.boss.ai_enabled=false;main.boss.visible=true;main.boss.state="idle"
		main.player.target=main.boss;main.camera.reset();main.camera.cinematic=false
	if event("lunge",5.25):main.boss.start_move("lunge")
	if event("dodge_lunge",5.88):dodge(Vector3(1,0,-.18).normalized())
	if event("overhead",7.10):main.boss.start_move("overhead")
	if event("dodge_overhead",8.02):dodge(G.flat(main.boss.global_position-main.player.global_position).normalized())
	if event("reply",8.66):main.player._queue("light")
	if event("phase",9.50):
		main.player.reset(Vector3(0,.05,2));main.boss.reset(Vector3(0,.05,-5));main.boss.state="idle";main.boss.ai_enabled=false;main.boss.phase=2
		main.player.target=main.boss;main.arena.rage(true)
	if event("leap",10.05):main.boss.start_move("leap")
	if event("dodge_leap",11.40):dodge(Vector3(1,0,.08).normalized())
	if event("air",12.95):
		main.player.reset(Vector3(0,.05,3));main.player.target=main.boss
		main.boss.global_position=Vector3(0,.05,-7);main.boss.start_move("air_blades")
	for i in 3:
		if event("air_dodge%d"%i,14.10+float(i)*.73):dodge(Vector3(1 if i%2==0 else -1,0,.04).normalized())
	if elapsed>17.3:get_tree().quit()
