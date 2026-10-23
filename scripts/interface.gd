extends CanvasLayer

const GOLD:=Color(.73,.64,.45)
const PAPER:=Color(.85,.86,.83)
const MUTED:=Color(.45,.52,.60)
var title_font:Font=preload("res://assets/fonts/Cormorant.ttf")
var ui_font:Font=preload("res://assets/fonts/Inter.ttf")
var canvas:Control
var title_root:Control
var pause_root:Control
var help_root:Control
var result_root:Control
var clock:=0.0
var mode:="title"
var hp_lag:=1.0
var boss_lag:=1.0
var banner:=""
var banner_sub:=""
var banner_timer:=0.0
var numbers:Array=[]
var help_visible:=false
var fade:=0.0
var result_time:=0.0
var result_win:=false
var title_buttons:Array=[]
var return_to_title:=false
var status:Label

class Painter extends Control:
	var owner_ui:CanvasLayer
	func _draw() -> void:owner_ui.paint(self)

func _ready() -> void:
	G.ui=self;layer=20;process_mode=Node.PROCESS_MODE_ALWAYS
	canvas=Painter.new();canvas.owner_ui=self;canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(canvas)
	_title();_pause_panel();_help_panel();_result_panel()

func _label(parent:Node,text:String,pos:Vector2,size:Vector2,font_size:int=22,color:Color=PAPER,serif:=false) -> Label:
	var l:=Label.new();l.text=text;l.position=pos;l.size=size;l.add_theme_font_override("font",title_font if serif else ui_font);l.add_theme_font_size_override("font_size",font_size);l.add_theme_color_override("font_color",color);parent.add_child(l);return l

func _button(parent:Node,text:String,pos:Vector2,width:float,cb:Callable,small:=false) -> Button:
	var b:=Button.new();b.text="   "+text;b.position=pos;b.size=Vector2(width,48 if small else 55);b.alignment=HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font",title_font);b.add_theme_font_size_override("font_size",26 if small else 30)
	b.add_theme_color_override("font_color",PAPER);b.add_theme_color_override("font_hover_color",Color(1,.86,.58));b.add_theme_color_override("font_focus_color",Color(1,.86,.58))
	var normal:=StyleBoxFlat.new();normal.bg_color=Color(.025,.04,.06,.08);normal.border_color=Color(GOLD,.18);normal.border_width_bottom=1
	var hover:=StyleBoxFlat.new();hover.bg_color=Color(.19,.23,.27,.44);hover.border_color=GOLD;hover.border_width_left=2
	b.add_theme_stylebox_override("normal",normal);b.add_theme_stylebox_override("hover",hover);b.add_theme_stylebox_override("focus",hover);b.add_theme_stylebox_override("pressed",hover)
	b.pressed.connect(func():if G.audio:G.audio.play("menu",G.camera.cam.global_position,-13)
	)
	b.pressed.connect(cb);parent.add_child(b);return b

func _title() -> void:
	title_root=Control.new();title_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(title_root)
	_label(title_root,"Х Р А М   З А Т М Е Н И Я",Vector2(112,178),Vector2(650,35),17,GOLD)
	_label(title_root,"BLACKBLADE",Vector2(104,218),Vector2(800,125),98,Color(.83,.78,.65),true)
	_label(title_root,"Зверь забытого храма",Vector2(111,337),Vector2(650,45),35,PAPER,true)
	_label(title_root,"Сломи его стойку. Переживи Чёрный Клинок.",Vector2(113,408),Vector2(650,30),17,Color(.56,.62,.69))
	title_buttons.append(_button(title_root,"Вступить в бой",Vector2(109,480),370,func():G.main.start(false)))
	title_buttons.append(_button(title_root,"Тренировка",Vector2(109,541),370,func():G.main.start(true)))
	title_buttons.append(_button(title_root,"Управление",Vector2(109,602),370,func():show_help()))
	title_buttons.append(_button(title_root,"Настройки",Vector2(109,663),370,func():open_pause(true)))
	_label(title_root,"SOULSLIKE  /  BOSS ENCOUNTER",Vector2(112,825),Vector2(800,26),12,MUTED)
	_label(title_root,"ENTER   Начать      ·      F11   Полный экран",Vector2(1080,829),Vector2(460,25),12,Color(.58,.62,.66))
	status=_label(title_root,"",Vector2(113,741),Vector2(700,28),14,MUTED)
	status.text="ПК и геймпад  ·  средний вес снаряжения"

