#!/bin/sh
# Gancho, Kaileh and Dracoxinia bodies (run 2026-10-21 b). Usage: sh build.sh gancho|kaileh|dracoxinia [tag] [extra args]
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
R=A:/Python/woa
W=$R/work/lemondev/2026-10-21b-three-heroes/bodies
D=$R/work/downloads/sf_heroes
n=$1; tag=${2:-p1}; shift 2 2>/dev/null
cd $R
case $n in
gancho) set -- --src="$(ls $D/gancho/*.fbx)" --name=gancho --height=1.95 --faces=30000 --tex=2048 "$@" ;;
kaileh) set -- --src="$W/src/kaileh_painted.blend" --name=kaileh --height=2.3 --faces=50000 --tex=2048 "$@" ;;
dracoxinia) set -- --src="$W/src/dracoxinia_painted.blend" --name=dracoxinia --height=2.0 --faces=50000 --tex=2048 "$@" ;;
esac
"$B" -b --factory-startup --python tools/blender/hero_body.py -- "$@" --preview=$W/prev_${n}_$tag --out=${OUTDIR:-$R/assets/characters/heroes17}/$n.glb > $W/logs/${n}_$tag.txt 2>&1
grep "imported\|kept\|rig\|cut\|unmix\|arm split\|hands:\|hand [LR]\|hand\.\|reach:\|cloth:\|rigid\|Traceback\|Error\|wrote\|scaled\|weights" $W/logs/${n}_$tag.txt | grep -v HIP
