# Builds Workshop showcase images: blurred backdrop, title band, zoomed menu crop, highlight boxes + labels.
# usage: python3 showcase.py <screenshots dir> <out dir> <spec.json>
# spec: [[name, [x,y,w,h crop], title, subtitle, [[x0,y0,x1,y1 (crop px), label, "left"|"right"], ...]], ...]
import subprocess, sys, os

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
FB, FM = "/usr/share/fonts/TTF/Roboto-Black.ttf", "/usr/share/fonts/TTF/Roboto-Medium.ttf"
HL, ACCENT = "#FFC83D", "#3C96F5"
W, H, BAND = 1920, 1080, 170

def crop_to_canvas(crop):
    cx, cy, cw, ch = crop
    k = min((W - 880) / cw, (H - BAND - 30) / ch)  # ~440 px free each side for labels
    sw, sh = round(cw * k), round(ch * k)
    return k, (W - sw) // 2, BAND + (H - BAND - 30 - sh) // 2, sw, sh

def build(name, crop, title, sub, marks, out):
    src = f"{SRC}/{name}.jpg"
    k, ox, oy, sw, sh = crop_to_canvas(crop)
    cx, cy, cw, ch = crop
    cmd = ["magick",
           # backdrop: the same screenshot, blurred and darkened
           src, "-resize", f"{W}x{H}^", "-gravity", "center", "-extent", f"{W}x{H}", "+gravity",
           "-blur", "0x18", "-fill", "#0b0d12", "-colorize", "55%",
           # title band
           "-fill", "#0b0d12d0", "-draw", f"rectangle 0,0 {W},{BAND - 20}",
           "-fill", ACCENT, "-draw", f"rectangle 0,{BAND - 24} {W},{BAND - 20}",
           "-font", FB, "-pointsize", "60", "-fill", "white", "-annotate", "+60+82", title,
           "-font", FM, "-pointsize", "30", "-fill", "#c8ccd4", "-annotate", "+62+128", sub,
           # zoomed crop with a shadow
           "(", src, "-crop", f"{cw}x{ch}+{cx}+{cy}", "+repage", "-resize", f"{sw}x{sh}!",
           "(", "+clone", "-background", "black", "-shadow", "70x14+0+8", ")", "+swap",
           "-background", "none", "-layers", "merge", "+repage", ")",
           "-geometry", f"+{ox - 14}+{oy - 6}", "-composite"]
    for (x0, y0, x1, y1, label, side) in marks:
        X0, Y0, X1, Y1 = ox + x0 * k, oy + y0 * k, ox + x1 * k, oy + y1 * k
        cmd += ["-fill", "none", "-stroke", HL, "-strokewidth", "6",
                "-draw", f"roundrectangle {X0:.0f},{Y0:.0f} {X1:.0f},{Y1:.0f} 14,14", "-stroke", "none"]
        if label:
            # label pill in the side margin, with a line to the box
            pw = 17 * len(label) + 44
            py = (Y0 + Y1) / 2
            px = ox - pw - 40 if side == "left" else ox + sw + 40
            px = max(16, min(W - pw - 16, px))
            ax = X0 if side == "left" else X1
            lx = px + pw if side == "left" else px
            cmd += ["-stroke", HL, "-strokewidth", "5", "-draw", f"line {lx:.0f},{py:.0f} {ax:.0f},{py:.0f}",
                    "-stroke", "none", "-fill", HL, "-draw", f"circle {ax:.0f},{py:.0f} {ax + 9:.0f},{py:.0f}",
                    "-draw", f"roundrectangle {px:.0f},{py - 30:.0f} {px + pw:.0f},{py + 30:.0f} 30,30",
                    "-font", FB, "-pointsize", "30", "-fill", "#111111",
                    "-annotate", f"+{px + 20:.0f}+{py + 11:.0f}", label]
    cmd += ["-quality", "92", out]
    subprocess.run(cmd, check=True)

if __name__ == "__main__":
    import json
    for i, (name, crop, title, sub, marks) in enumerate(json.load(open(sys.argv[3])), 1):
        build(name, tuple(crop), title, sub, marks, f"{OUT}/screenshot{i}.jpg")
        print("ok", i, name)
