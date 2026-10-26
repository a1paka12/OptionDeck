#!/usr/bin/env python3
"""Render a 30-second illustrated quickstart. Requires Pillow; no user screenshots."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math

ROOT = Path(__file__).resolve().parents[2]
FRAMES = ROOT / '.build' / 'quickstart-frames'
ASSETS = ROOT / 'docs' / 'assets'
W, H, FPS, SECONDS = 1280, 720, 12, 30
BG, INK, MUTED, BLUE = '#f2f4f7', '#1d1d1f', '#727780', '#007aff'
FONTS = {}
def font(size, mono=False, ko=False):
    key=(size,mono,ko)
    if key not in FONTS:
        file = '/System/Library/Fonts/AppleSDGothicNeo.ttc' if ko else ('/System/Library/Fonts/Menlo.ttc' if mono else '/System/Library/Fonts/SFNS.ttf')
        FONTS[key]=ImageFont.truetype(file,size)
    return FONTS[key]
def text(d,xy,label,size=24,fill=INK,mono=False,ko=False):
    d.text(xy,label,font=font(size,mono,ko),fill=fill)
def box(d,r,fill='white',radius=22,outline=None,width=1):
    d.rounded_rectangle(tuple(round(v) for v in r),radius=radius,fill=fill,outline=outline,width=width)
def curve(t, points=(.77,0,.175,1)):
    t=max(0,min(1,t)); lo,hi=0.,1.; x1,y1,x2,y2=points
    for _ in range(18):
        u=(lo+hi)/2; x=3*(1-u)**2*u*x1+3*(1-u)*u*u*x2+u**3
        if x<t: lo=u
        else: hi=u
    u=(lo+hi)/2
    return 3*(1-u)**2*u*y1+3*(1-u)*u*u*y2+u**3

def lerp(a,b,t): return a+(b-a)*max(0,min(1,t))
def cursor(d,x,y):
    d.polygon([(x,y),(x+4,y+29),(x+12,y+21),(x+22,y+34),(x+29,y+29),(x+20,y+16),(x+32,y+13)],fill=INK,outline='white',width=2)
def ring(d,x,y):
    d.ellipse((x-18,y-18,x+18,y+18),outline=BLUE,width=3)
    d.ellipse((x-5,y-5,x+5,y+5),fill=BLUE)
def play(d,x,y,size=15): d.polygon([(x-size/2,y-size),(x-size/2,y+size),(x+size,y)],fill=INK)
def media(d,r,title='System media',progress=.32):
    x,y,x2,y2=r; box(d,r)
    text(d,(x+24,y+20),title,24)
    d.line((x+24,y+72,x2-24,y+72),fill='#d9dde3',width=5)
    d.line((x+24,y+72,lerp(x+24,x2-24,progress),y+72),fill=BLUE,width=5)
    mid=(x+x2)/2; cy=y2-35
    text(d,(mid-95,cy-15),'‹',36); play(d,mid,cy,12); text(d,(mid+75,cy-15),'›',36)
def board(d,r,brightness=.55,page=0):
    x,y,x2,y2=r; box(d,r,fill='#e8ecf2',radius=28,outline='#dce1e8')
    text(d,(x+23,y+16),'⌥  OptionDeck',23)
    text(d,(x2-72,y+20),f'{page+1} / 2',17,fill=MUTED)
    if page==0:
        gap=12; inner=(x2-x-60)/2; top=y+62; bottom=y+185
        for j,label in enumerate(['Brightness','Volume']):
            lx=x+24+j*(inner+gap); box(d,(lx,top,lx+inner,bottom))
            text(d,(lx+18,top+16),label,20)
            val=brightness if j==0 else .45
            text(d,(lx+18,top+54),f'{round(val*100)}%',32)
            box(d,(lx+inner-34,top+20,lx+inner-20,bottom-20),fill='#e8ecf2',radius=7)
            box(d,(lx+inner-34,bottom-20-(bottom-top-40)*val,lx+inner-20,bottom-20),fill=BLUE,radius=7)
        media(d,(x+24,y+198,x2-24,y2-20))
    else:
        names=['Chrome','Editor','Terminal','Notes','Finder','Voice Memos']
        cw=(x2-x-68)/3
        for j,label in enumerate(names):
            xx=x+24+(j%3)*(cw+10); yy=y+62+(j//3)*65
            box(d,(xx,yy,xx+cw,yy+54),outline=BLUE if j==0 else None,width=2)
            text(d,(xx+12,yy+16),label,19)
        box(d,(x+24,y+198,x2-24,y2-20))
        text(d,(x+40,y+211),'Chrome · live menu shortcuts',18,fill=MUTED)
        text(d,(x+40,y+245),'New tab',21); text(d,(x2-130,y+245),'⌘ T',23)

TITLES=['Build once. Open OptionDeck.','Allow Accessibility.','Hold Option. Take control.','Swipe to your apps.','Make the layout yours.','Choose music. Release to return.']
SUBS=['macOS 14+  ·  Swift 6  ·  Rust 1.99+','System Settings → Privacy & Security → Accessibility','Trackpad position selects. Move up or down to adjust.','Two-finger swipe · shortcuts come from the selected app','Drag in to add · resize · drag out to remove','YouTube Music appears after installing its web app in Chrome']
KOREAN=['빌드하고 앱을 실행하세요. 도구는 처음 빌드할 때만 필요합니다.','시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 허용하세요.','Option을 누른 채 위치를 고르고, 위아래로 움직여 조절하세요.','두 손가락으로 페이지 전환 · 선택한 앱의 실제 메뉴 단축키를 표시합니다.','기능을 끌어 넣고 크기를 조절하세요. 밖으로 빼면 제거됩니다.','YouTube Music은 Chrome에서 앱으로 설치해야 표시됩니다. Option을 놓으면 복귀합니다.']

def render(t):
    scene=min(5,int(t//5)); u=t-scene*5
    im=Image.new('RGB',(W,H),BG); d=ImageDraw.Draw(im)
    text(d,(64,32),'OPTIONDECK',16,fill=MUTED)
    text(d,(1000,32),'ILLUSTRATED QUICKSTART',13,fill=MUTED)
    text(d,(64,78),TITLES[scene],46)
    text(d,(66,142),SUBS[scene],22,fill=MUTED)
    if scene==0:
        box(d,(100,210,1180,553),fill='#20242b')
        for i,c in enumerate(['#ff6058','#ffbd2e','#28c840']): d.ellipse((124+i*24,230,136+i*24,242),fill=c)
        lines=['git clone https://github.com/a1paka12/OptionDeck.git','cd OptionDeck','zsh scripts/build.sh','open dist/OptionDeck.app']
        for j,line in enumerate(lines):
            if u>j*.7+.2: text(d,(128,279+j*55),line,23,fill='#f4f7fb',mono=True)
        if u>3.1:
            box(d,(925,485,1154,532),fill=BLUE,radius=12); text(d,(951,495),'App opened  ✓',21,fill='white')
    elif scene==1:
        box(d,(100,210,780,553)); text(d,(130,237),'Privacy & Security',26)
        box(d,(122,292,758,345),fill='#f1f3f7',radius=10); text(d,(143,307),'Accessibility',23)
        text(d,(145,391),'⌥  OptionDeck',26)
        active=u>1.7; box(d,(676,389,720,421),fill=BLUE if active else '#cbd1db',radius=16)
        d.ellipse((699 if active else 679,393,719 if active else 699,417),fill='white')
        text(d,(840,320),'Allow OptionDeck',27)
        text(d,(840,369),'Then hold ⌥',24,fill=MUTED)
        cursor(d,695,lerp(476,403,curve(u/1.8)))
    elif scene==2:
        held=u>.45; box(d,(105,221,410,337),fill=BLUE if held else 'white')
        text(d,(174,244),'⌥ Option',38,fill='white' if held else INK)
        box(d,(86,393,429,552),fill='#e1e6ed',outline='#cdd4df')
        text(d,(183,563),'TRACKPAD',14,fill=MUTED)
        progress=curve((u-1.4)/2.1); value=lerp(.25,.76,progress)
        board(d,(500,204,1190,569),brightness=value)
        if held:
            ring(d,183,lerp(501,433,progress)); ring(d,655,lerp(349,287,progress))
    elif scene==3:
        board(d,(405,204,1190,569),page=1 if u>1.2 else 0)
        box(d,(83,365,350,535),fill='#e1e6ed',outline='#cdd4df')
        travel=curve((u-.4)/1.2)
        ring(d,lerp(278,153,travel),418); ring(d,lerp(278,153,travel),468)
        text(d,(104,276),'Two fingers',25); text(d,(108,315),'← swipe',24,fill=MUTED)
    elif scene==4:
        box(d,(75,208,306,565)); text(d,(96,230),'Feature library',22)
        for j,label in enumerate(['Media','Website','Shortcut']):
            box(d,(94,282+j*71,286,335+j*71),fill='#f0f3f7',radius=12); text(d,(111,298+j*71),label,20)
        box(d,(350,208,1194,565),fill='#e5eaf1',radius=26)
        box(d,(371,230,735,374)); text(d,(394,254),'Brightness',24)
        box(d,(752,230,1172,374)); text(d,(777,254),'Volume',24)
        box(d,(371,393,735,540)); text(d,(394,419),'Media',24)
        target=(754,393,1172,540)
        if .5<u<1.9:
            box(d,target,fill='#d4e5ff',outline=BLUE,width=2); text(d,(832,451),'Drop here',22,fill=BLUE)
            a=curve((u-.5)/1.4); x=lerp(120,790,a); y=lerp(355,420,a)
            box(d,(x,y,x+180,y+57),fill='#edf5ff',outline=BLUE,radius=12); text(d,(x+17,y+17),'Website',20); cursor(d,x+80,y+40)
        elif 1.9<=u<3.4:
            a=curve((u-2.1)/1.1); right=lerp(1025,1172,a)
            box(d,(754,393,right,540),outline=BLUE,width=2); text(d,(777,419),'Website',24); cursor(d,right-6,531)
        elif u>=3.4:
            a=curve((u-3.4)/1.1); x=lerp(754,150,a); y=lerp(393,510,a)
            if u<4.6:
                box(d,(x,y,x+180,y+57),fill='#edf5ff',outline=BLUE,radius=12); text(d,(x+17,y+17),'Website',20); cursor(d,x+80,y+40)
            text(d,(795,448),'Space closes automatically',20,fill=MUTED)
    else:
        media(d,(104,210,1176,535),title='Music app  ·  YouTube Music (Chrome installed)')
        text(d,(130,308),'Seeking depends on the player’s accessibility support.',22,fill=MUTED)
        text(d,(130,357),'Choose another installed music app in Settings.',22,fill=MUTED)
        if u>3.2:
            box(d,(786,447,1146,512),fill=BLUE,radius=16); text(d,(813,465),'Release ⌥ → back to work',22,fill='white')
    d.line((64,619,1216,619),fill='#d7dde6',width=1)
    text(d,(64,641),KOREAN[scene],20,ko=True)
    for j in range(6): box(d,(64+j*36,694,88+j*36,698),fill=BLUE if j==scene else '#cbd2dc',radius=2)
    text(d,(1127,680),f'{int(t):02d} / 30s',15,fill=MUTED,mono=True)
    return im


def main():
    FRAMES.mkdir(parents=True,exist_ok=True); ASSETS.mkdir(parents=True,exist_ok=True)
    for i in range(FPS*SECONDS):
        render(i/FPS).save(FRAMES/f'{i:04d}.png',optimize=True)
    # One stable palette prevents frame-to-frame color flicker.
    sheet=Image.new('RGB',(960,540))
    for j,t in enumerate([0,5,10,15,20,25]): sheet.paste(render(t+2).resize((320,270)),((j%3)*320,(j//3)*270))
    palette=sheet.quantize(colors=192,method=Image.Quantize.MEDIANCUT)
    gif=[]
    for i in range(300):
        frame=render(i/10).resize((960,540),Image.Resampling.LANCZOS)
        gif.append(frame.quantize(palette=palette,dither=Image.Dither.NONE))
    gif[0].save(ASSETS/'quickstart.gif',save_all=True,append_images=gif[1:],duration=100,loop=0,optimize=True,disposal=1)
    render(11.6).save(ASSETS/'quickstart-poster.png',optimize=True)
    with Image.open(ASSETS/'quickstart.gif') as image:
        duration=0
        for i in range(image.n_frames): image.seek(i); duration+=image.info['duration']
        assert duration==30000, duration
        print(f'GIF: {image.n_frames} frames, {duration/1000:.2f}s, {(ASSETS/"quickstart.gif").stat().st_size:,} bytes')
if __name__=='__main__': main()
