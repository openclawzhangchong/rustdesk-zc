"""显示拓扑快照探针（采集兼容验收用）。

用法：python test/probe-topo.py
打印所有 ACTIVE 显示设备：名称 | 驱动描述 | 分辨率@刷新率 位置 (PRIMARY 标记)。
退出码：0 = 存在间接显示（IddDriver / Virtual Display）活动；1 = 仅物理输出。
"""
import ctypes as c
from ctypes import wintypes as w
import sys

u = c.windll.user32


class DM(c.Structure):
    _fields_ = [("devname", w.WCHAR * 32), ("specver", w.WORD), ("driverversion", w.WORD),
                ("size", w.WORD), ("driverextra", w.WORD), ("fields", w.DWORD),
                ("posx", w.LONG), ("posy", w.LONG), ("orient", w.DWORD), ("fixedoutput", w.DWORD),
                ("color", w.SHORT), ("duplex", w.SHORT), ("yres", w.SHORT), ("ttoption", w.SHORT),
                ("collate", w.SHORT), ("formname", w.WCHAR * 32), ("logpixels", w.WORD),
                ("bitsperpel", w.DWORD), ("pelswidth", w.DWORD), ("pelsheight", w.DWORD),
                ("displayflags", w.DWORD), ("displayfreq", w.DWORD), ("icmmethod", w.DWORD),
                ("icmintent", w.DWORD), ("mediatype", w.DWORD), ("dithertype", w.DWORD),
                ("reserved1", w.DWORD), ("reserved2", w.DWORD), ("panningwidth", w.DWORD),
                ("panningheight", w.DWORD)]


class DD(c.Structure):
    _fields_ = [("cb", w.DWORD), ("devname", w.WCHAR * 32), ("devstring", w.WCHAR * 128),
                ("flags", w.DWORD), ("devid", w.WCHAR * 128), ("devkey", w.WCHAR * 128)]


indirect = False
i = 0
while True:
    d = DD()
    d.cb = c.sizeof(DD)
    if not u.EnumDisplayDevicesW(None, i, c.byref(d), 0):
        break
    if d.flags & 0x1:
        desc = d.devstring
        if 'IddDriver' in desc or 'Virtual Display' in desc:
            indirect = True
        dm = DM()
        dm.size = c.sizeof(DM)
        ok = u.EnumDisplaySettingsExW(d.devname, -2, c.byref(dm), 0)
        prim = ' PRIMARY' if d.flags & 0x4 else ''
        if ok:
            print(f"{d.devname} | {desc[:48]} | {dm.pelswidth}x{dm.pelsheight}"
                  f"@{dm.displayfreq} pos({dm.posx},{dm.posy}){prim}")
        else:
            print(f"{d.devname} | {desc[:48]} | NO CURRENT MODE{prim}")
    i += 1
sys.exit(0 if indirect else 1)