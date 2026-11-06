import asyncio
from playwright.async_api import async_playwright
U='file:///workspace/projects/d8290f90-c800-4100-8bf6-1b7482fdf18c/design/prototype/index.html'
async def main():
  async with async_playwright() as p:
    b=await p.chromium.launch();pg=await b.new_page(viewport={'width':1200,'height':1000})
    errs=[];pg.on('pageerror',lambda e:errs.append(str(e)));pg.on('console',lambda m:m.type=='error' and errs.append(m.text))
    await pg.goto(U+'?s=home-off');await pg.wait_for_timeout(600)
    async def vis(sel): return await pg.locator(sel).first.is_visible()
    await pg.click('#sw');await pg.wait_for_timeout(500);print('on dur',await pg.inner_text('#dur'))
    # drag AI row
    bb=await pg.locator('#rowAI').bounding_box()
    await pg.mouse.move(bb['x']+200,bb['y']+30);await pg.mouse.down();await pg.mouse.move(bb['x']+120,bb['y']+30,steps=8);await pg.mouse.up();await pg.wait_for_timeout(500)
    print('confirm open',await pg.evaluate("document.querySelector('#aiConfirm').classList.contains('open')"),await pg.inner_text('#aiNode'))
    await pg.click('#cfYes');await pg.wait_for_timeout(400);print('toast',await pg.inner_text('#toastText'),await pg.evaluate("document.querySelector('#toast').classList.contains('show')"))
    await pg.click('#undo');await pg.wait_for_timeout(400);print('after undo',await pg.inner_text('#aiNode'))
    # command
    await pg.click('#cmdOpen');await pg.wait_for_timeout(400)
    for q in ['Gemini 走日本','claude 用香港','github 直连','视频只用 4K','香港','东京','asdf','Netflix 走日本','chatgpt us']:
      await pg.fill('#cin','');await pg.type('#cin',q,delay=5);await pg.wait_for_timeout(100)
      t=(await pg.inner_text('#cres')).replace('\n',' | ');print('CMD',q,'=>',t[:170])
    await pg.fill('#cin','');await pg.type('#cin','Gemini 走日本');await pg.press('#cin','Enter');await pg.wait_for_timeout(400)
    print('applied',await pg.inner_text('#toastText'),await pg.inner_text('#rowAI .pin'))
    await pg.click('#undo');await pg.wait_for_timeout(300);print('undo pin',await pg.inner_text('#rowAI .pin'))
    # scene sheet
    await pg.locator('.row[data-scene=media]').click();await pg.wait_for_timeout(500);print('sheet',await pg.evaluate("[...document.querySelectorAll('.sheet.show')].map(s=>s.id)"))
    await pg.click('#veil',position={'x':50,'y':40});await pg.wait_for_timeout(400);print('after veil',await pg.evaluate("[...document.querySelectorAll('.sheet.show')].map(s=>s.id)"))
    await pg.click('#wind');await pg.wait_for_timeout(500);print('act',await pg.evaluate("[...document.querySelectorAll('.sheet.show')].map(s=>s.id)"))
    await pg.click('#openTrace');await pg.wait_for_timeout(500);print('trace vis',await vis('#trace'))
    await pg.click('#veil',position={'x':50,'y':40});await pg.wait_for_timeout(400)
    for i in range(2): await pg.click('#modeBtn');await pg.wait_for_timeout(200)
    print('mode',await pg.inner_text('#modeText'))
    await pg.goto(U+'?s=global');await pg.wait_for_timeout(500)
    await pg.click('#gChange');await pg.wait_for_timeout(450);await pg.click('#gYes');await pg.wait_for_timeout(300);print('global',await pg.inner_text('#globalWrap .k'))
    await pg.click('#libOpen');await pg.wait_for_timeout(400);print('lib',await pg.evaluate("[...document.querySelectorAll('.sheet.show')].map(s=>s.id)"))
    print('ERRS',errs)
    await b.close()
asyncio.run(main())