func _panel(size:Vector2) -> Panel:
	var p:=Panel.new();p.position=(Vector2(1600,900)-size)*.5;p.size=size
	var sb:=StyleBoxFlat.new();sb.bg_color=Color(.027,.042,.060,.98);sb.border_color=Color(GOLD,.55);sb.set_border_width_all(1);sb.shadow_color=Color(0,0,0,.6);sb.shadow_size=35
	p.add_theme_stylebox_override("panel",sb);return p

func _pause_panel() -> void:
	pause_root=Control.new();pause_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(pause_root)
	var bg:=ColorRect.new();bg.color=Color(.005,.01,.02,.66);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);pause_root.add_child(bg)
	var p:=_panel(Vector2(620,710));pause_root.add_child(p)
	_label(p,"Пауза у границы тьмы",Vector2(40,26),Vector2(540,55),42,GOLD,true)
	_button(p,"Продолжить",Vector2(35,100),550,close_pause,true)
	_label(p,"Вес снаряжения",Vector2(49,175),Vector2(280,30),17)
	var load_opt:=OptionButton.new();load_opt.position=Vector2(325,173);load_opt.size=Vector2(240,35);load_opt.add_theme_font_override("font",ui_font);load_opt.add_theme_font_size_override("font_size",16)
	for n in ["Лёгкий · дальний перекат","Средний · обычный","Тяжёлый · долгий откат"]:load_opt.add_item(n)
	load_opt.selected=int(G.settings.load);load_opt.item_selected.connect(func(i):G.settings.load=i;G.save());p.add_child(load_opt)
	_label(p,"Графика",Vector2(49,225),Vector2(220,30),17)
	var quality:=OptionButton.new();quality.position=Vector2(325,222);quality.size=Vector2(240,32)
	for q in ["Низкая","Высокая"]:quality.add_item(q)
	quality.selected=int(G.settings.get("quality",1));quality.item_selected.connect(func(v):G.settings.quality=v;G.save());p.add_child(quality)
	_slider(p,"Чувствительность",285,"sensitivity",.25,2.5)
	_slider(p,"Громкость",340,"volume",0,1)
	_slider(p,"Музыка",395,"music",0,1)
	var shake:=CheckButton.new();shake.text="Тряска камеры";shake.position=Vector2(48,435);shake.size=Vector2(510,35);shake.button_pressed=G.settings.shake;shake.add_theme_font_override("font",ui_font);shake.add_theme_font_size_override("font_size",17);shake.toggled.connect(func(v):G.settings.shake=v;G.save());p.add_child(shake)
	_button(p,"Начать заново",Vector2(35,495),550,func():close_pause();G.main.start(G.training,true),true)
	_button(p,"В главное меню",Vector2(35,550),550,func():close_pause();G.main.to_title(),true)
	_button(p,"Выйти из игры",Vector2(35,605),550,func():get_tree().quit(),true)
	pause_root.visible=false

func _slider(parent:Control,text:String,y:float,key:String,lo:float,hi:float) -> void:
	_label(parent,text,Vector2(49,y),Vector2(270,30),17)
	var s:=HSlider.new();s.position=Vector2(325,y+6);s.size=Vector2(235,24);s.min_value=lo;s.max_value=hi;s.step=.05;s.value=G.settings[key];s.value_changed.connect(func(v):G.settings[key]=v;G.save());parent.add_child(s)

