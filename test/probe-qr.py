"""微信登录二维码 GDI 可读性探针（采集兼容验收用）。

用法：python test/probe-qr.py [标签] [输出目录]
退出码：0 = 二维码可读（darkpx > 500）；1 = 白窗/空白；2 = 没有可见微信窗口。
依赖：pip install pillow psutil
注意：先把微信窗口移入屏内再抓——屏外黑边会被计入 darkpx 造成假阳性。
"""
import ctypes
import ctypes.wintypes as wt
import os
import sys
import time

from PIL import Image
import psutil

tag = sys.argv[1] if len(sys.argv) > 1 else 'x'
outdir = sys.argv[2] if len(sys.argv) > 2 else os.environ.get('TEMP', '.')
u32 = ctypes.windll.user32
gdi = ctypes.windll.gdi32


class BIH(ctypes.Structure):
    _fields_ = [('biSize', wt.DWORD), ('biWidth', wt.LONG), ('biHeight', wt.LONG),
                ('biPlanes', wt.WORD), ('biBitCount', wt.WORD), ('biCompression', wt.DWORD),
                ('biSizeImage', wt.DWORD), ('biXPelsPerMeter', wt.LONG),
                ('biYPelsPerMeter', wt.LONG), ('biClrUsed', wt.DWORD),
                ('biClrImportant', wt.DWORD)]


wx = {p.pid for p in psutil.process_iter(['name'])
      if p.info['name'] and p.info['name'].lower() in ('weixin.exe', 'wechat.exe')}
tops = []
CB = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)


def cb(h, l):
    pid = wt.DWORD()
    u32.GetWindowThreadProcessId(h, ctypes.byref(pid))
    if pid.value in wx and u32.IsWindowVisible(h):
        r = wt.RECT()
        u32.GetWindowRect(h, ctypes.byref(r))
        if r.right - r.left > 0:
            tops.append((h, r))
    return True


u32.EnumWindows(CB(cb), 0)
if not tops:
    print(tag, 'NO WECHAT WINDOW')
    sys.exit(2)
h, r = tops[0]
u32.SetWindowPos(h, 0, 100, 100, 0, 0, 0x1 | 0x4 | 0x10)
time.sleep(0.5)
u32.GetWindowRect(h, ctypes.byref(r))
w, hh = r.right - r.left, r.bottom - r.top
scr = u32.GetDC(0)
mem = gdi.CreateCompatibleDC(scr)
bmp = gdi.CreateCompatibleBitmap(scr, w, hh)
gdi.SelectObject(mem, bmp)
gdi.BitBlt(mem, 0, 0, w, hh, scr, r.left, r.top, 0x40CC0020)
bmi = BIH()
bmi.biSize = ctypes.sizeof(BIH)
bmi.biWidth = w
bmi.biHeight = -hh
bmi.biPlanes = 1
bmi.biBitCount = 32
buf = (ctypes.c_ubyte * (w * hh * 4))()
gdi.GetDIBits(mem, bmp, 0, hh, buf, ctypes.byref(bmi), 0)
im = Image.frombytes('RGBA', (w, hh), bytes(buf), 'raw', 'BGRA').convert('RGB')
path = os.path.join(outdir, f'qr-{tag}.png')
im.save(path)
px = im.load()
dark = sum(1 for j in range(0, hh, 2) for i in range(0, w, 2) if sum(px[i, j]) < 200)
print(tag, 'hwnd', h, f'{w}x{hh}', 'darkpx', dark,
      '(QR present)' if dark > 500 else '(blank/white)', '->', path)
u32.ReleaseDC(0, scr)
sys.exit(0 if dark > 500 else 1)