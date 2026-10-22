"""Offline Lua 5.4 syntax + journal regression tests; requires optional lupa."""
import argparse
import sys
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--lupa-dir', type=Path)
args = parser.parse_args()
if args.lupa_dir:
    sys.path.insert(0, str(args.lupa_dir.resolve()))
from lupa.lua54 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
files = [*root.rglob('*.lua')]
for path in files:
    lua.execute('assert(load(...))', path.read_text(encoding='utf-8-sig'), '@' + str(path))
print(f'PASS Lua 5.4 syntax ({len(files)} files)', flush=True)
lua.globals().arg = lua.table_from({1: root.as_posix()})
lua.execute((root / 'tests/reversal_spec.lua').read_text(encoding='utf-8'))
