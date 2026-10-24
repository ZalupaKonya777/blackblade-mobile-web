// Trusted touch against the actual release WASM; only renderer budget is reduced.
import {chromium} from '../.runtime/qa/node_modules/playwright-core/index.mjs';
import {readFile,writeFile} from 'node:fs/promises';
const browser=await chromium.launch({headless:true,executablePath:'/root/.cache/ms-playwright/chromium-1248/chrome-linux64/chrome',args:['--no-sandbox','--disable-dev-shm-usage','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--autoplay-policy=user-gesture-required']});
const context=await browser.newContext({viewport:{width:844,height:390},isMobile:true,hasTouch:true,serviceWorkers:'block'});
const page=await context.newPage();page.setDefaultTimeout(120000);
const cdp=await context.newCDPSession(page),fingers=new Map(),checks=[],errors=[];
page.on('pageerror',e=>errors.push(e.message));
function check(label,ok,detail){checks.push({label,ok,detail});console.log(ok?'PASS':'FAIL',label,JSON.stringify(detail));if(!ok)throw Error(label);}
async function point(selector,id,dy=0,dx=0){const r=await page.locator(selector).boundingBox();if(!r)throw Error('Hidden '+selector);return {id,x:r.x+r.width/2+dx,y:r.y+r.height/2+dy,radiusX:8,radiusY:8,force:.6};}
async function tap(selector,id=7){const p=await point(selector,id);const down=cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[...fingers.values(),p]});const up=cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:fingers.size?[p]:[]});await Promise.all([down,up]);}
let failure=null;
try{
 await page.addInitScript(()=>localStorage.setItem('blackblade-visual-quality-v2','0'));
 await page.route('**/app.js*',async route=>{
  let js=await readFile(new URL('../web/app.js',import.meta.url),'utf8');
  js=js.replace("'--qa-controls'","'--qa-controls','--low'").replace('dpr: 1.25, width: 1440, height: 864','dpr: .35, width: 320, height: 148');
  await route.fulfill({contentType:'text/javascript',body:js});
 });
 await page.goto('http://127.0.0.1:8793/?qa=1');await tap('#enter');
 await page.waitForFunction(()=>typeof BlackbladeNative==='function'&&BlackbladeUI.state?.phase==='title',null,{timeout:240000});
 check('release WASM boots',true,await page.evaluate(()=>BlackbladeUI.graphics));
 await page.evaluate(()=>{
  const update=BlackbladeUI.update.bind(BlackbladeUI);window.encounterSeen=new Set();window.encounterRolls=[];
  BlackbladeUI.update=json=>{const s=typeof json==='string'?JSON.parse(json):json;if(s.playerMove)encounterSeen.add(s.playerMove);if(s.playerState==='roll')encounterRolls.push({locked:s.rollLocked,x:s.rollLocalX,z:s.rollLocalZ});return update(json);};
 });
 await tap('#training');await page.waitForFunction(()=>BlackbladeUI.state?.phase==='fight',null,{timeout:180000});
 await page.waitForFunction(()=>(BlackbladeSound.diagnostics.events.beast_roar||0)>0);
 check('native beast roar still reaches browser audio',true,await page.evaluate(()=>BlackbladeSound.diagnostics.events));
 await page.evaluate(()=>BlackbladeNative(JSON.stringify({type:'qa_dummy'})));await page.waitForFunction(()=>!BlackbladeUI.state.bossAI);
 const start=Date.now();let seen=[];
 while(Date.now()-start<180000){await tap('#light');await page.waitForTimeout(100);seen=await page.evaluate(()=>[...encounterSeen]);if(['light1','light2','light3','light4'].every(id=>seen.includes(id)))break;}
 check('real touch inputs execute all four distinct light attacks', ['light1','light2','light3','light4'].every(id=>seen.includes(id)),seen);
 await page.waitForFunction(()=>BlackbladeUI.state.stamina>28&&['idle','move'].includes(BlackbladeUI.state.playerState));
 const stick=await point('#joystick',2,0,43);fingers.set(2,stick);await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[...fingers.values()]});
 const x=await page.evaluate(()=>BlackbladeUI.state.playerX);await page.waitForFunction(x=>BlackbladeUI.state.playerX>x+.12,x);
 await tap('#dodge',3);await page.waitForFunction(()=>encounterRolls.length>0);
 const roll=await page.evaluate(()=>encounterRolls[0]);check('locked side input selects a lateral body roll',roll.locked&&Math.abs(roll.x)>.90&&Math.abs(roll.z)<.30,roll);
 fingers.clear();await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
 check('no JavaScript exceptions in integrated encounter',errors.length===0,errors);
}catch(error){failure=String(error);console.log('FAILED',failure);}
finally{
 const state=await page.evaluate(()=>({native:BlackbladeUI?.state,audio:BlackbladeSound?.diagnostics,seen:[...(window.encounterSeen||[])]})).catch(()=>null);
 await writeFile(new URL('../artifacts/encounter_browser_check.json',import.meta.url),JSON.stringify({checks,failure,state,errors,note:'Actual release WASM and trusted Chromium touch. Test-only --low and a small drawing buffer bound the software GPU. No physical iPhone performance or speaker measurement.'},null,2));
 await browser.close();
}
if(failure)process.exitCode=1;
