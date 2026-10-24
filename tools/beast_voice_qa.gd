extends Node3D
class Target:
	extends Node3D
	var state:="idle"
	func alive() -> bool:return true
class AudioSpy:
	extends Node
	var calls:=[]
	func play(name:String,pos:Vector3,db:float=-6,pitch:float=1) -> void:calls.append({"name":name,"position":pos,"db":db,"pitch":pitch})
	func count(name:String) -> int:return calls.filter(func(item:Dictionary) -> bool:return item.name==name).size()
var checks:=[]
func check(label:String,ok:bool,detail:Variant=null) -> void:
	checks.append({"label":label,"ok":ok,"detail":detail});print("BEAST VOICE ","PASS " if ok else "FAIL ",label," ",detail)
func _ready() -> void:run.call_deferred()
func run() -> void:
	G.training=false;G.playing=true;G.settings.shake=false
	var target:=Target.new();add_child(target);target.position=Vector3(0,.05,4);G.player=target
	var spy:=AudioSpy.new();add_child(spy);G.audio=spy
	var beast:=EclipseBeast.new();add_child(beast);beast.set_physics_process(false);beast.position.y=.05;beast.state="idle";beast.ai_enabled=false
	beast._voice_tick(.016)
	check("beast announces its presence once",spy.count("beast_growl")==1)
	beast.voice_clock=5;beast.voice_until=0;beast.breath_at=0;beast.growl_at=100;beast._voice_tick(.016)
	check("idle breathing is a separate vocal event",spy.count("beast_breath")==1)
	beast.voice_clock=10;beast.voice_until=0;beast.growl_at=0;beast._voice_tick(.016)
	check("nearby beast growls between attacks",spy.count("beast_growl")==2)
	beast.voice_clock=15;beast.voice_until=0;beast.start_move("sweep");beast.t=.52
	beast._attack_events(beast.rig.blade());beast.t=.54;beast._attack_events(beast.rig.blade())
	check("a sword release emits one grunt",spy.count("beast_attack")==1,spy.count("beast_attack"))
	beast.voice_clock=18;beast.voice_until=0;beast.start_move("air_blades");beast.t=.90
	beast._attack_events(beast.rig.blade())
	check("air blade launch has vocal effort",spy.count("beast_attack")>=2)
	beast.voice_clock=22;beast.voice_until=0;beast.state="idle";beast.hp=beast.MAX_HP;beast.pain_at=0
	beast.take_damage(100,0,Vector3.UP,"light");beast.take_damage(100,0,Vector3.UP,"light")
	check("hurt reactions have a cooldown",spy.count("beast_pain")==1,spy.count("beast_pain"))
	beast.voice_clock=25;beast.voice_until=0;beast.state="intro";beast.t=.44;beast.events.clear();beast.set_physics_process(true)
	await get_tree().physics_frame;await get_tree().physics_frame;beast.set_physics_process(false)
	check("intro roar follows the intro timeline",spy.count("beast_roar")==1,spy.count("beast_roar"))
	beast.voice_clock=30;beast.voice_until=0;beast.state="transition";beast.t=1.09;beast.events.clear();beast.set_physics_process(true)
	await get_tree().physics_frame;await get_tree().physics_frame;beast.set_physics_process(false)
	check("phase ignition has a stronger roar",spy.count("beast_roar")==2,spy.count("beast_roar"))
	beast.voice_clock=35;beast.voice_until=0;beast.state="idle";beast.hp=1
	beast.take_damage(100,0,Vector3.UP,"heavy")
	check("death vocal is emitted once",spy.count("beast_death")==1 and beast.state=="dead")
	var count:=spy.calls.size();G.playing=false;beast.state="idle";beast.voice_until=0;beast.breath_at=0;beast._voice_tick(10)
	check("no autonomous vocals on the title screen",spy.calls.size()==count)
	beast.reset(Vector3(0,.05,0))
	check("retry resets vocal timing",not beast.voice_awakened and beast.voice_clock==0 and beast.voice_until==0)
	var audio=load("res://scripts/audio.gd").new();add_child(audio)
	audio.play("beast_roar",Vector3.ZERO);var first:int=audio.voice_index
	audio.play("beast_breath",Vector3.ZERO);audio.play("beast_pain",Vector3.ZERO)
	check("native roar cannot be interrupted by breath or pain",audio.voice_event=="beast_roar" and audio.voice_index==first)
	audio.play("beast_death",Vector3.ZERO);audio.fight(false)
	check("death overrides roar and survives the victory music transition",audio.voice_event=="beast_death" and audio.voice_remaining>0)
	audio.fight(true)
	check("new attempt clears the old vocal",audio.voice_event=="" and audio.voice_remaining==0)
	audio.play("beast_attack",Vector3.ZERO);var slot:int=audio.voice_index;audio.play("beast_attack",Vector3.ZERO)
	check("native vocal cooldown suppresses duplicate cues",audio.voice_index==slot)
	check("native bank loads all creature variants",audio.streams.size()==82 and audio.bank.events.has("beast_death"),audio.streams.size())
	var failures:=checks.filter(func(item:Dictionary) -> bool:return not item.ok).size()
	var file:=FileAccess.open("res://artifacts/beast_voice_verification.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures}));file.close()
	get_tree().quit(1 if failures else 0)
