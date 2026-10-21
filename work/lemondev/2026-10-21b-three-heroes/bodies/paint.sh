#!/bin/sh
# sh paint.sh kaileh|dracoxinia [ao 0/1] [views]: paint_prep then preview renders (paint attribute and full material)
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
R=A:/Python/woa; W=$R/work/lemondev/2026-10-21b-three-heroes/bodies
n=$1; ao=${2:-1}; views=${3:-front,back,torso,head,legs,hand_r}
case $n in kaileh) src=$(ls $R/work/downloads/sf_heroes/lord_kaileh/*.fbx);; dracoxinia) src=$(ls $R/work/downloads/sf_heroes/dracoxinia/*.fbx);; esac
cd $R
"$B" -b --factory-startup --python tools/blender/paint_prep.py -- --src="$src" --out=$W/src/${n}_painted --rules=$W/rules/$n.py --ao=$ao --low=${LOW:-0} > $W/logs/paint_$n.txt 2>&1
grep "paint_prep\|Error\|Traceback" $W/logs/paint_$n.txt | tail -6
ATTR=paint "$B" -b --factory-startup --python $W/rest_look.py -- $W/src/${n}_painted.blend $W/look/${n}_paint $views > $W/logs/look_paint_$n.txt 2>&1
"$B" -b --factory-startup --python $W/rest_look.py -- $W/src/${n}_painted.blend $W/look/${n}_mat $views > $W/logs/look_mat_$n.txt 2>&1
cd $W/look && python -I -c "
from PIL import Image
import sys
n='$n'; views='$views'.split(',')
for kind in ('paint','mat'):
    ims=[Image.open(f'{n}_{kind}_{v}.png').convert('RGB') for v in views]
    c=3; r=(len(ims)+2)//3
    s=Image.new('RGB',(900*c,900*r))
    for i,im in enumerate(ims): s.paste(im,((i%c)*900,(i//c)*900))
    s.thumbnail((2100,1400)); s.save(f'{n}_{kind}_sheet.png')
"
