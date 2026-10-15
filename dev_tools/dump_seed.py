"""Dump every game in games_seed.json: id, gameType, entryPoint, comingSoon."""
import json, os
path = r'c:\Users\Asus\Playora\playhub_bd\assets\data\games_seed.json'
with open(path, encoding='utf-8-sig') as f:
    payload = json.load(f)
    data = payload['games'] if isinstance(payload, dict) else payload
print(f"{'id':<22} {'type':<7} {'entry':<22} {'cs'}  title")
print('-' * 78)
for g in data:
    cs = 'Y' if g.get('comingSoon') else '.'
    ep = g.get('entryPoint') or '-'
    print(f"{g['id']:<22} {g['gameType']:<7} {ep:<22} {cs}  {g['title']}")