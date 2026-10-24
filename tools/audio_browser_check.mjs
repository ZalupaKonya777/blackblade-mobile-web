import { chromium, webkit } from '../.runtime/qa/node_modules/playwright-core/index.mjs';
import fs from 'node:fs/promises';
const report=[];
const base=process.env.AUDIO_PREVIEW_URL||'http://127.0.0.1:8793/';
for(const [name,type,executablePath] of [
 ['chromium',chromium,'/root/.cache/ms-playwright/chromium-1248/chrome-linux64/chrome'],
 ['webkit',webkit,'/root/.cache/ms-playwright/webkit-2370/pw_run.sh']]){
 const browser=await type.launch({headless:true,executablePath,args:name==='chromium'?['--no-sandbox','--autoplay-policy=user-gesture-required']:[]});
 const context=await browser.newContext({viewport:{width:844,height:390},isMobile:true,hasTouch:true});
 const page=await context.newPage();const errors=[];const checks=[];
 page.on('pageerror',error=>errors.push(error.message));
 const check=(label,ok,detail)=>{checks.push({label,ok,detail});console.log(name,ok?'PASS':'FAIL',label,JSON.stringify(detail));};
 try{
  await page.route('**/app.js*',route=>route.abort());
  await page.goto(base+'?audio-qa=1');
  await page.addScriptTag({url:new URL('sound.js',base).href});
  await page.evaluate(async()=>{await BlackbladeSound.prepare();for(const kind of ['pointerdown','touchend','click'])document.querySelector('#enter').addEventListener(kind,()=>BlackbladeSound.unlock());});
  check('audio remains locked before gesture',await page.evaluate(()=>BlackbladeSound.context===null));
  await page.locator('#enter').tap();
  await page.waitForFunction(()=>BlackbladeSound.diagnostics.decoded===67&&BlackbladeSound.diagnostics.state==='running',null,{timeout:30000});
  check('trusted touch unlocks and decodes all 67 files',true,await page.evaluate(()=>BlackbladeSound.diagnostics));
  await page.evaluate(()=>{BlackbladeSound.listener(0,1,4,0,0,-1,0,1,0);BlackbladeSound.fight(true);BlackbladeSound.play('knight_swing',0,1,0,-1,1);});
  await page.waitForFunction(()=>BlackbladeSound.diagnostics.rms>.0005);
  check('gesture starts an actual warm-up source',await page.evaluate(()=>BlackbladeSound.diagnostics.warmups>0),await page.evaluate(()=>BlackbladeSound.diagnostics));
  check('actual output contains audible samples',true,await page.evaluate(()=>BlackbladeSound.diagnostics));
  const immediate=await page.evaluate(()=>{
   for(const name of ['armor_takeoff','body_contact','knight_heavy'])BlackbladeSound.play(name,0,1,0,-3,1);
   const counts={...BlackbladeSound.diagnostics.events};const until=performance.now()+300;while(performance.now()<until){}
   return counts;
  });
  check('cached combat effects start synchronously before a slow frame yields',immediate.armor_takeoff===1&&immediate.body_contact===1&&immediate.knight_heavy===1,immediate);
  const afterStall=await page.evaluate(()=>BlackbladeSound.diagnostics);
  check('slow rendering does not discard roll and heavy effects',afterStall.events.body_contact===1&&afterStall.events.knight_heavy===1,afterStall);
  await page.evaluate(()=>{BlackbladeSound.state(2,false);BlackbladeSound.play('impact_beast',-2,1,0,-1,1);});
  await page.waitForTimeout(1100);
  const phase=await page.evaluate(()=>({diagnostics:BlackbladeSound.diagnostics,gains:[...BlackbladeSound.loops].map(([id,l])=>[id,l?.gain.gain.value]),loops:[...BlackbladeSound.loops].map(([id,l])=>[id,l?.source.loopEnd])}));
  check('phase II music crossfade and impact event',phase.diagnostics.phase===2&&phase.diagnostics.events.impact_beast===1&&phase.diagnostics.rms>0,phase);
  await page.evaluate(()=>BlackbladeSound.mute(true));await page.waitForTimeout(900);
  const muted=await page.evaluate(()=>BlackbladeSound.diagnostics);
  check('mute actually silences the output',muted.rms<.00001,muted.rms);
  await page.evaluate(async()=>{BlackbladeSound.mute(false);await BlackbladeSound.context.suspend();});
  await page.locator('#enter').tap();
  await page.waitForFunction(()=>BlackbladeSound.context.state==='running'&&BlackbladeSound.diagnostics.rms>.0001);
  check('touch resumes suspended audio',true,await page.evaluate(()=>BlackbladeSound.diagnostics));
  const route=await page.evaluate(()=>({session:BlackbladeSound.diagnostics.sessionType,media:!!BlackbladeSound.mediaOutput,playing:BlackbladeSound.mediaPlaying}));
  check('playback session or live media route is selected',route.session==='playback'||(route.media&&route.playing),route);
  if(route.media){
   await page.evaluate(()=>BlackbladeSound.mediaOutput.pause());
   await page.waitForFunction(()=>BlackbladeSound.needsGesture&&!BlackbladeSound.mediaPlaying);
   check('a stopped media endpoint is detected even with a running audio clock',await page.evaluate(()=>BlackbladeSound.context.state==='running'));
   await page.locator('#enter').tap();
   await page.waitForFunction(()=>BlackbladeSound.mediaPlaying&&!BlackbladeSound.needsGesture&&BlackbladeSound.diagnostics.rms>.0001);
   check('the next trusted gesture restores a stopped media endpoint',true,await page.evaluate(()=>BlackbladeSound.diagnostics));
  }
  await page.evaluate(()=>BlackbladeSound.background());
  await page.waitForFunction(()=>BlackbladeSound.context.state==='suspended');
  check('background pauses both audio output routes',await page.evaluate(()=>!BlackbladeSound.mediaOutput||BlackbladeSound.mediaOutput.paused));
  await page.locator('#enter').tap();
  await page.waitForFunction(()=>BlackbladeSound.context.state==='running'&&BlackbladeSound.diagnostics.rms>.0001);
  check('returning gesture resumes audible output',true,await page.evaluate(()=>BlackbladeSound.diagnostics));
  await page.evaluate(async()=>{window.previousSoundContext=BlackbladeSound.context;await BlackbladeSound.context.close();});
  await page.locator('#enter').tap();
  await page.waitForFunction(()=>BlackbladeSound.context!==previousSoundContext&&BlackbladeSound.context.state==='running'&&BlackbladeSound.diagnostics.rms>.0001&&(BlackbladeSound.outputRoute!=='media-stream'||BlackbladeSound.mediaPlaying));
  check('closed iOS output can be rebuilt without reloading the game',true,await page.evaluate(()=>BlackbladeSound.diagnostics));
  check('no browser audio script errors',errors.length===0,errors);
 }catch(error){check('audio component completes',false,error.message);}
 report.push({browser:name,checks,errors});await browser.close();
}
await fs.writeFile(new URL('../artifacts/audio_browser_check.json',import.meta.url),JSON.stringify(report,null,2));
if(report.some(r=>r.checks.some(c=>!c.ok)))process.exitCode=1;
