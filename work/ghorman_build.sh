B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"; P=A:/Python/woa/work/lemondev/2026-10-17f-ghorman-azrael
G="A:/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
cd /a/Python/woa
"$B" -b --factory-startup --python tools/blender/ghorman_prep.py -- --out=A:/Python/woa/work/ghorman_src 2>&1 | grep -E "rror:|Traceback|saved"
"$B" -b --factory-startup --python tools/blender/hero_body.py -- --src=A:/Python/woa/work/ghorman_src/ghorman_src.blend --name=ghorman --body_piece="^ghorman_body" --height=2.05 --faces=80000 --tex=2048 --reach=1 --cloth="^no_hanging_cloth$" --out=A:/Python/woa/assets/characters/heroes17/ghorman.glb > $P/ghorman_build.txt 2>&1
grep "wrote" $P/ghorman_build.txt
"$G" --headless --path . --import > $P/import3.txt 2>&1
