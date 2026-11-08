"""Generate dungeon quest metadata from a pinned, merged GPL-3.0 QuestieDB checkout.

Run: python tools/generate_dungeon_quests.py PATH_TO_QUESTIEDB [--check]
Requires Python 3 and Lua 5.1 (defaults to QuestieDB's bundled interpreter).
The upstream exporter writes its combined/ files inside that source checkout.
Only the generated addon data file is written here; no WoW installation is touched.
"""

import argparse
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

REVISION = "3a621efafce6aef99b0f106d22aa71ca980ee552"
ZONE_KEYS = {
    2437: ("rfc",), 16919: ("hot",), 718: ("wc",), 16611: ("rol",),
    1581: ("dm",), 209: ("sfk",), 719: ("bfd",), 717: ("stk",),
    16732: ("exc",), 721: ("gnom",), 16544: ("dal",), 491: ("rfk",),
    796: ("smg", "sml", "sma", "smc"), 722: ("rfd",), 1337: ("uld",),
    1176: ("zf",), 2100: ("mara",), 1477: ("st",), 1584: ("brd",),
    2557: ("dme", "dmw", "dmn"), 1583: ("lbrs", "ubrs"),
    2057: ("sch",), 2017: ("stl", "stu"),
    17780: ("kro",), 16985: ("shp",),
}
RACES = {1: 1, 2: 2, 3: 4, 4: 8, 5: 16, 6: 32, 7: 64, 8: 128,
         95: 4294967296, 96: 8589934592}
ALLIANCE = {1, 3, 4, 7, 95}
HORDE = {2, 5, 6, 8, 96}
# Class-sort quests whose specific objective items/NPCs establish a dungeon visit.
# Some dungeon-family assignments remain deliberately wing-unspecified.
CLASS_DUNGEONS = {
    1442: ("bfd",), 1654: ("dm", "sfk"), 1740: ("bfd", "sfk"),
    1951: ("smg", "sml", "sma", "smc"), 1956: ("uld",),
    7463: ("dme",), 7581: ("dme",),
    7631: ("dmw",), 7629: ("sch",), 7668: ("sch",),
    8258: ("sch",), 7642: ("stl", "stu"), 7647: ("sch",), 8257: ("st",),
    79360: ("rfk",), 96264: ("rfk",), 95036: ("dm",), 95042: ("bfd",),
    8232: ("st",), 8236: ("st",), 8253: ("st",), 8413: ("st",), 8418: ("st",),
    8422: ("st",), 8425: ("st",), 9053: ("st",),
    7643: ("dmw",), 9257: ("stl", "stu"),
    9269: ("stl", "stu"), 9270: ("stl", "stu"), 9271: ("stl", "stu"),
    78676: ("smg", "sml", "sma", "smc"),
}

# Execute data with Lua rather than attempting to parse Lua with regular expressions.
# JSON object keys preserve sparse positional fields, including holes after nil.
LUA_READER = r'''
local base, catalog = arg[1], arg[2]
local function read(path) local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local function literal(path) return assert(loadstring(assert(read(path):match("%[%[(return .-)%]%]"))))() end
local function locale(kind)
  local result={}
  for _, prefix in ipairs({"", "traces/"}) do
    local values=literal(base.."/l10n/Forever/"..prefix.."lookup"..kind.."/deDE.lua")
    for id,value in pairs(values) do result[id]=value end
  end
  return result
end
local zone={private={}}
local expansions={Current=1,Wotlk=3,Cata=4}
QuestieLoader={ImportModule=function(_,name) return name=="ZoneDB" and zone or expansions end}
UnitFactionGroup=function() return "Alliance" end
dofile(base.."/support/Forever/Zones/areaIdToUiMapId.lua")
local areas=assert(loadstring(zone.private.areaIdToUiMapId))()
for id,map in pairs(assert(loadstring(zone.private.areaIdToUiMapIdOverride))()) do areas[id]=map end
dofile(base.."/support/Forever/Zones/dungeons.lua")
OneMoreQuest={}
assert(loadfile(catalog))("OneMoreQuest",OneMoreQuest)
local combined=base.."/src/corrections/Forever/combined/forever"
local input={quests=dofile(combined.."QuestDB.lua"),npcs=dofile(combined.."NpcDB.lua"),
 items=dofile(combined.."ItemDB.lua"),objects=dofile(combined.."ObjectDB.lua"),
 questDE=locale("Quests"),npcDE=locale("Npcs"),itemDE=locale("Items"),objectDE=locale("Objects"),
 areas=areas,dungeonAreas=zone.private.dungeons,catalog=OneMoreQuest.Dungeons}
local escapes={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
local function quote(s)
  return '"'..s:gsub('[%z\1-\31\\"]',function(c) return escapes[c] or string.format('\\u%04x',c:byte()) end)..'"'
end
local function encode(v)
  local kind=type(v)
  if kind=="nil" then return "null" end
  if kind=="string" then return quote(v) end
  if kind=="boolean" then return tostring(v) end
  if kind=="number" then return string.format("%.17g",v) end
  assert(kind=="table", "Unexpected source value: "..kind)
  local keys, parts={},{}
  for k in pairs(v) do keys[#keys+1]=k end
  table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
  for _,k in ipairs(keys) do parts[#parts+1]=quote(tostring(k))..":"..encode(v[k]) end
  return "{"..table.concat(parts,",").."}"
end
io.write(encode(input))
'''


