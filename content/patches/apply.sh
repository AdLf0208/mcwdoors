#!/usr/bin/env bash
# Re-apply the hand patches after a fresh `horizon-port-pack carry` (it deletes
# and rewrites carry/). Run from ports/mcwdoors/content.
set -euo pipefail
cd "$(dirname "$0")/.."
# 1. The eight IRON BlockSetType doors (metal_*, jail, store, sliding_glass):
#    upstream opens these with redstone only; template them on vanilla iron_door.
for f in patches/block/*.json; do
    cp "$f" "data/mcwdoors/horizon/block/$(basename "$f")"
done
# 2. cherry_waffle_door: the jar has its blockstate + item model + item
#    texture but NO block models, loot, recipe or lang. Carrying it loads the
#    missing model; no assets are invented, so the block is left out.
rm -f data/mcwdoors/horizon/block/cherry_waffle_door.json
# 3. The jar has orphan item models with no registered block or item
#    (crimson_nether_door, warped_mystic_door: no BlockInit/ItemInit entry).
#    Do not invent items for them; keep the assets as upstream does.
rm -f data/mcwdoors/horizon/item/crimson_nether_door.json \
      data/mcwdoors/horizon/item/warped_mystic_door.json
# 4. The Java creative tab (TabInit) is code; mirror it as 26.3 data.
mkdir -p data/mcwdoors/horizon/creative_tab
cp patches/tab/doors.json data/mcwdoors/horizon/creative_tab/doors.json
echo "patches applied: 8 iron doors, 2 phantom items removed, 1 creative tab"