func _help_panel() -> void:
	help_root=Control.new();help_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(help_root)
	var bg:=ColorRect.new();bg.color=Color(.005,.012,.025,.85);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);help_root.add_child(bg)
	var p:=_panel(Vector2(1040,730));help_root.add_child(p)
	_label(p,"Искусство выживания",Vector2(46,24),Vector2(900,55),46,GOLD,true)
	_label(p,"УКЛОНЕНИЕ",Vector2(49,112),Vector2(300,30),14,GOLD)
	var rows:=[
		["W A S D / левый стик","Двигаться"],
		["Пробел / B","Отпустить — перекат; удерживать — спринт"],
		["Пробел без направления","Отскок назад без неуязвимости"],
		["Q / СКМ / R3","Захват цели; повторно — свободная камера"],
		["F / A","Прыжок: позволяет избежать низких ударов"],
		["ЛКМ / RB","Быстрый удар; повторные нажатия — серия"],
		["ПКМ / RT","Сильный удар; удерживать — зарядить"],
		["Ctrl / LB","Блок; ПКМ после блока — контрудар"],
		["C / LT","Отразить золотую вспышку клинка босса"],
		["R / X","Выпить флягу · 5 зарядов на попытку"],
		["Esc / Start","Пауза и настройки"],
		["F1 / Back","Эта памятка"]]
	for i in rows.size():
		var y:=155+i*34
		_label(p,rows[i][0],Vector2(49,y),Vector2(320,28),16,Color(.76,.75,.68))
		_label(p,rows[i][1],Vector2(365,y),Vector2(630,28),16,PAPER)
	_label(p,"Не спеши: перекатывайся в удар и атакуй после конца серии.\nЗаряд тратит больше стамины. Тяжёлые удары ломают стойку. Подойди спереди и нажми ЛКМ для критического удара.",Vector2(49,579),Vector2(940,64),17,MUTED)
	_button(p,"Вернуться",Vector2(35,660),970,hide_help,true)
	help_root.visible=false

func _result_panel() -> void:
	result_root=Control.new();result_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(result_root)
	_button(result_root,"Ещё одна попытка",Vector2(590,570),420,func():G.main.start(G.training,true))
	_button(result_root,"Главное меню",Vector2(590,636),420,func():G.main.to_title())
	result_root.visible=false

func show_title() -> void:
	mode="title";title_root.show();result_root.hide();banner_timer=0;hp_lag=1;boss_lag=1
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func begin() -> void:
	mode="game";title_root.hide();result_root.hide();pause_root.hide();help_root.hide();hp_lag=1;boss_lag=1;banner_timer=0;fade=0

func result(win:bool) -> void:
	mode="result";result_time=0;result_win=win
	result_root.hide();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func open_pause(from_title:=false) -> void:
	return_to_title=from_title;pause_root.show();get_tree().paused=true;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if not OS.has_feature("web"):pause_root.find_children("*","Button",true,false)[0].grab_focus()

func close_pause() -> void:
	pause_root.hide();get_tree().paused=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if G.mobile or mode!="game" else Input.MOUSE_MODE_CAPTURED

func show_help() -> void:
	help_root.show();get_tree().paused=true;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func hide_help() -> void:
	help_root.hide();get_tree().paused=false;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if G.mobile or mode!="game" else Input.MOUSE_MODE_CAPTURED

func notify(text:String,sub:String="") -> void:
	banner=text;banner_sub=sub;banner_timer=3.0

func damage_number(amount:float,at:Vector3) -> void:
	numbers.append({"amount":roundi(amount),"at":at,"age":0.0})

func _input(e:InputEvent) -> void:
	if e.is_action_pressed("fullscreen"):
		var fs:=DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED)
	if e.is_action_pressed("help"):
		if help_root.visible:hide_help()
		else:show_help()
		get_viewport().set_input_as_handled()
	if e.is_action_pressed("pause"):
		if help_root.visible:hide_help()
		elif pause_root.visible:close_pause()
		else:open_pause(mode=="title")
		get_viewport().set_input_as_handled()
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode==KEY_ENTER:
		if help_root.visible or pause_root.visible:return
		if mode=="title":
			G.main.start(false);get_viewport().set_input_as_handled()
		elif mode=="result" and result_time>1.5:
			G.main.start(G.training,true);get_viewport().set_input_as_handled()

