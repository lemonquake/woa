"""Check the data contract and record before/after measurements."""
import collections
import hashlib
import json
import re
import statistics
from pathlib import Path

run = Path(__file__).resolve().parent
path = run.parents[2] / 'bot_trashtalk_chat_lines.json'
before = json.loads((run / 'before.json').read_text(encoding='utf-8-sig'))
raw = path.read_bytes()
after = json.loads(raw.decode('utf-8'))
assert list(after) == list(before), 'Top-level keys changed'
assert list(after['metadata']) == list(before['metadata']), 'Metadata keys changed'
assert list(after['chat_lines']) == list(before['chat_lines']), 'Category keys/order changed'
lines = [line for pool in after['chat_lines'].values() for line in pool]
assert all(isinstance(pool, list) and pool for pool in after['chat_lines'].values())
assert all(isinstance(line, str) and line.strip() == line and line for line in lines)
assert all('\n' not in line and '\r' not in line for line in lines)
counts = {key: len(pool) for key, pool in after['chat_lines'].items()}
assert counts == after['metadata']['category_breakdown']
assert len(counts) == after['metadata']['categories_count'] == 10
assert sum(counts.values()) == after['metadata']['total_lines'] == len(lines)
normalized = [re.sub(r'[^a-z0-9]', '', line.casefold()) or line for line in lines]
assert len(normalized) == len(set(normalized)), 'Duplicate or punctuation/case-only variant'
assert max(map(len, lines)) <= 110
assert sum(len(line.split()) <= 6 for line in lines) / len(lines) >= .8
assert all(not any(ord(char) < 32 for char in line) for line in lines)
report = {'sha256': hashlib.sha256(raw).hexdigest(), 'categories': counts}
for label, data in [('before', before), ('after', after)]:
    pool = [line for values in data['chat_lines'].values() for line in values]
    report[label] = {
        'lines': len(pool), 'median_words': statistics.median(len(line.split()) for line in pool),
        'at_most_six_words': sum(len(line.split()) <= 6 for line in pool),
        'max_characters': max(map(len, pool)),
        'exact_duplicates': len(pool) - len(set(pool)),
    }
(run / 'validation.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
print('JSON contract OK')
print(json.dumps(report, indent=2))
