#!/bin/sh
# Rebuild the own hero bodies with the 2026-10-18 QA fixes (hand fit, fist, cut remnants, arm unmix, hand lock).
# Usage: sh work/rebuild_qa.sh [out_dir] [names...]   (default out: the game's heroes17 folder, all bodies below)
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
OUT=${1:-A:/Python/woa/assets/characters/heroes17}
shift 2>/dev/null
NAMES=${*:-"azrael ezee azrin caziel"}
LOG=A:/Python/woa/work/lemondev/2026-10-18-model-qa/rebuild
cd /a/Python/woa; mkdir -p $LOG
D=A:/Python/woa/work/downloads/sf_heroes
CAZ=$(ls $D/caziel/source/x/*.fbx); EZ=$(ls $D/fallen-paladin-in-corrupted-black-plate-armor/source/x/*.fbx); AZ=$(ls $D/azrin/source/x/*.fbx)
for n in $NAMES; do
  case $n in
  azrael) set -- --src=A:/Python/woa/work/azrael_src/azrael_src.blend --name=azrael --height=1.8 --faces=50000 --tex=2048 --glide=idle_staff --reach=1 --fist ;;
  ezee) set -- --src="$EZ" --name=ezee --yaw=-90 --height=1.9 --faces=40000 --tex=2048 --bake --cut="0.175,0.27,-0.24,-0.135,-0.50,-0.30;0.15,0.24,-0.26,-0.10,-0.30,-0.05;0.13,0.185,-0.26,-0.12,-0.075,0.135;0.10,0.20,-0.26,-0.12,-0.08,-0.02" --joints=tools/blender/joints/fallen_paladin.json --reach=1 ;;
  azrin) set -- --src="$AZ" --name=azrin --height=1.78 --faces=52000 --tex=2048 --bake --hue=275:356:80:1.6:1.1 --glide=idle_staff --cut="cap:-0.19,-0.27,1.0,-0.015,-0.075,-0.01,0.024;ball:-0.185,-0.245,0.885,0.115" --joints=tools/blender/joints/azrin.json --reach=1 ;;
  caziel) set -- --src="$CAZ" --name=caziel --height=1.85 --faces=40000 --tex=2048 --bake --gray=1.45 --joints=tools/blender/joints/caziel.json --reach=1 ;;
  *) echo "unknown $n"; continue ;;
  esac
  "$B" -b --factory-startup --python tools/blender/hero_body.py -- "$@" --out=$OUT/$n.glb > $LOG/$n.txt 2>&1
  grep "cut\|unmix\|hands:\|hand [LR]\|reach:\|cloth:\|Traceback\|Error:\|wrote" $LOG/$n.txt | grep -v HIP
done
