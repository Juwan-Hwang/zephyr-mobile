import asyncio,os,glob,subprocess,json
R=0.25
from playwright.async_api import async_playwright
U='file:///workspace/projects/d8290f90-c800-4100-8bf6-1b7482fdf18c/design/prototype/index.html'
TOUCH='''(()=>{const d=document.createElement('div');d.id='tch';d.style.cssText='position:fixed;width:40px;height:40px;margin:-20px 0 0 -20px;border-radius:20px;background:rgba(255,255,255,.12);border:1px solid rgba(255,255,255,.35);pointer-events:none;z-index:99999;opacity:0;transition:opacity .2s,transform .15s;left:-100px;top:-100px';document.body.appendChild(d);
addEventListener('mousemove',e=>{d.style.left=e.clientX+'px';d.style.top=e.clientY+'px'},true);
addEventListener('mousedown',()=>{d.style.opacity=1;d.style.transform='scale(.8)'},true);
addEventListener('mouseup',()=>{d.style.transform='scale(1)';d.style.opacity=0},true);})()'''
async def main():
  os.makedirs('rec',exist_ok=True)
  for f in glob.glob('rec/*'):os.remove(f)
  async with async_playwright() as p:
    b=await p.chromium.launch()
    ctx=await b.new_context(viewport={'width':1100,'height':1000},device_scale_factor=1,record_video_dir='rec',record_video_size={'width':1100,'height':1000})
    pg=await ctx.new_page()
    await pg.add_init_script('''(()=>{const R=%s;const pn=performance.now.bind(performance),t0=pn();performance.now=()=>t0+(pn()-t0)*R;const dn=Date.now,d0=dn();Date.now=()=>d0+(dn()-d0)*R;const st=setTimeout,si=setInterval;window.setTimeout=(f,ms,...a)=>st(f,(ms||0)/R,...a);window.setInterval=(f,ms,...a)=>si(f,(ms||0)/R,...a);const raf=requestAnimationFrame.bind(window);window.requestAnimationFrame=cb=>raf(t=>cb(t0+(t-t0)*R));})()'''%R)
    cdp=await ctx.new_cdp_session(pg);await cdp.send('Animation.enable');await cdp.send('Animation.setPlaybackRate',{'playbackRate':R})
    await pg.goto(U+'?s=home-off&embed=1');await pg.wait_for_timeout(300)
    await pg.evaluate(TOUCH)
    bb=await pg.locator('#device').bounding_box();json.dump(bb,open('rec/bb.json','w'))
    W=lambda ms:pg.wait_for_timeout(ms/R)
    cur=[550,900]
    async def mv(x,y,steps):
      x0,y0=cur
      for i in range(1,steps+1):
        e=i/steps;await pg.mouse.move(x0+(x-x0)*e,y0+(y-y0)*e);await W(16)
      cur[:]=[x,y]
    async def tap(sel,dx=None,dy=None):
      r=await pg.locator(sel).first.bounding_box();x=r['x']+(dx if dx is not None else r['width']/2);y=r['y']+(dy if dy is not None else r['height']/2)
      await mv(x,y,12);await W(120);await pg.mouse.down();await W(90);await pg.mouse.up()
    await W(900)
    await tap('#sw');await W(1800)
    r=await pg.locator('#rowAI').bounding_box()
    await mv(r['x']+230,r['y']+32,15);await pg.mouse.down();await mv(r['x']+120,r['y']+32,30);await W(200);await pg.mouse.up();await W(1300)
    await tap('#cfYes');await W(1600)
    await tap('#cmdOpen');await W(500)
    await pg.type('#cin','Gemini 走日本',delay=int(110/R));await W(1400)
    await pg.press('#cin','Enter');await W(1600)
    await tap('#libOpen');await W(1100)
    await tap('#libSheet .lc >> nth=0');await W(1100)
    v=await pg.locator('#vl').bounding_box()
    await mv(v['x']+170,v['y']+260,10)
    for i in range(14): await pg.mouse.wheel(0,420);await W(40)
    await W(1500)
    rl=await pg.locator('#rail').bounding_box()
    await mv(rl['x']+15,rl['y']+20,10);await pg.mouse.down()
    for k in range(1,30): await mv(rl['x']+15,rl['y']+20+k*(rl['height']-40)/30,2);await W(30)
    await W(500);await pg.mouse.up();await W(1600)
    await tap('#nq');await pg.type('#nq','东京 NTT IPLC',delay=int(110/R));await W(1600)
    await tap('#nodes [data-back]');await W(900)
    await tap('#libSheet .lc >> nth=2');await W(900)
    await tap('#rx');await W(300)
    await pg.type('#rq','chat.openai.com',delay=int(70/R));await W(1600)
    await pg.fill('#rq','');await pg.type('#rq','ads.doubleclick.net',delay=int(60/R));await W(1800)
    await pg.close();await ctx.close();await b.close()
asyncio.run(main())
v=glob.glob('rec/*.webm')[0];bb=json.load(open('rec/bb.json'))
x,y,w,h=[int(round(bb[k])) for k in ('x','y','width','height')];pad=16
x-=pad;y-=pad;w+=2*pad;h+=2*pad;w-=w%2;h-=h%2
subprocess.run(['ffmpeg','-y','-loglevel','error','-i',v,'-vf',f'setpts=PTS*{R},fps=30,crop={w}:{h}:{x}:{y},scale={w*2}:{h*2}:flags=lanczos','-c:v','libx264','-pix_fmt','yuv420p','-crf','18','-preset','slow','-movflags','+faststart','Zephyr-Mobile-Demo.mp4'],check=True)
print(subprocess.run(['ffprobe','-v','error','-show_entries','format=duration,size','-of','csv=p=0','Zephyr-Mobile-Demo.mp4'],capture_output=True,text=True).stdout)
