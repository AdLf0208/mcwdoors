# Macaw's Doors — Horizon port

A port of [Macaw's Doors](https://github.com/sketchmacaw/MacawsDoors) by Sketch Macaw and Peachy Macaw for
Horizon. A data-tier carry: no native code and no hooks.

**Status:** the slice below is what works today; the second list is what is
missing. Nothing here claims parity with the original.

## What works

- 239 door blocks with all 64 vanilla door states (facing, half, hinge, open, powered)
  and their own models: 231 on the wooden-door template and 8 on the iron-door template.
- The 8 iron-set doors (metal, jail, store and sliding-glass) behave like vanilla iron
  doors: they ignore a right-click and open on redstone.
- The 12 door-print items and their recipes, 251 recipes, 239 loot tables, 12
  advancements, block/item tags and 17 language files.
- A creative tab (`itemGroup.mcwdoors`) listing the 239 doors and the 12 prints.

## Not yet ported

- The 6 garage doors and portcullises (a `part` column with a roll-up animation) and
  `cherry_waffle_door` (its block models are missing upstream) are not carried; their
  recipes are left out with them.
- The shoji/stable doors' per-half opening, the stable door's independent halves and the
  door-print tooltips are code, not carried.
- Fuel burn time is the vanilla door's 200 ticks; upstream's `FuelItemBlock` uses 300.
- Custom shoji/garage click sounds are not played (a content block uses its template's
  sounds).
- Hardness/blast resistance/sounds are the template's, not upstream's per-block values.

## Install

1. Take `mcwdoors.hmod` from this repository (or build it below).
2. Put it in the game folder's `horizon-mods` folder — the game folder is the
   one holding `options.txt`.
3. Mods are off by default: enable this one in the game's mod list.

To try it without installing, start the game with
`--dev-mod mcwdoors.hmod`.

## Build from source

This is a content-only mod: `content/horizon-mod.toml` plus `assets/` and
`data/`.

```sh
cd content && cargo horizon-mod build    # packs content/ into the .hmod and checks it
bash content/patches/apply.sh          # re-applies the 26.3 block declarations and the creative tab
```

`cargo-horizon-mod` comes from the Horizon repository
(`cargo install --git https://github.com/horizon-rust/horizon cargo-horizon-mod`).
`tools/` holds the content generator and the in-game harness. The harness
expects a campaign checkout (`$CAMPAIGN_ROOT`) with the prepared 26.3 resources
(`$HORIZON_RES`, default `~/Desktop/horizon/.local/horizon-client/26.3`).

## Compatibility

- Horizon `1d63e0a` (see `compatibility.json` for the exact revision this
  artifact was built against).
- horizon-mixins `5a64af93`, schema 6.
- Minecraft: Java Edition 26.3.

## Credits

Macaw's Doors 1.1.5 by Sketch Macaw and Peachy Macaw — <https://github.com/sketchmacaw/MacawsDoors>.
The original copyright and licence notices are kept in
[LICENSE](LICENSE); [LICENSE-NOTICE.md](LICENSE-NOTICE.md) records where each
was read from.

This is an unofficial port: Horizon is not affiliated with the original author.

## Licence

MIT — see [LICENSE](LICENSE).

## Contributing

The "Not yet ported" list is the gap list; an issue or a pull request that
closes one item is welcome. Please keep the original notices and say which
slice you are working on.
