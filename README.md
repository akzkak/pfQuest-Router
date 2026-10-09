# pfQuest-Router

An extension for [pfQuest](https://github.com/brues-code/pfQuest) that turns the spawn points of a database search into a closed loop and guides you around it with the pfQuest arrow, over and over. Made for grinding mobs, herbs, ore or anything else pfQuest can put on the map.

## Requirements

- [pfQuest](https://github.com/brues-code/pfQuest) (required)
- pfQuest-octo (optional, loaded first if present)

## Installation

1. Copy the folder into `Interface\AddOns` and make sure it is named `pfQuest-Router`.
2. Restart the game client and enable **pfQuest [Router]** in the addon list.

## Usage

Search as usual with pfQuest, then build a route from what is on the map:

```
/db Forest Boar
/pfr start
```

Or search and route in one step (exact unit or object name):

```
/pfr Forest Boar
```

The arrow points at the next waypoint and shows the route name, waypoint number and distance. Reaching the last waypoint continues with the first, so the loop never ends.

### Commands

| Command | Description |
| --- | --- |
| `/pfr start` | Route over the database search results on the current zone map |
| `/pfr <name>` | Search a unit or object by exact name and route it |
| `/pfr stop` | Remove the route |
| `/pfr next` / `/pfr prev` | Skip to the next / previous waypoint |
| `/pfr reverse` | Walk the loop in the other direction |
| `/pfr debug` | Toggle debug mode: explain every waypoint change in chat (default off) |
| `/pfr radius <n>` | Merge spawns closer than `<n>` map units into one waypoint (default 2) |
| `/pfr` | Show help and the active route |

`/router` is an alias for `/pfr`.

### World map

The loop is drawn on the zone map. The leg and waypoint you are heading for are gold, the rest of the loop is teal, and waypoints removed from the route are red.

| Action | Result |
| --- | --- |
| Right-click a waypoint | Remove it from the route; the marker stays on the map |
| Right-click a red waypoint | Add it back to the route |
| Left-click a waypoint | Head there next |

Every change to the route prints a summary to chat:

```
pfQuest Router: Waypoint removed - Forest Boar in Hillsbrad Foothills: 11 spawns, 11 waypoints (1 removed), loop length 172.
```

## How it works

- **Waypoints:** spawn points within the merge radius of each other are combined into a single waypoint. Use `/pfr radius 0` for one waypoint per spawn.
- **Loop:** waypoints are ordered into a short closed loop (nearest neighbour, then 2-opt), starting at the one nearest to you.
- **Advancing:** a waypoint counts as done only when you are within half the radius of it (1 map unit by default). Coming near it, or near a later waypoint on the way, never skips ahead, so the loop is walked strictly in order. Use `/pfr next` or left-click a waypoint to skip manually.
- **Direction:** the loop is walked in the order it was planned. Use `/pfr reverse` to go the other way round; it continues with the next waypoint in the new direction rather than the one you just left.
- **Arrow:** the route takes over pfQuest's own arrow, so its position and scale are unchanged. pfQuest gets the arrow back while you are dead or looking at another zone's map.

## Notes

- Routes last for the session only; `/reload` or relogging clears them, like `/db` search results. The radius and debug settings are saved per character.
- Removing or adding a waypoint re-plans the whole loop for the shortest path, so the order of the remaining waypoints can change. Your current target is kept.
- `/pfr start` uses every database result on the map except quest nodes. Run `/db clean` first if old searches are still showing.
- `/pfr radius <n>` rebuilds the route, which brings removed waypoints back.
- A waypoint marker sits on top of the pfQuest pin at the same spot and blocks that pin's tooltip and clicks while a route is active.
