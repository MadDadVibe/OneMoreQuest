# One More Quest

A World of Warcraft addon for **WoW Forever**, made for a small group of friends (a few dads) who level together and want to reach 60 as a party. It works alone, but most features come alive when everybody in the group runs it.

## What it does

- **Playing together:** session and lifetime stats for the party, an arrow to whoever drifts too far away, automatic quest sharing, a shared quest tracker, and Alt on an item shows what it means for every party member.
- **One more quest?** `/omq` starts a vote: one more quest or bed time. If it is one more quest, the arrow leads the group to the best next quest.
- **Finding your way:** arrows to trainers, vendors, flight masters, dungeon entrances, quest hubs and a meeting point.
- **Alert cards:** small reminders for training, repairs, drinks, missing buffs, spells not on a bar, consumables, gear upgrades in your bags and more.
- **Dungeons:** a group check for durability, bags and supplies, the dungeon quests, and the best boss loot for you.
- **Comfort:** auction house and vendor helpers, quests accepted and turned in automatically with the best reward marked, Shift-click heals.
- **Fun:** bets between friends and titles at bed time.

Works with English and German clients.

## Dungeon quest journal — proposal

Open **Quest journal (sample)** from a dungeon Group Check (`/omq ready wc`), or use
`/omq journal wc`. The arrow buttons browse all listed dungeons. Choose **Horde**, **Alliance**
or **Both factions** to inspect their quests. Progress and eligibility hints always refer to your
own character, including when you inspect another faction or class.

Quests are grouped by pickup region and sorted by quest level within each region. Click a quest
to expand its prerequisites, then select a step for its directions. The **Pick up**, **Objectives**
and **Turn in** tabs explain who to visit and where to go, with region names and coordinates.
Each expanded prerequisite chain retains its dependency order; alternative prerequisites are not
treated as if every alternative were mandatory. Missing source data remains explicitly unknown.

Choose a location in the details, then use **Map: region targets** for known target markers in that
region, **My arrow** for local guidance, or **Tell group** for an explicit party-chat announcement.
Opening the journal, selecting a quest or viewing its map never sends a destination automatically.
Native player waypoints are left intact. **Open quest log** opens an accepted quest in the game's
quest log. Failed client actions and disabled guidance leave the journal open with an explanation.

The data covers every existing dungeon quest plus additional source-linked dungeon and class
quests, with full prerequisite graphs from the merged QuestieDB Forever database. Quests whose
source identifies only a dungeon complex are labelled as having an unverified wing. A quest with
missing source prerequisites is listed with an incomplete chain. Markers are representative known
database locations, not live creature tracking or an exhaustive list of spawns. Dungeon-interior
positions without verified coordinates are not invented. “Known prerequisites met” does not
guarantee that the server offers the quest; other game conditions can apply.

Current source coverage: **35 dungeon entries, 377 quest IDs and 642 distinct quest steps** with
6,557 named location points. All 203 IDs in the existing catalog have complete prerequisite data.
The additional Gnomeregan quest 4604 references missing alternative 2955 and stays marked incomplete.
For Krol'dok, Alcaz Prison, Blackmaw and Shaper's Terrace, the source supplies no additional verified
quests; empty views state that data is missing. The expanded catalog is scoped to the journal, so
the existing Group Check and its party-message format retain their original quest list.

The feature idea comes from [Forever Guide](https://www.curseforge.com/wow/addons/forever-guide).
The implementation and data import are independent and use GPL-3.0 QuestieDB Forever, pinned to
the revision documented in `Data/DungeonQuestChains.lua`. No Forever Guide code/database is
embedded. This remains a separate draft proposal with no release version change.

To regenerate the data, check out the documented QuestieDB revision and run
`python tools/generate_dungeon_quests.py PATH_TO_QUESTIEDB`; use `--check` to verify reproducibility
or `--lua PATH_TO_LUA51` to choose the interpreter. This is an offline development tool, not an
addon runtime dependency.

Run `lua5.1 tests/dungeon_quest_journal.lua`, `lua5.1 tests/dungeon_quest_locations.lua` and
`lua5.1 tests/quest_locations.lua` from the repository root. Actual world-map rendering, party
message delivery and live quest-state changes still require a manual WoW: Forever test.
The generator's pure regression checks run with
`python -B -m unittest discover -s tests -p test_generate_dungeon_quests.py`.

## Install

Download the latest `OneMoreQuest_vX.Y.Z.zip` from [Releases](../../releases), unzip it into the `Interface/AddOns` folder of your WoW Forever installation and `/reload`.
With WowUp: "Install from URL" and paste the address of this repository; WowUp then keeps it up to date.

In the game: `/omq help` lists the commands; right click on the minimap icon opens the quick options, Shift + right click all options.

## License

GPL-3.0, see [LICENSE](LICENSE). Uses map and quest data from [Questie / QuestieDB](https://github.com/Questie/QuestieDB) (GPL-3.0), and the skill-up thresholds of [SkillUp Forever](https://github.com/cjber/skillup-forever) by cjber (GPL-3.0).
