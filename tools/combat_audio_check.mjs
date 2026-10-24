// Actual WASM combat and trusted touch, with a bounded software-GPU budget.
import {chromium} from '../.runtime/qa/node_modules/playwright-core/index.mjs';
import {readFile,writeFile} from 'node:fs/promises';
const browser=await chromium.launch({headless:true,executablePath:'/root/.cache/ms-playwright/chromium-1248/chrome-linux64/chrome',args:['--no-sandbox','--disable-dev-shm-usage','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--autoplay-policy=user-gesture-required']});
const context=await browser.newContext({viewport:{width:844,height:390},isMobile:true,hasTouch:true,serviceWorkers:'block'});
const page=await context.newPage();page.setDefaultTimeout(90000);
const cdp=await context.newCDPSession(page),fingers=new Map(),checks=[],errors=[];
page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')console.log('BROWSER',m.text().slice(0,250));});
function check(label,ok,detail){checks.push({label,ok,detail});console.log(ok?'PASS':'FAIL',label,JSON.stringify(detail));if(!ok)throw Error(label);}
async function touch(selector,id,down,dy=0){
 const r=await page.locator(selector).boundingBox();if(!r)throw Error('Hidden '+selector);
 const point={id,x:r.x+r.width/2,y:r.y+r.height/2+dy,radiusX:8,radiusY:8,force:.6};
 if(down)fingers.set(id,point);else fingers.delete(id);
 await cdp.send('Input.dispatchTouchEvent',{type:down?'touchStart':'touchEnd',touchPoints:down?[...fingers.values()]:(fingers.size?[point]:[])});
}
async function tap(selector,id){
 const r=await page.locator(selector).boundingBox();const point={id,x:r.x+r.width/2,y:r.y+r.height/2,radiusX:8,radiusY:8,force:.6};
 const down=cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[...fingers.values(),point]});
 const up=cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:fingers.size?[point]:[]});await Promise.all([down,up]);
}
let failure=null;
try{
 await page.addInitScript(()=>localStorage.setItem('blackblade-visual-quality-v2','0'));
 // Test-only renderer flags. The PCK, sound engine and input/combat code are
 // byte-identical to the release; no game state or sound event is mocked.
 await page.route('**/app.js*',async route=>{
  let js=await readFile(new URL('../web/app.js',import.meta.url),'utf8');
  js=js.replace("'--qa-controls'","'--qa-controls','--low'").replace('dpr: 1.25, width: 1440, height: 864','dpr: .5, width: 480, height: 222');
  await route.fulfill({contentType:'text/javascript',body:js});
 });
 await page.goto('http://127.0.0.1:8793/?qa=1');await tap('#enter',1);
 await page.waitForFunction(()=>typeof BlackbladeNative==='function'&&BlackbladeUI.state?.phase==='title',null,{timeout:240000});
 check('actual release WASM boots with a software-GPU test budget',true,await page.evaluate(()=>BlackbladeUI.graphics));
 await tap('#training',1);await page.waitForFunction(()=>BlackbladeUI.state?.phase==='fight',null,{timeout:180000});
 await page.waitForFunction(()=>(BlackbladeSound.diagnostics.events.beast_roar||0)>0,null,{timeout:120000});
 check('real beast intro sends its recorded roar through the native browser bridge',await page.evaluate(()=>BlackbladeSound.diagnostics.decoded===82),await page.evaluate(()=>BlackbladeSound.diagnostics));
 await page.evaluate(()=>BlackbladeNative(JSON.stringify({type:'qa_dummy'})));
 await page.waitForFunction(()=>!BlackbladeUI.state.bossAI);
 await touch('#joystick',2,true,40);
 await page.waitForFunction(()=>BlackbladeUI.state.playerZ>6.12);
 await tap('#dodge',3);
 await page.waitForFunction(()=>(BlackbladeSound.diagnostics.events.body_contact||0)>0,null,{timeout:120000});
 await touch('#joystick',2,false);
 check('real moving roll starts takeoff and ground-contact audio',await page.evaluate(()=>(BlackbladeSound.diagnostics.events.armor_takeoff||0)>0&&BlackbladeSound.diagnostics.events.body_contact>0),await page.evaluate(()=>BlackbladeSound.diagnostics.events));
 await page.waitForFunction(()=>['idle','move'].includes(BlackbladeUI.state.playerState));
 await touch('#heavy',4,true);
 await page.waitForFunction(()=>BlackbladeUI.state.charged,null,{timeout:120000});
 await touch('#heavy',4,false);
 await page.waitForFunction(()=>(BlackbladeSound.diagnostics.events.knight_heavy||0)>0,null,{timeout:120000});
 check('released charged attack starts its native heavy swing sound',true,await page.evaluate(()=>BlackbladeSound.diagnostics));
 check('no JavaScript exceptions in integrated combat',errors.length===0,errors);
}catch(error){failure=String(error);console.log('FAILED',failure);}
finally{
 const state=await page.evaluate(()=>({native:BlackbladeUI?.state,audio:BlackbladeSound?.diagnostics})).catch(()=>null);
 await writeFile(new URL('../artifacts/combat_audio_check.json',import.meta.url),JSON.stringify({checks,failure,state,errors,note:'Trusted Chromium touch and unchanged release WASM. Test-only --low and 480px cap bound the software GPU. This does not measure physical iPhone performance.'},null,2));
 await browser.close();
}
if(failure)process.exitCode=1;
