#!/bin/sh
# Does learning help? Train bot memories, then play each learned memory against fresh bots, both sides of the map.
#   sh tests/tools/learn_ab.sh [trainers=3] [games_each=3] [minutes=35] [out=work/learn_ab]
# Training: each trainer plays games_each 5 v 5 bot games in a row with its own memory file (both teams learning).
# Evaluation: each memory plays 2 games as Ancient Light against fresh Black Sun bots and 2 games the other way
# round (--learn_teams 1,0 / 0,1, memory not saved). Results land in out/; summarise with grep "totals\|won" out/eval_*.
G="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
T=${1:-3}
K=${2:-3}
M=${3:-35}
OUT=${4:-work/learn_ab}
cd /a/Python/woa
mkdir -p "$OUT"
i=1
while [ $i -le $T ]; do
  seeds=""
  k=1
  while [ $k -le $K ]; do
    s=$((i * 100 + k))
    seeds="$seeds${seeds:+,}$s"
    k=$((k + 1))
  done
  rm -f "$OUT/mem_$i.json"
  "$G" --headless --path . -s tests/tools/bot_game.gd -- --seeds=$seeds --min=$M --learn="$OUT/mem_$i.json" \
    --out="$OUT/train_$i.txt" > /dev/null 2>&1 &
  i=$((i + 1))
done
wait
i=1
while [ $i -le $T ]; do
  "$G" --headless --path . -s tests/tools/bot_game.gd -- --seeds=901,902 --min=$M --learn="$OUT/mem_$i.json" \
    --learn_teams=1,0 --no_save=1 --out="$OUT/eval_${i}_dawn.txt" > /dev/null 2>&1 &
  "$G" --headless --path . -s tests/tools/bot_game.gd -- --seeds=901,902 --min=$M --learn="$OUT/mem_$i.json" \
    --learn_teams=0,1 --no_save=1 --out="$OUT/eval_${i}_dusk.txt" > /dev/null 2>&1 &
  i=$((i + 1))
done
wait
# the same seeds with no learning on either side, as the control
"$G" --headless --path . -s tests/tools/bot_game.gd -- --seeds=901,902 --min=$M --out="$OUT/control.txt" > /dev/null 2>&1
echo "learn_ab done: $OUT"
