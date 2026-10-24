// Run against a built static preview with service workers and byte ranges enabled.
import { chromium, webkit } from '../.runtime/qa/node_modules/playwright-core/index.mjs';
import fs from 'node:fs/promises';
const base=process.env.AUDIO_PREVIEW_URL||'http://127.0.0.1:8793/';
const reports=[];
for (const [engine,type,executablePath] of [
 ['chromium',chromium,'/root/.cache/ms-playwright/chromium-1248/chrome-linux64/chrome'],
 ['webkit',webkit,'/root/.cache/ms-playwright/webkit-2370/pw_run.sh']]) {
 const browser=await type.launch({headless:true,executablePath,args:engine==='chromium'?['--no-sandbox']:[]});
 const context=await browser.newContext({serviceWorkers:'allow'}),page=await context.newPage(),checks=[],errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 const check=(label,ok,detail)=>{checks.push({label,ok,detail});console.log(engine,ok?'PASS':'FAIL',label,JSON.stringify(detail));if(!ok)throw Error(label);};
 try {
  await page.goto(base);await page.waitForFunction(()=>!!navigator.serviceWorker.controller);
  const url=new URL('audio/ambient.mp3',base).href;
  await page.evaluate(async url=>{for(const key of await caches.keys())await(await caches.open(key)).delete(url);},url);
  const fetchAudio=async(headers={})=>page.evaluate(async({url,headers})=>{const response=await fetch(url,{headers});const bytes=new Uint8Array(await response.arrayBuffer());return {status:response.status,range:response.headers.get('Content-Range'),size:bytes.length,head:[...bytes.slice(0,24)]};},{url,headers});
  const initial=await fetchAudio({Range:'bytes=0-99'});
  // Some static hosts ignore Range and return a whole 200, which is also valid.
  check('online media request survives a 206 partial response',initial.status===206||initial.status===200,initial);
  const cachedPartial=await page.evaluate(async url=>{const c=await caches.open((await caches.keys()).find(k=>k.startsWith('blackblade-')));const r=await c.match(url);return r?.status||null;},url);
  check('a partial response never becomes a cached full audio file',cachedPartial!==206,cachedPartial);
  const full=await fetchAudio();check('whole audio download is complete',full.status===200&&full.size>1000,full);
  await page.waitForFunction(async url=>{for(const key of await caches.keys()){const response=await(await caches.open(key)).match(url);if(response?.status===200)return true;}return false;},url);
  await context.setOffline(true);
  const range=await fetchAudio({Range:'bytes=0-99'});
  check('offline Safari range comes from the full cached body',range.status===206&&range.size===100&&range.range===`bytes 0-99/${full.size}`&&JSON.stringify(range.head)===JSON.stringify(full.head),range);
  const open=await fetchAudio({Range:'bytes=100-'});
  check('open ended offline byte range is exact',open.status===206&&open.size===full.size-100&&open.range===`bytes 100-${full.size-1}/${full.size}`,open);
  const suffix=await fetchAudio({Range:'bytes=-64'});
  check('suffix offline byte range is exact',suffix.status===206&&suffix.size===64&&suffix.range===`bytes ${full.size-64}-${full.size-1}/${full.size}`,suffix);
  const bad=await fetchAudio({Range:`bytes=${full.size}-`});
  check('unsatisfiable offline range returns 416',bad.status===416&&bad.range===`bytes */${full.size}`,bad);
  const ifRange=await fetchAudio({Range:'bytes=0-99','If-Range':'"unmatched-audio-version"'});
  check('unmatched If-Range returns a complete representation',ifRange.status===200&&ifRange.size===full.size,ifRange);
  await context.setOffline(false);
  check('service worker does not introduce page errors',errors.length===0,errors);
 } catch(error) { checks.push({label:'case completes',ok:false,detail:String(error)});console.log(engine,'FAIL',String(error)); }
 reports.push({engine,checks,errors});await browser.close();
}
await fs.writeFile(new URL('../artifacts/audio_sw_check.json',import.meta.url),JSON.stringify(reports,null,2));
if(reports.some(r=>r.checks.some(c=>!c.ok)))process.exitCode=1;