func _process(dt:float) -> void:
	clock+=dt
	if not get_tree().paused:
		banner_timer=maxf(0,banner_timer-dt)
		if G.player:hp_lag=move_toward(hp_lag,G.player.hp/PlayerUnit.MAX_HP,dt*.22)
		if G.boss:boss_lag=move_toward(boss_lag,G.boss.hp/EclipseBeast.MAX_HP,dt*.12)
		for i in range(numbers.size()-1,-1,-1):
			numbers[i].age+=dt
			if numbers[i].age>1.1:numbers.remove_at(i)
	if mode=="result":
		result_time+=dt;result_root.visible=result_time>2.0
	canvas.queue_redraw()

func _text(c:Control,text:String,pos:Vector2,size:int=18,color:Color=PAPER,serif:=false) -> void:
	c.draw_string(title_font if serif else ui_font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func _center(c:Control,text:String,pos:Vector2,size:int=18,color:Color=PAPER,serif:=false) -> void:
	var f:=title_font if serif else ui_font
	var w:=f.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	c.draw_string(f,pos-Vector2(w*.5,0),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func _sigil(c:Control,pos:Vector2,r:float,color:Color) -> void:
	c.draw_arc(pos,r,0,TAU,64,Color(color,.45),1,true)
	var points:=PackedVector2Array()
	for i in 16:
		var a:=i*TAU/16-PI*.5;var v:=r*.91 if i%4==0 else (r*.51 if i%2==0 else r*.12)
		points.append(pos+Vector2(cos(a),sin(a))*v)
	c.draw_colored_polygon(points,color)
	c.draw_circle(pos,r*.11,Color(.045,.065,.09))

func _bar(c:Control,pos:Vector2,width:float,height:float,frac:float,lag:float,color:Color) -> void:
	c.draw_rect(Rect2(pos-Vector2(2,2),Vector2(width+4,height+4)),Color(.014,.017,.022,.94))
	c.draw_rect(Rect2(pos-Vector2(2,2),Vector2(width+4,height+4)),Color(GOLD,.55),false,1)
	c.draw_rect(Rect2(pos,Vector2(width*clampf(lag,0,1),height)),Color(.64,.49,.19,.85))
	c.draw_rect(Rect2(pos,Vector2(width*clampf(frac,0,1),height)),color)
	c.draw_line(pos, pos+Vector2(width*clampf(frac,0,1),0),color.lightened(.22),1)

func paint(c:Control) -> void:
	if mode=="title":
		for i in 100:
			var x:=float(i)*11;var a:=.87*pow(1-float(i)/100,1.8)
			c.draw_rect(Rect2(x,0,11,900),Color(.007,.015,.026,a))
		c.draw_rect(Rect2(0,0,1600,96),Color(.005,.012,.02,.28))
		_sigil(c,Vector2(146,117),34,GOLD)
		c.draw_line(Vector2(197,117),Vector2(420,117),Color(GOLD,.35),1)
		c.draw_line(Vector2(113,386),Vector2(483,386),Color(GOLD,.46),1)
		return
	if not G.player or not G.boss:return
	var p=G.player;var b=G.boss
	# A thin vignette anchors the bars while leaving the action clear.
	for i in 12:
		c.draw_rect(Rect2(0,i*8,1600,8),Color(.006,.012,.022,.20*(1-float(i)/12)))
	_sigil(c,Vector2(63,67),31,GOLD)
	_bar(c,Vector2(110,42),370,12,p.hp/PlayerUnit.MAX_HP,hp_lag,Color(.48,.075,.075))
	_bar(c,Vector2(110,66),275,9,p.stamina/PlayerUnit.MAX_STAMINA,p.stamina/PlayerUnit.MAX_STAMINA,Color(.23,.40,.25))
	_text(c,"%d / %d"%[ceili(p.hp),PlayerUnit.MAX_HP],Vector2(112,101),13,Color(.62,.65,.67))
	if p.dd_timer>0:_text(c,"КЛЕЙМО СМЕРТИ",Vector2(110,124),12,Color(.82,.26,.23))
	_text(c,"F1  Управление     Esc  Меню",Vector2(1260,43),12,Color(.53,.59,.65))
	if G.training:_center(c,"ТРЕНИРОВКА · E / Y сменить фазу · бесконечные фляги",Vector2(800,40),13,GOLD)
	elif G.elapsed<8:_center(c,"Х Р А М   З А Т М Е Н И Я",Vector2(800,48),15,Color(.68,.72,.76,clampf((8-G.elapsed)*.5,0,1)))
	if b.alive() and G.playing:
		var name:="Астар, зверь затмения" if b.phase==1 else "Астар, Чёрный Клинок"
		_text(c,name,Vector2(267,782),30,PAPER,true)
		_bar(c,Vector2(267,800),1066,13,b.hp/EclipseBeast.MAX_HP,boss_lag,Color(.47,.075,.065))
		_text(c,"I  /  ЗВЕРИНАЯ КЛЯТВА" if b.phase==1 else "II  /  ПРЕДНАЧЕРТАННАЯ СМЕРТЬ",Vector2(269,839),11,Color(.57,.58,.56))
		if G.training:
			_bar(c,Vector2(1122,834),210,3,b.posture/EclipseBeast.STANCE,b.posture/EclipseBeast.STANCE,GOLD)
			_text(c,"СТОЙКА",Vector2(1122,858),10,MUTED)
	# The flask is drawn as an actual small vial, with an item key and remaining charges.
	var at:=Vector2(73,737)
	c.draw_rect(Rect2(at-Vector2(34,44),Vector2(68,83)),Color(.02,.035,.05,.75))
	c.draw_rect(Rect2(at-Vector2(34,44),Vector2(68,83)),Color(GOLD,.40),false,1)
	c.draw_colored_polygon(PackedVector2Array([at+Vector2(-7,-27),at+Vector2(7,-27),at+Vector2(7,-13),at+Vector2(16,3),at+Vector2(11,20),at+Vector2(-11,20),at+Vector2(-16,3),at+Vector2(-7,-13)]),Color(.53,.15,.09))
	c.draw_circle(at+Vector2(0,4),11,Color(.78,.37,.13));c.draw_rect(Rect2(at+Vector2(-9,-30),Vector2(18,5)),GOLD)
	_text(c,"R",Vector2(49,709),13,GOLD);_text(c,"∞" if G.training else str(p.flasks),Vector2(86,770),19,PAPER)
	_text(c,"Багровая фляга",Vector2(40,803),18,Color(.69,.68,.61),true)
	if G.elapsed<16:
		_center(c,"ПРОБЕЛ  Перекат     ЛКМ  Удар     ПКМ  Сильный удар     Q  Цель",Vector2(800,889),12,Color(.58,.64,.71,clampf((16-G.elapsed)*.2,0,1)))
	if p.target and G.camera:
		var wp:Vector3=p.target.lock_point()
		if not G.camera.cam.is_position_behind(wp):
			var sp:Vector2=G.camera.cam.unproject_position(wp)
			c.draw_arc(sp,6,0,TAU,24,Color(.92,.91,.81,.7),1,true);c.draw_circle(sp,2,Color(1,.98,.84))
	for n in numbers:
		if G.camera.cam.is_position_behind(n.at):continue
		var at2:Vector2=G.camera.cam.unproject_position(n.at)-Vector2(0,n.age*32)
		_center(c,str(n.amount),at2,26,Color(.94,.82,.56,1-n.age/1.1),true)
	if banner_timer>0:
		var a:=clampf(banner_timer,0,1)
		_center(c,banner,Vector2(800,169),32,Color(GOLD,a),true)
		_center(c,banner_sub,Vector2(800,202),15,Color(PAPER,a))
	if mode=="result":
		var a:=clampf(result_time-.30,0,1)
		c.draw_rect(Rect2(0,320,1600,217),Color(.005,.008,.015,.73*a))
		_center(c,"ВЕЛИКИЙ ВРАГ ПОВЕРЖЕН" if result_win else "ТЫ ПОГИБ",Vector2(800,425),64,Color(GOLD,a) if result_win else Color(.55,.10,.075,a),true)
		var secs:=int(G.elapsed)
		_center(c,"%02d:%02d   ·   Попаданий: %d   ·   Уклонений: %d"%[secs/60,secs%60,G.stats.hits,G.stats.evades],Vector2(800,489),16,Color(.68,.69,.67,a))
	if fade>0:c.draw_rect(Rect2(0,0,1600,900),Color(0,0,0,fade))
