#!/bin/sh
# Blackfire and Thyrandael bodies (run 2026-10-21). Usage: sh build.sh blackfire|thyrandael [pass tag] [extra args]
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
R=A:/Python/woa
W=$R/work/lemondev/2026-10-21-blackfire-thyrandael/bodies
D=$R/work/downloads/sf_heroes
BF=$(ls $D/blackfire_the_unfallen/source/x/*.fbx)
TH=$(ls $D/thyrandael_the_forsaken_seraph/source/x/*.fbx)
n=$1; tag=${2:-p1}; shift 2 2>/dev/null
cd $R
case $n in
blackfire) set -- --src="$BF" --name=blackfire --height=2.05 --faces=44000 --tex=2048 --bake \
  --cut="-0.29,-0.163,-0.08,0.006,0.06,0.428;-0.26,-0.195,-0.07,0.0,-0.01,0.06;cap:-0.216,-0.037,0.40,-0.216,-0.037,0.50,0.0095;-0.232,-0.197,-0.07,-0.019,0.494,0.528" \
  --joints=tools/blender/joints/blackfire.json --reach=1 --split=0 --rigid="hand.R:ball:-0.22,-0.035,0.468,0.045" "$@" ;;
thyrandael) set -- --src="$TH" --name=thyrandael --height=2.15 --faces=60000 --tex=2048 --bake   --cut="$(cat $W/th_cut.txt)" --rigid="$(cat $W/th_rigid.txt)"   --joints=tools/blender/joints/thyrandael.json --reach=1 "$@" ;;
esac
mkdir -p $W/logs
"$B" -b --factory-startup --python tools/blender/hero_body.py -- "$@" --preview=$W/prev_${n}_$tag --out=${OUTDIR:-$R/assets/characters/heroes17}/$n.glb > $W/logs/${n}_$tag.txt 2>&1
grep "cut\|unmix\|arm split\|hands:\|hand [LR]\|hand\.\|reach:\|cloth:\|rigid\|Traceback\|Error\|wrote\|scaled" $W/logs/${n}_$tag.txt | grep -v HIP
