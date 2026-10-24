import {chromium,webkit} from '../.runtime/qa/node_modules/playwright-core/index.mjs';
import fs from 'node:fs/promises';
const base=process.env.AUDIO_PREVIEW_URL||'http://127.0.0.1:8793/';
const reports=[];
for(const [name,type,executablePath] of [['chromium',chromium,'/root/.cache/ms-playwright/chromium-1248/chrome-linux64/chrome'],['webkit',webkit,'/root/.cache/ms-playwright/webkit-2370/pw_run.sh']]){
 const browser=await type.launch({headless:true,executablePath,args:name==='chromium'?['--no-sandbox','--autoplay-policy=user-gesture-required']:[]});
 const context=await browser.newContext({viewport:{width:844,height:390},isMobile:true,hasTouch:true,serviceWorkers:'block'});
 const page=await context.newPage(),checks=[],errors=[];page.on('pageerror',e=>errors.push(e.message));
 const check=(label,ok,detail)=>{checks.push({label,ok,detail});console.log(name,ok?'PASS':'FAIL',label,JSON.stringify(detail));if(!ok)throw Error(label);};
 try{
  await page.route('**/app.js*',route=>route.abort());await page.goto(base+'?audio-qa=1');
  await page.addScriptTag({url:new URL('sound.js',base).href});
  await page.evaluate(async()=>{await BlackbladeSound.prepare();document.querySelector('#enter').addEventListener('click',()=>BlackbladeSound.unlock());});
  await page.locator('#enter').tap();await page.waitForFunction(()=>BlackbladeSound.diagnostics.decoded===82&&BlackbladeSound.context.state==='running');
  check('all fifteen new recorded vocal variants decode',await page.evaluate(()=>Object.keys(BlackbladeSound.bank.files).filter(k=>k.startsWith('beast_')).length===15));
  await page.evaluate(()=>{BlackbladeSound.listener(0,1,4,0,0,-1,0,1,0);BlackbladeSound.fight(true);BlackbladeSound.play('beast_breath',0,1,0,-3);});
  await page.waitForFunction(()=>BlackbladeSound.diagnostics.rms>.0005);
  check('creature breathing reaches the real audio graph',await page.evaluate(()=>BlackbladeSound.diagnostics.events.beast_breath===1),await page.evaluate(()=>BlackbladeSound.diagnostics));
  await page.evaluate(()=>{BlackbladeSound.play('beast_roar',0,1,0,0);BlackbladeSound.play('beast_growl');BlackbladeSound.play('beast_pain');BlackbladeSound.play('beast_breath');});
  check('roar has one vocal lane and suppresses softer interruptions',await page.evaluate(()=>BlackbladeSound.diagnostics.voices.length===1&&BlackbladeSound.diagnostics.voices[0].event==='beast_roar'&&!BlackbladeSound.diagnostics.events.beast_pain),await page.evaluate(()=>BlackbladeSound.diagnostics));
  await page.waitForTimeout(140);
  check('music ducks under the important vocal',await page.evaluate(()=>BlackbladeSound.musicDuck.gain.value<.70),await page.evaluate(()=>BlackbladeSound.musicDuck.gain.value));
  await page.evaluate(()=>{BlackbladeSound.play('beast_death',0,1,0,0);BlackbladeSound.fight(false);});
  check('death overrides roar and survives the victory transition',await page.evaluate(()=>BlackbladeSound.diagnostics.voices[0]?.event==='beast_death'));
  await page.evaluate(()=>BlackbladeSound.fight(true));await page.waitForTimeout(60);
  check('retry clears the old vocal lane',await page.evaluate(()=>BlackbladeSound.diagnostics.voices.length===0));
  await page.evaluate(()=>{BlackbladeSound.play('beast_attack',0,1,0);BlackbladeSound.play('beast_attack',0,1,0);});
  check('duplicate attack cue is limited without delaying its first sound',await page.evaluate(()=>BlackbladeSound.diagnostics.events.beast_attack===1));
  await page.waitForTimeout(340);await page.evaluate(()=>BlackbladeSound.play('beast_attack',0,1,0));
  check('a subsequent sword release can sound again',await page.evaluate(()=>BlackbladeSound.diagnostics.events.beast_attack===2));
  await page.evaluate(()=>{BlackbladeSound.play('beast_roar',0,1,0);BlackbladeSound.mute(true);});await page.waitForTimeout(450);
  check('mute also silences creature vocals',await page.evaluate(()=>BlackbladeSound.diagnostics.rms<.00001));
  await page.evaluate(async()=>{BlackbladeSound.mute(false);await BlackbladeSound.context.close();});await page.locator('#enter').tap();
  await page.waitForFunction(()=>BlackbladeSound.context.state==='running');
  await page.evaluate(()=>BlackbladeSound.play('beast_breath',0,1,0));
  check('output repair clears stale vocal priorities and cooldowns',await page.evaluate(()=>BlackbladeSound.diagnostics.voices[0]?.event==='beast_breath'));
  check('no browser exceptions',errors.length===0,errors);
 }catch(error){checks.push({label:'suite completes',ok:false,detail:String(error)});console.log(name,'FAIL',String(error));}
 reports.push({browser:name,checks,errors,note:'Actual browser audio decoding and processing. Physical iPhone speaker output is not emulated.'});await browser.close();
}
await fs.writeFile(new URL('../artifacts/beast_audio_browser_check.json',import.meta.url),JSON.stringify(reports,null,2));
if(reports.some(r=>r.checks.some(c=>!c.ok)))process.exitCode=1;