def field(row, index, default=None):
    return row.get(str(index), default) if isinstance(row, dict) else default


def values(row):
    return [value for key, value in sorted((row or {}).items(), key=lambda pair: int(pair[0]))]


def ids(row):
    return [int(value) for value in values(row)]


def clean(text):
    return re.sub(r"\s+", " ", text or "").strip()


def short(text):
    text = clean(text)
    return text if len(text) <= 240 else text[:237].rstrip() + "..."


def restrictions(row):
    races = [race for race, mask in RACES.items() if int(field(row, 6, 0) or 0) & mask]
    classes = [index + 1 for index in range(11) if int(field(row, 7, 0) or 0) & (1 << index)]
    faction = "A" if races and set(races) <= ALLIANCE else "H" if races and set(races) <= HORDE else None
    return races, classes, faction


def chain_ids(root, quests):
    ordered, visited, active = [], set(), set()
    missing = set()
    complete = True

    def visit(qid):
        nonlocal complete
        if qid in active:
            complete = False
            return
        if qid in visited:
            return
        visited.add(qid)
        row = quests.get(str(qid))
        if row is None:
            complete = False
            missing.add(qid)
            return
        active.add(qid)
        parents = ids(field(row, 12)) + ids(field(row, 13))
        parents += [int(field(row, index)) for index in (25, 34) if field(row, index)]
        for parent in parents:
            visit(abs(parent))
        active.remove(qid)
        ordered.append(qid)

    visit(root)
    return ordered, complete, sorted(missing)


