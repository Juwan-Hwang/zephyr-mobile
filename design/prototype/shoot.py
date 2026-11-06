import asyncio,sys
from playwright.async_api import async_playwright
STATES=sys.argv[1].split(',')
async def main():
    async with async_playwright() as p:
        b=await p.chromium.launch()
        pg=await b.new_page(viewport={'width':1100,'height':1000},device_scale_factor=2)
        errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
        for s in STATES:
            await pg.goto(f'file:///workspace/projects/d8290f90-c800-4100-8bf6-1b7482fdf18c/design/prototype/index.html?s={s}&embed=1')
            await pg.wait_for_timeout(1600)
            await pg.locator('#device').screenshot(path=f'shots/{s}.png')
        print('ERR',errs)
        await b.close()
asyncio.run(main())
