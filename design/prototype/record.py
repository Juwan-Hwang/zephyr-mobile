import asyncio,os,glob,subprocess,json
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
    await pg.goto(U+'?s=home-off&embed=1');await pg.wait_for_timeout(300)
    await pg.evaluate(TOUCH)
    bb=await pg.locator('#device').bounding_box();json.dump(bb,open('rec/bb.json','w'))
    W=pg.wait_for_timeout
    async def tap(sel,dx=None,dy=None):
      r=await pg.locator(sel).first.bounding_box();x=r['x']+(dx if dx is not None else r['width']/2);y=r['y']+(dy if dy is not None else r['height']/2)
      await pg.mouse.move(x,y,steps=12);await W(120);await pg.mouse.down();await W(90);await pg.mouse.up()
    await W(900)
    await tap('#sw');await W(1800)
    r=await pg.locator('#rowAI').bounding_box()
    await pg.mouse.move(r['x']+230,r['y']+32,steps=15);await pg.mouse.down();await pg.mouse.move(r['x']+120,r['y']+32,steps=30);await W(200);await pg.mouse.up();await W(1300)
    await tap('#cfYes');await W(1600)
    await tap('#cmdOpen');await W(500)
    await pg.type('#cin','Gemini 走日本',delay=110);await W(1400)
    await pg.press('#cin','Enter');await W(1600)
    await tap('#libOpen');await W(1100)
    await tap('#libSheet .lc >> nth=0');await W(1100)
    v=await pg.locator('#vl').bounding_box()
    await pg.mouse.move(v['x']+170,v['y']+260,steps=10)
    for i in range(14): await pg.mouse.wheel(0,420);await W(40)
    await W(1500)
    rl=await pg.locator('#rail').bounding_box()
    await pg.mouse.move(rl['x']+15,rl['y']+20,steps=10);await pg.mouse.down()
    for k in range(1,30): await pg.mouse.move(rl['x']+15,rl['y']+20+k*(rl['height']-40)/30);await W(45)
    await W(500);await pg.mouse.up();await W(1600)
    await tap('#nq');await pg.type('#nq','东京 NTT IPLC',delay=110);await W(1600)
    await tap('#nodes [data-back]');await W(900)
    await tap('#libSheet .lc >> nth=2');await W(900)
    await tap('#rx');await W(300)
    await pg.type('#rq','chat.openai.com',delay=70);await W(1600)
    await pg.fill('#rq','');await pg.type('#rq','ads.doubleclick.net',delay=60);await W(1800)
    await pg.close();await ctx.close();await b.close()
asyncio.run(main())
v=glob.glob('rec/*.webm')[0];bb=json.load(open('rec/bb.json'))
x,y,w,h=[int(round(bb[k])) for k in ('x','y','width','height')];pad=16
x-=pad;y-=pad;w+=2*pad;h+=2*pad;w-=w%2;h-=h%2
subprocess.run(['ffmpeg','-y','-loglevel','error','-i',v,'-vf',f'crop={w}:{h}:{x}:{y},scale={w*2}:{h*2}:flags=lanczos','-c:v','libx264','-pix_fmt','yuv420p','-crf','18','-preset','slow','-movflags','+faststart','Zephyr-Mobile-Demo.mp4'],check=True)
print(subprocess.run(['ffprobe','-v','error','-show_entries','format=duration,size','-of','csv=p=0','Zephyr-Mobile-Demo.mp4'],capture_output=True,text=True).stdout)
