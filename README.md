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

## Dungeon prerequisite journal — sample proposal

This branch adds an optional **Quest journal (sample)** button to the existing dungeon Group Check
(`/omq ready dm`, for example). `/omq journal dm` opens it directly; the arrow buttons browse all
listed dungeons. Click a dungeon quest to expand its chain, then click an individual step to open
your quest log or point the existing guidance arrow at that step's giver.

Three complete chains are included: **The Defias Brotherhood** (Deadmines, quest 166),
**Smart Drinks** (Wailing Caverns, 1491), and **Hidden Enemies** (Ragefire Chasm, 5728).
The journal shows your character's completed, in-log, level and prerequisite states. It refreshes
while open and uses the existing faction filter. “Known prerequisites met” describes only the
included chain; it does not guarantee that the server offers a quest. Uncovered chains and missing
client progress APIs show **Unknown**. No character progress is stored or shared by the journal.
If guidance is disabled or the client cannot open its quest log, the journal stays open and explains why.

The idea comes from [Forever Guide's dungeon quest feature](https://www.curseforge.com/wow/addons/forever-guide).
This is an independent sample: its small dataset comes from GPL-3.0 QuestieDB Forever, with exact
source links in `Data/DungeonQuestChains.lua`. Full dungeon coverage, rewards and map pins are
outside this proposal. No release version is changed.

Run the regression check from the repository root with `lua5.1 tests/dungeon_quest_journal.lua`.
In-game validation still required: test each faction, expand a chain, accept/turn in a step, check
that the next step updates and routes to its own giver, then switch dungeons and close with Escape.

## Install

Download the latest `OneMoreQuest_vX.Y.Z.zip` from [Releases](../../releases), unzip it into the `Interface/AddOns` folder of your WoW Forever installation and `/reload`.
With WowUp: "Install from URL" and paste the address of this repository; WowUp then keeps it up to date.

In the game: `/omq help` lists the commands; right click on the minimap icon opens the quick options, Shift + right click all options.

## License

GPL-3.0, see [LICENSE](LICENSE). Uses map and quest data from [Questie / QuestieDB](https://github.com/Questie/QuestieDB) (GPL-3.0), and the skill-up thresholds of [SkillUp Forever](https://github.com/cjber/skillup-forever) by cjber (GPL-3.0).
