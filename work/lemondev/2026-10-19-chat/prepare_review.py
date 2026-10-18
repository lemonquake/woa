"""Prepare equal-size, deterministic anonymous excerpts for the text critic."""
import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
run = Path(__file__).resolve().parent
versions = [
    json.loads((run / 'before.json').read_text(encoding='utf-8-sig')),
    json.loads((ROOT / 'bot_trashtalk_chat_lines.json').read_text(encoding='utf-8')),
]
order = [0, 1]
random.Random(429).shuffle(order)
packet = '''# Anonymous chat comparison

Criterion: choose the set that better resembles short, natural in-match Filipino/Taglish and English trashtalk. One thought per line; profanity and clipped spelling are welcome. Occasional long gameplay complaints are allowed. Avoid repeated prefix/setup/suffix combinations and forced meme punchlines. Judge category fit too.

User style reference: matic na yan; potakte; ampota; bwisit ka ha (revenge kill); ulol!; tangaaaaaa; pota weak; apaka basic ampota; nakakasuka laro mo lods (teammate); carry ampota baog.

Each version has ten corresponding pools and eight randomly sampled entries per pool (seed 429). This is standalone text; do not assume runtime selection or triggers. Both texts use the same sample size. Sources, builder rationale, metadata and candidate identity are excluded.

'''
for label, index in zip(('A', 'B'), order):
    packet += f'## Version {label}\n\n'
    rng = random.Random(429)
    for key, lines in versions[index]['chat_lines'].items():
        packet += f'### {key}\n\n'
        packet += '\n'.join('- ' + line for line in rng.sample(lines, 8)) + '\n\n'
(run / 'review_packet.md').write_text(packet, encoding='utf-8', newline='\n')
mapping = {label: ('baseline' if index == 0 else 'candidate') for label, index in zip(('A', 'B'), order)}
(run / 'review_mapping.json').write_text(json.dumps(mapping, indent=2) + '\n', encoding='utf-8', newline='\n')
