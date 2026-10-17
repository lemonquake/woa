#!/bin/sh
# Rebuild the new heroes' bodies (run 2026-10-17 e commands) with the current body pipeline: the hand fit and the unmix;
# the arm split is off (EXTRA). Airah is built from the base body instead (tools/blender/airah_prep.py, run 2026-10-18 e).
# Usage: sh work/rebuild_new5.sh [out_dir] [names...]
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
OUT=${1:-A:/Python/woa/assets/characters/heroes17}
shift 2>/dev/null
NAMES=${*:-"emelrich feran burak ghorman_beast"}
LOG=${LOG:-A:/Python/woa/work/lemondev/2026-10-18e-mocap2/rebuild}
EXTRA=${EXTRA:-"--split=0"}            # the arm split and --reach=1 tore these models apart (run 2026-10-18 e)
cd /a/Python/woa; mkdir -p $LOG
D=A:/Python/woa/work/downloads/sf_heroes
for n in $NAMES; do
  case $n in
  emelrich) set -- --src=$D/bulky_knight.glb --name=emelrich --height=1.95 --faces=34000 --drop="Axe|pasted" --joints=tools/blender/joints/bulky_knight.json --hue=345:42:45:0.35:3.2 --gray=1.35 ;;
  feran) set -- --src=$D/assassin_character_model.glb --name=feran --height=1.82 --faces=34000 --drop="^cloth13_" --cloth="^cloth" ;;
  burak) set -- --src=$D/burak.glb --name=burak --norig --joints=tools/blender/joints/burak.json --move="^Object_1[468]$:0,0,-0.082" --rigid="hips:ball:0.23,-0.125,0.915,0.115" --height=1.88 --faces=42000 --tex=2048 --drop="^Axe [LR]" ;;
  airah) set -- --src=$D/airah.glb --name=airah --joints=tools/blender/joints/airah.json --drop="lampu" --capture --rigid="hips:cap:-0.6,0.06,0.95,-0.55,0.73,0.72,0.11;hand.R:cap:-0.665,-0.066,1.30,-0.62,-0.085,1.35,0.034" --height=1.76 --faces=60000 --tex=2048 ;;
  ghorman_beast) set -- --src=$D/ghorman_transform.glb --name=ghorman_beast --norig --posture --keep="mace" --joints=tools/blender/joints/troll.json --rigid="hand.R:cap:-48,-15,68,-52,-55,42,11;hand.R:ball:-55,-75,27,33;hips:cap:2,20,72,8,62,72,12" --height=2.4 --faces=30000 --tex=2048 ;;
  *) echo "unknown $n"; continue ;;
  esac
  "$B" -b --factory-startup --python tools/blender/hero_body.py -- "$@" $EXTRA --out=$OUT/$n.glb > $LOG/$n.txt 2>&1
  echo "== $n"; grep "cut\|unmix\|arm split\|hands:\|hand [LR]\|reach:\|cloth:\|Traceback\|Error:\|wrote" $LOG/$n.txt | grep -v HIP | tail -12
done
