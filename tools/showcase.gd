extends Node
var main:Node
var elapsed:=0.0
var events:={}
func _ready() -> void:
	main=get_parent()
func event(id:String,time:float) -> bool:
	if elapsed>=time and not events.has(id):events[id]=true;return true
	return false
func _physics_process(dt:float) -> void:
	elapsed+=dt
	if event("start",.10):
		main.start(true,true);main.boss.ai_enabled=false
		main.player.bot_move=Vector2.ZERO
		main.player.reset(Vector3(0,.05,0));main.player.target=null;main.player.yaw=PI
		main.boss.global_position=Vector3(-7,.05,-8)
		main.camera.cinematic=true
	if elapsed<4.5:
		var pos:Vector3=main.player.global_position
		main.camera.cine_position=pos+Vector3(4.0,2.1,4.0)
		main.camera.cine_target=pos+Vector3.UP*.95
	if event("roll",.65):
		main.player.move_dir=Vector3(0,0,-1);main.player._command("dodge")
	if event("attack",1.70):main.player._attack("light")
	if event("attack2",2.05):main.player._queue("light")
	if event("attack3",2.52):main.player._queue("light")
	if event("heavy",3.25):main.player._attack("heavy")
	if event("fight",4.60):
		main.player.reset(Vector3(0,.05,2));main.boss.reset(Vector3(0,.05,-7));main.boss.ai_enabled=false;main.boss.state="idle";main.boss.phase=2
		main.player.target=main.boss;main.camera.reset();main.camera.cinematic=false
	if event("lunge",5.1):main.boss.start_move("lunge")
	if event("evade",5.76):
		main.player.move_dir=Vector3(1,0,-.2).normalized();main.player._command("dodge")
	if event("jumpreset",7.30):
		main.player.reset(Vector3(0,.05,2));main.player.target=main.boss
		main.boss.global_position=Vector3(0,.05,-7);main.boss.phase=2;main.boss.start_move("leap")
	if event("evade2",8.70):
		main.player.move_dir=Vector3(1,0,-.2).normalized();main.player._command("dodge")
	if event("airreset",10.6):
		main.player.reset(Vector3(0,.05,3));main.player.target=main.boss
		main.boss.global_position=Vector3(0,.05,-7);main.boss.phase=2;main.boss.start_move("air_blades")
	for i in 3:
		if event("dodgeair%d"%i,11.65+i*.70):
			main.player.move_dir=Vector3(1 if i%2==0 else -1,0,0);main.player._command("dodge")
	if elapsed>15.3:get_tree().quit()
