# "Without SkinShare / With SkinShare" showcase: GMod-style red ERROR vs the real skin, diagonal split.
# usage: python3 beforeafter.py <scratchpad> <reference image with the ERROR model>
import subprocess, sys
D = sys.argv[1]; S = f"{D}/ss2"; O = f"{D}/ba"
subprocess.run(["mkdir", "-p", O], check=True)
FB, FM = "/usr/share/fonts/TTF/Roboto-Black.ttf", "/usr/share/fonts/TTF/Roboto-Medium.ttf"
W, H = 1920, 1080

def m(*a): subprocess.run(["magick", *map(str, a)], check=True)

# background: the map from the C-menu screenshot, without the menus around it
m(f"{S}/s1.jpg", "-crop", "1260x709+130+60", "+repage", "-resize", f"{W}x{H}!", "-blur", "0x2", f"{O}/bg.png")

# Miku: preview panel of the menu screenshot, background flood-filled away from the corners
m(f"{S}/s6.jpg", "-crop", "480x560+496+262", "+repage", "-alpha", "set", "-fuzz", "4%", "-fill", "none",
  "-draw", "color 0,0 floodfill", "-draw", "color 479,0 floodfill", "-draw", "color 0,559 floodfill",
  "-draw", "color 479,559 floodfill",
  # the two background pockets enclosed between hair and body (found with connected-components)
  "-draw", "color 153,404 floodfill", "-draw", "color 326,397 floodfill",
  # shave the dark keying fringe: erode the alpha a bit and soften it
  "(", "+clone", "-alpha", "extract", "-morphology", "Erode", "Disk:1.5", "-blur", "0x0.8", ")",
  "-compose", "copy_opacity", "-composite", f"{O}/miku_raw.png")
# drop small speckle islands left under the feet
m(f"{O}/miku_raw.png", "-alpha", "extract", "-threshold", "30%", "-define", "connected-components:area-threshold=300",
  "-define", "connected-components:mean-color=true", "-connected-components", "8", f"{O}/miku_keep.png")
m(f"{O}/miku_raw.png", "(", f"{O}/miku_raw.png", "-alpha", "extract", f"{O}/miku_keep.png", "-compose", "multiply", "-composite", ")",
  "-compose", "copy_opacity", "-composite", "-trim", "+repage", "-resize", "x760", f"{O}/miku.png")

# the real GMod ERROR model, keyed out of the user's reference image (red-dominant pixels of its left panel)
REF = sys.argv[2]
m(REF, "-crop", "270x225+35+80", "+repage", "-alpha", "set",
  "(", "+clone", "-fx", "(r-g > 0.22 && r-b > 0.18) ? 1 : 0", "-colorspace", "gray",
  "-morphology", "Close", "Disk:1", "-morphology", "Open", "Disk:1", "-blur", "0x0.7", ")",
  "-compose", "copy_opacity", "-composite", "-trim", "+repage",
  "-filter", "Lanczos", "-resize", "x600", "-unsharp", "0x1", f"{O}/error.png")

# halves: left desaturated/red-tinted with ERROR, right normal with Miku; split along a diagonal
m(f"{O}/bg.png", "-modulate", "80,40", "-fill", "#400000", "-colorize", "18%",
  "(", "-size", "640x60", "xc:none", "-fill", "#00000070", "-draw", "ellipse 320,30 300,26 0,360", "-blur", "0x10", ")",
  "-geometry", "+170+860", "-composite",
  f"{O}/error.png", "-geometry", "+150+300", "-composite", f"{O}/left.png")
m(f"{O}/bg.png", "(", "-size", "520x70", "xc:none", "-fill", "#00000070", "-draw", "ellipse 260,35 230,28 0,360", "-blur", "0x10", ")",
  "-geometry", "+1225+872", "-composite",
  f"{O}/miku.png", "-gravity", "northwest", "-geometry", "+1320+150", "-composite", f"{O}/right.png")
# diagonal mask: right side = white
m("-size", f"{W}x{H}", "xc:black", "-fill", "white", "-draw", f"polygon 1060,0 {W},0 {W},{H} 860,{H}", f"{O}/mask.png")
m(f"{O}/left.png", f"{O}/right.png", f"{O}/mask.png", "-composite",
  # the "/" slash
  "-stroke", "white", "-strokewidth", "14", "-draw", f"line 1060,0 860,{H}",
  "-stroke", "#3C96F5", "-strokewidth", "4", "-draw", f"line 1074,0 874,{H}", "-stroke", "none",
  # labels
  "-font", FB, "-pointsize", "64", "-fill", "#0b0d12b0", "-draw", "roundrectangle 60,50 760,150 24,24",
  "-fill", "#ff5050", "-annotate", "+92+124", "WITHOUT SKINSHARE",
  "-fill", "#0b0d12b0", "-draw", "roundrectangle 1180,50 1860,150 24,24",
  "-fill", "#7CC4FF", "-annotate", "+1222+124", "WITH SKINSHARE",
  "-font", FM, "-pointsize", "34", "-fill", "#0b0d12b0", "-draw", "roundrectangle 60,960 820,1030 20,20",
  "-fill", "white", "-annotate", "+88+1007", "Your friends see a giant ERROR",
  "-fill", "#0b0d12b0", "-draw", "roundrectangle 1140,960 1860,1030 20,20",
  "-fill", "white", "-annotate", "+1168+1007", "Everyone sees your real skin",
  "-quality", "92", f"{O}/before_after.jpg")
print(f"{O}/before_after.jpg")
