B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"; P=A:/Python/woa/work/lemondev/2026-10-17f-ghorman-azrael/rebuild
G="A:/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
cd /a/Python/woa; mkdir -p $P
D=A:/Python/woa/work/downloads/sf_heroes
CAZ=$(ls $D/caziel/source/x/*.fbx); EZ=$(ls $D/fallen-paladin-in-corrupted-black-plate-armor/source/x/*.fbx); AZ=$(ls $D/azrin/source/x/*.fbx)
"$B" -b --factory-startup --python tools/blender/hero_body.py -- --src="$CAZ" --name=caziel --height=1.85 --faces=40000 --tex=2048 --bake --gray=1.45 --joints=tools/blender/joints/caziel.json --reach=1 --out=A:/Python/woa/assets/characters/heroes17/caziel.glb > $P/caziel.txt 2>&1
grep "reach\|wrote\|Traceback\|Error:" $P/caziel.txt | grep -v HIP
"$B" -b --factory-startup --python tools/blender/hero_body.py -- --src="$EZ" --name=ezee --yaw=-90 --height=1.9 --faces=40000 --tex=2048 --bake --cut="0.175,0.27,-0.24,-0.135,-0.50,-0.30;0.15,0.24,-0.26,-0.10,-0.30,-0.05;0.13,0.185,-0.26,-0.12,-0.075,0.135;0.10,0.20,-0.26,-0.12,-0.08,-0.02" --joints=tools/blender/joints/fallen_paladin.json --reach=1 --out=A:/Python/woa/assets/characters/heroes17/ezee.glb > $P/ezee.txt 2>&1
grep "reach\|wrote\|Traceback\|Error:" $P/ezee.txt | grep -v HIP
"$B" -b --factory-startup --python tools/blender/hero_body.py -- --src="$AZ" --name=azrin --height=1.78 --faces=52000 --tex=2048 --bake --hue=275:356:80:1.6:1.1 --glide=idle_staff --cut="cap:-0.19,-0.27,1.0,-0.015,-0.075,-0.01,0.024;ball:-0.185,-0.245,0.885,0.115" --joints=tools/blender/joints/azrin.json --reach=1 --out=A:/Python/woa/assets/characters/heroes17/azrin.glb > $P/azrin.txt 2>&1
grep "reach\|wrote\|Traceback\|Error:" $P/azrin.txt | grep -v HIP
"$G" --headless --path . --import > $P/import.txt 2>&1
echo done
