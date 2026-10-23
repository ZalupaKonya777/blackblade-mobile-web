extends Node
## A real-engine boss rehearsal; no poses or damage are simulated outside the game.
var main:Node
var elapsed:=0.0
var events:={}
var last_report:=-1
var stop_move:=0.0
var shots:Array=[]

func _ready() -> void:
	main=get_parent()
	# Configure the software capture before its first rendered frame.
	get_viewport().msaa_3d=Viewport.MSAA_DISABLED
	main.arena.moon.shadow_enabled=false
	for light in main.arena.lights:light.visible=false
func event(id:String,at:float) -> bool:
	if elapsed>=at and not events.has(id):events[id]=true;return true
	return false
func dodge(direction:Vector3) -> void:
	var yaw:float=main.camera.yaw
	var forward:=Vector3(-sin(yaw),0,-cos(yaw));var right:=Vector3(cos(yaw),0,-sin(yaw))
	main.player.bot_move=Vector2(direction.dot(right),direction.dot(forward))
	main.player._queue("dodge");stop_move=elapsed+.10
func setup(gap:float,rage:=false) -> void:
	main.start(true,true);main.boss.ai_enabled=false
	main.player.reset(Vector3(0,.05,2.8));main.player.target=main.boss;main.player.controls_enabled=true
	main.boss.reset(Vector3(0,.05,2.8-gap));main.boss.state="idle";main.boss.phase=2 if rage else 1
	main.arena.rage(rage);main.camera.reset();main.camera.cinematic=false
	main.ui.help_root.visible=false
	main.ui.banner_timer=0
func _physics_process(dt:float) -> void:
	elapsed+=dt
	if int(elapsed)!=last_report:last_report=int(elapsed);print("BEAST REEL ",last_report)
	if stop_move>0 and elapsed>=stop_move:main.player.bot_move=Vector2.ZERO;stop_move=0
	if event("start",.10):
		setup(4.0)
		main.camera.cinematic=true;main.ui.visible=false
	if elapsed<1.6:
		var center:Vector3=main.boss.global_position
		main.camera.cam.fov=46;main.camera.cine_position=center+Vector3(4.5,2.35,5.3);main.camera.cine_target=center+Vector3(0,1.35,.45)
		main.camera.cam.global_position=main.camera.cine_position;main.camera.cam.look_at(main.camera.cine_target)
	if event("combat",1.6):main.ui.visible=true;main.camera.cinematic=false;main.camera.reset()
	if event("combo",1.9):main.boss.start_move("combo")
	if event("dodge1",2.45):dodge(Vector3(.8,0,-.6))
	if event("dodge2",3.20):dodge(Vector3(-.7,0,-.7))
	if event("dodge3",3.95):dodge(Vector3(.9,0,.4))
	if event("punish",4.85):main.player._queue("light")
	if event("overhead_setup",5.4):setup(3.4)
	if event("overhead",5.65):main.boss.start_move("overhead")
	if event("overhead_roll",6.58):dodge(Vector3(.8,0,-.6))
	if event("reply",7.18):main.player._queue("heavy")
	if event("leap_setup",8.4):setup(9.0,true)
	if event("leap",8.6):main.boss.start_move("leap")
	if event("leap_roll",9.93):dodge(Vector3(1,0,0))
	if event("wave_roll",10.70):dodge(Vector3(-1,0,0))
	if event("air_setup",12.0):setup(10.0,true)
	if event("air",12.15):main.boss.start_move("air_blades")
	for i in 3:
		if event("blade_roll%d"%i,13.02+i*.74):dodge(Vector3(1 if i%2==0 else -1,0,0))
	if event("storm_setup",15.75):setup(4.3,true)
	if event("storm",15.95):main.boss.start_move("death_storm")
	if event("storm_roll",17.5):dodge(Vector3(.4,0,1).normalized())
	if event("storm_exit",18.3):dodge(Vector3(0,0,1))
	if elapsed>20.2:get_tree().quit()