def lua(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "{" + ",".join(lua(item) for item in value) + "}"
    return "{" + ",".join((key if re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", str(key)) else "[" + lua(key) + "]")
                           + "=" + lua(item) for key, item in value.items() if item is not None) + "}"


class Generator:
    def __init__(self, source):
        self.source = source
        self.quests = source["quests"]
        self.aliases = dict(ZONE_KEYS)
        for area, dungeon in source["dungeonAreas"].items():
            keys = ZONE_KEYS.get(int(area))
            if keys:
                for alias in ids(field(dungeon, 2)):
                    self.aliases[alias] = keys

    def name(self, kind, entity_id):
        raw = self.source[kind].get(str(entity_id))
        english = field(raw, 1, "")
        localized = self.source[{"npcs": "npcDE", "objects": "objectDE", "items": "itemDE"}[kind]].get(str(entity_id))
        german = (localized if isinstance(localized, str) else field(localized, 1)) or english
        return [english, german]

    def raw_spots(self, kind, entity_id):
        row = self.source[kind].get(str(entity_id))
        return field(row, 7 if kind == "npcs" else 4, {})

    def points(self, references):
        buckets = {}
        for kind, entity_id in sorted(set(references)):
            name = self.name(kind, entity_id)
            for area, coords in self.raw_spots(kind, entity_id).items():
                area = int(area)
                map_id = self.source["areas"].get(str(area))
                if not map_id or area in (10073, 10074, 10089):
                    continue
                for coord in values(coords):
                    x, y = field(coord, 1), field(coord, 2)
                    if x is None or y is None or not (0 <= x <= 100 and 0 <= y <= 100):
                        continue
                    key = (kind, entity_id, map_id, int(x // 10), int(y // 10))
                    if key not in buckets:
                        buckets[key] = [[map_id, x, y, name[0], name[1]], 0]
                    buckets[key][1] += 1
        by_map = defaultdict(list)
        for key, (point, count) in buckets.items():
            by_map[key[:3]].append((count, point))
        result = []
        for key in sorted(by_map):
            result.extend(point for _, point in sorted(by_map[key], key=lambda pair: (-pair[0], pair[1]))[:6])
        return sorted(result)

    def references(self, tuple_):
        return [(kind, entity_id) for index, kind in ((1, "npcs"), (2, "objects")) for entity_id in ids(field(tuple_, index))]

    def objectives(self, row):
        objectives = field(row, 10, {})
        refs = [(kind, int(field(target, 1))) for index, kind in ((1, "npcs"), (2, "objects"))
                for target in values(field(objectives, index)) if field(target, 1)]
        for target in values(field(objectives, 5)):
            refs.extend(("npcs", npc) for npc in ids(field(target, 1)))
        for target in values(field(objectives, 3)):
            item = self.source["items"].get(str(field(target, 1)), {})
            refs.extend(("npcs", npc) for npc in ids(field(item, 2)))
            refs.extend(("objects", obj) for obj in ids(field(item, 3)))
        return sorted(set(refs))

    def node(self, qid):
        row = self.quests[str(qid)]
        local = self.source["questDE"].get(str(qid), {})
        english = field(row, 1)
        start_refs = self.references(field(row, 2))
        start_items = ids(field(field(row, 2), 3))
        start_item = self.name("items", start_items[0]) if start_items and not start_refs else None
        if start_item:
            for item_id in start_items:
                item = self.source["items"].get(str(item_id), {})
                start_refs.extend(("npcs", npc) for npc in ids(field(item, 2)))
                start_refs.extend(("objects", obj) for obj in ids(field(item, 3)))
        end_refs = self.references(field(row, 3))
        objective_refs = self.objectives(row)
        starts, ends, objectives = self.points(start_refs), self.points(end_refs), self.points(objective_refs)
        trigger = field(field(row, 9), 2, {})
        for area, coords in trigger.items():
            map_id = self.source["areas"].get(str(area))
            for coord in values(coords):
                x, y = field(coord, 1), field(coord, 2)
                if map_id and x is not None and y is not None and 0 <= x <= 100 and 0 <= y <= 100:
                    objectives.append([map_id, x, y, english, field(local, 1, english)])
        if starts:
            point = starts[0]
            kind = next((kind for kind, entity_id in start_refs if self.name(kind, entity_id)[0] == point[3]), "npcs")
            start = [qid, english, *(start_item or point[3:5]), *point[:3], "item" if start_item else "npc" if kind == "npcs" else "object"]
        elif start_item:
            start = [qid, english, *start_item, 0, 0, 0, "item"]
        elif start_refs:
            kind, entity_id = start_refs[0]
            name = self.name(kind, entity_id)
            inside = any(str(area) in self.source["dungeonAreas"] or int(area) in self.aliases
                         for area in self.raw_spots(kind, entity_id))
            start = [qid, english, *name, 0, 0, 0, "inside" if inside else "npc" if kind == "npcs" else "object"]
        elif ids(field(field(row, 2), 3)):
            name = self.name("items", ids(field(field(row, 2), 3))[0])
            start = [qid, english, *name, 0, 0, 0, "item"]
        else:
            start = None
        target_names = [[entity_id, *self.name(kind, entity_id)] for kind, entity_id in objective_refs]
        en_objective = short(" ".join(values(field(row, 8))))
        de_objective = short(" ".join(values(field(local, 2))))
        if not en_objective:
            en_objective = short("Objectives: " + ", ".join(target[1] for target in target_names)) if target_names else "Objective text is not included in the source; check the in-game quest description."
        if not de_objective:
            de_objective = short("Ziele: " + ", ".join(target[2] for target in target_names)) if target_names else en_objective
        races, classes, faction = restrictions(row)
        inside = not objectives and (int(field(row, 17, 0) or 0) in self.aliases
            or any(int(area) in self.aliases for kind, entity_id in objective_refs for area in self.raw_spots(kind, entity_id)))
        delivery = not field(row, 10) and not field(row, 9) and bool(end_refs)
        return dict(id=qid, name=english, nameDe=local if isinstance(local, str) else field(local, 1, english), level=field(row, 4, 1), questLevel=field(row, 5, 1),
                    faction=faction, classes=classes, races=races, start=start, startItem=start_item, objective=[en_objective, de_objective],
                    turnIn=self.name(*end_refs[0]) if end_refs else None, targets=target_names,
                    startSpots=starts, endSpots=ends, objectiveSpots=objectives, inside=inside, delivery=delivery,
                    requiresAll=ids(field(row, 12)), requiresAny=ids(field(row, 13)),
                    requiresActive=[field(row, 25)] if field(row, 25) else [],
                    requiresStarted=[field(row, 34)] if field(row, 34) else [])

    def generate(self):
        dungeons = values(self.source["catalog"])
        original = {int(q["id"]) for d in dungeons for q in values(d["quests"])}
        original.update(int(alt) for d in dungeons for q in values(d["quests"]) for alt in values(q.get("alt")))
        additions = defaultdict(list)
        for key, row in sorted(self.quests.items(), key=lambda pair: int(pair[0])):
            qid = int(key)
            keys = CLASS_DUNGEONS.get(qid) or self.aliases.get(int(field(row, 17, 0) or 0), ())
            if qid in original or not keys:
                continue
            races, classes, faction = restrictions(row)
            for dungeon_key in keys:
                additions[dungeon_key].append(dict(id=qid, name=field(row, 1), level=field(row, 4, 1), faction=faction,
                                                  classes=classes, races=races,
                                                  wingUnknown=len(keys) > 1 and all(key in ("smg", "sml", "sma", "smc", "dme", "dmw", "dmn", "lbrs", "ubrs", "stl", "stu") for key in keys)))
        roots = original | {q["id"] for quests in additions.values() for q in quests}
        chains = {qid: chain_ids(qid, self.quests) for qid in sorted(roots)}
        nodes = {qid for ordered, _, _ in chains.values() for qid in ordered}
        incomplete = [qid for qid, (_, complete, _) in chains.items() if not complete]
        missing = sorted({qid for _, _, absent in chains.values() for qid in absent})
        lines = ["-- Generated by tools/generate_dungeon_quests.py; do not edit.",
                 "-- GPL-3.0 QuestieDB Forever, merged Static Corrections, revision " + REVISION,
                 "-- https://github.com/Questie/QuestieDB/tree/" + REVISION,
                 "-- Coordinates are representative known database spawn areas (at most six per target/map), not live positions.",
                 "-- Instance sentinel coordinates and unresolved synthetic world maps are never rendered as exact positions.",
                 "local ADDON, OMQ = ...", "OMQ = _G.OneMoreQuest", "local Q = {"]
        for qid in sorted(nodes):
            lines.append("[" + str(qid) + "]=" + lua(self.node(qid)) + ",")
        lines.append("}\nOMQ.DungeonQuestChains = {")
        for qid, (ordered, complete, absent) in chains.items():
            lines.append("[" + str(qid) + "]={" + ",".join("Q[" + str(step) + "]" for step in ordered)
                         + ",complete=" + lua(complete) + ",missingPrerequisites=" + lua(absent) + "},")
        lines.append("}\nOMQ.DungeonQuestAdditions = " + lua(dict(sorted(additions.items()))))
        coverage = dict(dungeons=len(dungeons), catalogIds=len(original), additionalIds=len(roots - original),
                        roots=len(roots), steps=len(nodes), incomplete=len(incomplete), missingIds=missing, revision=REVISION)
        lines.append("OMQ.DungeonQuestCoverage = " + lua(coverage))
        lines.append("")
        return "\n".join(lines), coverage


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="QuestieDB checkout at the documented revision")
    parser.add_argument("--lua", type=Path, help="Lua 5.1 interpreter; defaults to the source checkout's bundled Lua")
    parser.add_argument("--check", action="store_true", help="Fail when checked-in data differs; do not change addon data")
    args = parser.parse_args()
    source = args.source.resolve()
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    if revision != REVISION:
        parser.error("Expected QuestieDB revision " + REVISION + ", got " + revision)
    subprocess.run(["git", "diff", "--exit-code", "HEAD", "--", "data/Forever", "src", "support/Forever", "l10n/Forever", "generator", "tools/export"],
                   cwd=source, check=True, stdout=subprocess.PIPE)
    interpreter = args.lua.resolve() if args.lua else source / ("tools/lua-binary/lua.exe" if sys.platform == "win32" else "tools/lua-binary/linux-x64/lua")
    subprocess.run([str(interpreter), "tools/export-forever.lua", "--include-authored"], cwd=source, check=True)
    repository = Path(__file__).resolve().parents[1]
    decoded = subprocess.check_output([str(interpreter), "-", str(source), str(repository / "OneMoreQuest/Data/DungeonQuests.lua")],
                                      input=LUA_READER.encode("utf-8"), cwd=source)
    result, coverage = Generator(json.loads(decoded)).generate()
    destination = repository / "OneMoreQuest/Data/DungeonQuestChains.lua"
    if args.check:
        if destination.read_text(encoding="utf-8") != result:
            raise SystemExit("Dungeon quest data differs; regenerate it first")
    else:
        temporary = destination.with_suffix(".lua.tmp")
        temporary.write_text(result, encoding="utf-8", newline="\n")
        temporary.replace(destination)
    print(json.dumps(coverage, sort_keys=True))


if __name__ == "__main__":
    main()
