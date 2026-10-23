extends Node
## Recorded through the real command buffer. Training only keeps rehearsals repeatable.
var main:Node
var elapsed:=0.0
var events:={}
var report:=-1
var stop_move:=0.0
func _ready() -> void:
	main=get_parent();get_viewport().msaa_3d=Viewport.MSAA_DISABLED
	main.arena.moon.shadow_enabled=false
	for light in main.arena.lights:light.visible=false
func event(id:String,at:float) -> bool:
	if elapsed>=at and not events.has(id):events[id]=true;return true
	return false
func solo() -> void:
	main.start(true,true);main.boss.ai_enabled=false;main.boss.visible=false;main.boss.global_position=Vector3(-12,.05,-12)
	main.player.reset(Vector3(0,.05,0));main.player.yaw=0;main.player.bot_move=Vector2.ZERO;main.player.target=null
	main.camera.cinematic=true;main.ui.visible=false
func fight(gap:float) -> void:
	main.start(true,true);main.boss.ai_enabled=false;main.boss.visible=true;main.boss.reset(Vector3(0,.05,2.8-gap));main.boss.state="idle"
	main.player.reset(Vector3(0,.05,2.8));main.player.target=main.boss;main.player.bot_move=Vector2.ZERO
	main.camera.reset();main.camera.cinematic=false;main.ui.visible=true;main.ui.banner_timer=0;main.ui.help_root.visible=false
func dodge(direction:Vector3) -> void:
	var yaw:float=main.camera.yaw
	var forward:=Vector3(-sin(yaw),0,-cos(yaw));var right:=Vector3(cos(yaw),0,-sin(yaw))
	main.player.bot_move=Vector2(direction.dot(right),direction.dot(forward));main.player._queue("dodge");stop_move=elapsed+.10
func _physics_process(dt:float) -> void:
	elapsed+=dt
	if int(elapsed)!=report:report=int(elapsed);print("WEIGHT REEL ",report)
	if stop_move>0 and elapsed>=stop_move:main.player.bot_move=Vector2.ZERO;stop_move=0
	if event("start",.10):solo()
	if elapsed<6.35:
		var pos:Vector3=main.player.global_position
		main.camera.cine_position=pos+Vector3(3.0,1.5,3.1);main.camera.cine_target=pos+Vector3(0,1.12,.10)
		main.camera.cam.fov=46;main.camera.cam.global_position=main.camera.cine_position;main.camera.cam.look_at(main.camera.cine_target)
	if event("light1",.50):main.player._queue("light")
	if event("light2",1.00):main.player._queue("light")
	if event("light3",1.73):main.player._queue("light")
	if event("heavy_setup",3.60):solo()
	if event("charge",3.80):main.player.heavy_held=true;main.player._queue("heavy")
	if event("release",5.00):main.player.heavy_held=false
	if event("combat",6.40):fight(3.4)
	if event("overhead",6.80):main.boss.start_move("overhead")
	if event("dodge",7.72):dodge(Vector3(.8,0,-.6))
	if event("punish",8.50):main.player._queue("heavy")
	if event("guard_setup",11.20):fight(2.65)
	if event("sweep",11.50):main.boss.start_move("sweep")
	if event("guard",11.80):Input.action_press("guard")
	if event("guard_release",12.43):Input.action_release("guard")
	if event("counter",12.50):main.player._queue("heavy")
	if event("counter_roll",13.50):dodge(Vector3(1,0,0))
	if elapsed>15.2:Input.action_release("guard");get_tree().quit()
