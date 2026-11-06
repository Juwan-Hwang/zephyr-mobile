import sys
from PIL import Image
fs=sys.argv[1].split(',');ims=[Image.open(f'shots/{f}.png') for f in fs]
w,h=ims[0].size;s=Image.new('RGB',(w*len(fs)+20*(len(fs)-1),h),(40,40,44))
for i,im in enumerate(ims): s.paste(im,(i*(w+20),0))
s.resize((s.width*int(sys.argv[2])//10,s.height*int(sys.argv[2])//10)).save('shots/sheet.png')
