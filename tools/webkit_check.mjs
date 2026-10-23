import { webkit } from '../.runtime/qa/node_modules/playwright-core/index.mjs';
import { writeFile } from 'node:fs/promises';
const root = new URL('../', import.meta.url);
const checks = [], errors = [], logs = [];
let browser, page, failure = null;
function check(name, ok, detail = '') {
  checks.push({ name, ok:!!ok, detail }); console.log(ok ? 'PASS' : 'FAIL', name, detail);
  if (!ok) throw new Error(name);
}
try {
  browser = await webkit.launch({
    executablePath: process.env.WEBKIT_PATH || '/root/.cache/ms-playwright/webkit-2370/pw_run.sh',
    headless: true,
    env: { ...process.env, TMPDIR: new URL('.runtime/tmp',root).pathname,
      XDG_CACHE_HOME:new URL('.runtime/webkit-cache',root).pathname,
      XDG_CONFIG_HOME:new URL('.runtime/webkit-config',root).pathname,
      XDG_DATA_HOME:new URL('.runtime/webkit-data',root).pathname,
      LIBGL_ALWAYS_SOFTWARE:'1', WEBKIT_DISABLE_DMABUF_RENDERER:'1' },
  });
  const context = await browser.newContext({ viewport:{width:844,height:390}, deviceScaleFactor:2, isMobile:true, hasTouch:true, serviceWorkers:'block' });
  page = await context.newPage();
  page.setDefaultTimeout(120000);
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => { if (message.type()==='error') { logs.push(message.text());console.log('WEBKIT ERROR',message.text()); } });
  await page.goto('http://127.0.0.1:8793/?qa=1',{waitUntil:'networkidle',timeout:60000});
  check('WebKit mobile shell loads',await page.getByRole('button',{name:/Войти в храм/}).isVisible());
  const supports = await page.evaluate(() => {
    const c=document.createElement('canvas');const gl=c.getContext('webgl2');const supported=!!gl;
    gl?.getExtension('WEBGL_lose_context')?.loseContext();return {webgl2:supported,wasm:!!window.WebAssembly};
  });
  check('WebKit has WebGL 2 and WebAssembly',supports.webgl2&&supports.wasm,supports);
  await page.getByRole('button',{name:/Войти в храм/}).tap();
  await page.waitForFunction(()=>window.BlackbladeUI?.state?.phase==='title'&&typeof window.BlackbladeNative==='function',null,{timeout:300000});
  check('WebKit boots the actual Godot Web game',true);
  check('WebKit selects HD rendering with antialiasing',await page.evaluate(()=>window.BlackbladeUI.graphics.width===1688&&window.BlackbladeUI.state.msaa===1&&window.BlackbladeUI.state.renderScale===1));
  // Input/compatibility probes use a bounded software-renderer buffer. The
  // separate native review captures full-resolution character/arena poses.
  await page.evaluate(()=>{
    const quality=document.getElementById('graphics-quality');quality.value='0';quality.dispatchEvent(new Event('change'));
    game.width=480;game.height=222;
  });
  await page.waitForFunction(()=>window.BlackbladeUI.state.quality===0,null,{timeout:120000});
  // Linux WPE can stall while acknowledging a synthetic tap over a WebGL
  // frame. Use its trusted pointer protocol for these two bridge checks;
  // concurrent touchscreen input is exercised separately in Chromium.
  await page.getByRole('button',{name:'Тренировка',exact:true}).click();
  await page.waitForFunction(()=>window.BlackbladeUI?.state?.phase==='fight',null,{timeout:120000});
  check('WebKit pointer starts training',true);
  await page.screenshot({path:new URL('artifacts/mobile-webkit.png',root).pathname,scale:'css'});
  await page.getByRole('button',{name:'Быстрый удар',exact:true}).click();
  await page.waitForFunction(()=>window.BlackbladeUI.state.action==='light',null,{timeout:60000});
  check('WebKit pointer reaches native attack',true);
  check('WebKit audio unlocked',await page.evaluate(()=>window.BlackbladeUI.audioStates.includes('running')));
  const unexpected=logs.filter(text=>!text.includes('glBlitFramebuffer: Read and write color attachments cannot be the same image.'));
  check('WebKit has no JavaScript, script or resource failures',errors.length===0&&unexpected.length===0,{errors,unexpected});
} catch(error) { failure=String(error);console.log('WEBKIT CHECK FAILED',failure); }
finally {
  await writeFile(new URL('artifacts/webkit_check.json',root),JSON.stringify({checks,failures:failure?1:0,failure,errors,logs,rendererWarning:{messages:logs.filter(text=>text.includes('glBlitFramebuffer: Read and write color attachments cannot be the same image.')).length,upstreamReport:'https://github.com/godotengine/godot/issues/122816',note:'Recorded, not suppressed in the game. Known same-image self-blit report also reproduces in a blank Godot Web project; visual gameplay and input are checked separately.'},note:'Linux Playwright WebKit, mobile viewport. Initial touch loads the engine; trusted mouse-pointer protocol checks fight entry and attack because WPE synthetic tap acknowledgement timed out. Chromium tests concurrent touch. Not a physical iPhone or a phone performance measurement.'},null,2));
  if(browser)await browser.close();
}
if(failure)process.exitCode=1;
