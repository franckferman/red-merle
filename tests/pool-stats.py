#!/usr/bin/env python3
"""Print the TAC pool's real sizes: total, EMEA pool, global pool.

Read by tests/check-version.sh so the figures quoted in the README and on the
website are checked against the code rather than against someone's memory of
it. The counts drifted twice before this existed.
"""
import re
import sys

SRC = 'files/lib/red-merle/imei_generate.py'

try:
    src = open(SRC, encoding='utf-8').read()
    block = src[src.index('TAC_POOL = ['):]
    block = block[:block.index('\n]')]
except (OSError, ValueError) as exc:
    print('cannot read the TAC pool from %s: %s' % (SRC, exc), file=sys.stderr)
    sys.exit(1)

entries = re.findall(r'"tac": "(\d{8})".*?"fits": \[([^\]]*)\]', block, re.S)
if not entries:
    print('no pool entries matched in %s' % SRC, file=sys.stderr)
    sys.exit(1)

emea = sum(1 for _, fits in entries if 'ep06e' in fits)
glob = sum(1 for _, fits in entries if 'em060k' in fits)
print('%d %d %d' % (len(entries), emea, glob))
