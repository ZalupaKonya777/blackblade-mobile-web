// Browser and gesture coverage. The AudioSession stub tests call ordering only;
// hardware Ring/Silent routing still needs a physical iPhone verification.
import {chromium,webkit} from '../.runtime/qa/node_modules/playwright-core/index.mjs';
import fs from 'node:fs/promises';
const base=process.env.AUDIO_PREVIEW_URL||'http://127.0.0.1:8793/';
const reports=[];
for(const [engine,type,executablePath] of [
 ['chromium',chromium,'/root/.cache/ms-playwright/chromium-1248/chrome-linux64/chrome'],
 ['webkit',webkit,'/root/.cache/ms-playwright/webkit-2370/pw_run.sh']]){
 const browser=await type.launch({headless:true,executablePath,args:engine==='chromium'?['--no-sandbox','--autoplay-policy=user-gesture-required']:[]});
 for(const mode of ['playback-api','media-fallback']){
  const context=await browser.newContext({viewport:{width:844,height:390},isMobile:true,hasTouch:true,serviceWorkers:'block'});
  const page=await context.newPage(),errors=[],checks=[];page.on('pageerror',e=>errors.push(e.message));
  const check=(label,ok,detail)=>{checks.push({label,ok,detail});console.log(engine,mode,ok?'PASS':'FAIL',label,JSON.stringify(detail));if(!ok)throw Error(label);};
  try{
   await page.addInitScript(mode=>{
    window.__soundOrder=[];
    Object.defineProperty(navigator,'standalone',{configurable:true,value:true});
    const session=new EventTarget();let value='auto';
    Object.defineProperty(session,'type',{get(){return value;},set(next){value=next;window.__soundOrder.push('session:'+next);}});
    Object.defineProperty(session,'state',{get(){return 'active';}});
    Object.defineProperty(navigator,'audioSession',{configurable:true,value:mode==='playback-api'?session:undefined});
    const Constructor=window.AudioContext||window.webkitAudioContext;
    const Traced=new Proxy(Constructor,{construct(Target,args){window.__soundOrder.push('context:'+session.type);return Reflect.construct(Target,args);}});
    window.AudioContext=Traced;if(window.webkitAudioContext)window.webkitAudioContext=Traced;
   },mode);
   await page.goto(base+'?qa=1');await page.waitForFunction(()=>window.BlackbladeSound&&window.BlackbladeUI);
   check('audio output stays locked until a gesture',await page.evaluate(()=>BlackbladeSound.context===null));
   check('standalone PWA mode is recognised',await page.evaluate(()=>BlackbladeSound.diagnostics.standalone));
   await page.locator('#home-help-toggle').tap();
   await page.waitForFunction(()=>BlackbladeSound.context?.state==='running');
   if(mode==='playback-api')check('modern playback session uses the direct low latency output',await page.evaluate(()=>BlackbladeSound.outputRoute==='web-audio'&&!BlackbladeSound.mediaOutput),await page.evaluate(()=>BlackbladeSound.diagnostics));
   await page.locator('#home-sound').tap();
   await page.waitForFunction(()=>BlackbladeSound.context?.state==='running'&&BlackbladeSound.diagnostics.rms>.0002);
   const first=await page.evaluate(()=>({audio:BlackbladeSound.diagnostics,order:__soundOrder}));
   check('visible home button starts a real audible graph before the game loads',first.audio.probes===1&&first.audio.warmups>0,first);
   if(mode==='playback-api')check('playback intent is set before AudioContext construction',first.order.indexOf('session:playback')<first.order.indexOf('context:playback'),first.order);
   else {
    await page.waitForFunction(()=>BlackbladeSound.mediaPlaying&&BlackbladeSound.mediaOutput.currentTime>0);
    check('legacy route uses a real playing media source',await page.evaluate(()=>!!BlackbladeSound.mediaDestination),await page.evaluate(()=>BlackbladeSound.diagnostics));
   }
   await page.evaluate(()=>BlackbladeSound.settings(0,.5));await page.waitForTimeout(900);
   check('zero volume silences the whole graph and pauses the media route',await page.evaluate(()=>BlackbladeSound.diagnostics.rms<.00001&&(!BlackbladeSound.mediaOutput||BlackbladeSound.mediaOutput.paused)),await page.evaluate(()=>BlackbladeSound.diagnostics));
   await page.evaluate(()=>{document.getElementById('home').hidden=true;document.getElementById('hud').hidden=false;window.__nativeSoundCommands=[];window.BlackbladeNative=data=>__nativeSoundCommands.push(JSON.parse(data));});
   await page.locator('#sound-enable').tap();
   await page.waitForFunction(()=>BlackbladeSound.volume>0&&BlackbladeSound.diagnostics.rms>.0002);
   check('HUD sound button restores a saved zero level and sends it to the game',await page.evaluate(()=>__nativeSoundCommands.some(c=>c.type==='setting'&&c.key==='volume'&&c.value>0)),await page.evaluate(()=>BlackbladeSound.diagnostics));
   await page.waitForTimeout(1300);
   await page.evaluate(()=>{window.oldSoundOutput=BlackbladeSound.context;document.getElementById('pause-menu').hidden=false;});
   await page.locator('#sound-check').tap();
   await page.waitForFunction(()=>BlackbladeSound.context!==oldSoundOutput&&BlackbladeSound.context.state==='running'&&BlackbladeSound.diagnostics.rms>.0002);
   check('explicit repair rebuilds the output without a page reload',await page.evaluate(()=>BlackbladeSound.rebuilds>0&&document.querySelectorAll('audio[data-game-audio-output]').length===1),await page.evaluate(()=>BlackbladeSound.diagnostics));
   await page.evaluate(()=>window.dispatchEvent(new PageTransitionEvent('pagehide',{persisted:true})));await page.waitForFunction(()=>BlackbladeSound.context.state==='suspended');
   check('standalone pagehide stops media and Web Audio together',await page.evaluate(()=>BlackbladeSound.mediaOutput.paused));
   await page.evaluate(()=>window.dispatchEvent(new PageTransitionEvent('pageshow',{persisted:true})));
   await page.locator('#sound-check').tap();
   await page.waitForFunction(()=>BlackbladeSound.context.state==='running'&&BlackbladeSound.diagnostics.rms>.0002);
   check('returning user gesture restores the signal',true,await page.evaluate(()=>BlackbladeSound.diagnostics));
   await page.setViewportSize({width:667,height:375});
   const size=await page.locator('#sound-enable').boundingBox();
   check('sound control remains a 44px target on small landscape screens',size.width>=44&&size.height>=44&&size.x>=0&&size.x+size.width<=667,size);
   await page.screenshot({path:new URL(`../artifacts/${engine}_${mode}_audio_ui.png`,import.meta.url).pathname});
   check('no JavaScript errors in the actual audio UI',errors.length===0,errors);
  }catch(error){checks.push({label:'case completes',ok:false,detail:String(error)});console.log(engine,mode,'FAIL',String(error));}
  reports.push({engine,mode,checks,errors,note:mode==='playback-api'?'AudioSession ordering uses a stub; this does not emulate iOS hardware routing.':'Actual gain graph -> MediaStream -> HTMLMediaElement output and measured audio samples.'});
  await context.close();
 }
 await browser.close();
}
await fs.writeFile(new URL('../artifacts/safari_audio_check.json',import.meta.url),JSON.stringify(reports,null,2));
if(reports.some(r=>r.checks.some(c=>!c.ok)))process.exitCode=1;
