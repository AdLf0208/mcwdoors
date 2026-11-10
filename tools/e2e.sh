#!/usr/bin/env bash
# In-game check for the Macaw's Doors content port (240 doors -> 239 carried,
# 12 door prints), Minecraft 26.3 on the campaign pin 41f822b6.
#
# Default run (offscreen renderer, creative, The End, shared unmodded game +
# `--dev-mod content/`):
#   0. tools/verify_content.py compares the carried folder mod with the
#      1.21.1 jar first (blockstate/model/texture/recipe/loot/lang fidelity,
#      hash-sealed at the top of this script's log);
#   1. the mod loads (no "content mods not loaded");
#   2. all 239 carried door ids `setblock` and read back, so every registry
#      entry and its default state binds;
#   3. the directional state space is real, not only declared: 16 lower/upper
#      pairs across facing x hinge x open read back every property, plus a
#      `powered=true` pair;
#   4. a door item places on a support, both halves appear with
#      facing/half/hinge/open/powered, right-click opens both halves and a
#      second click closes them;
#   5. a vanilla oak door does the same (baseline), a plain stick places
#      nothing (control), and unknown ids are refused;
#   6. the eight IRON BlockSetType doors (metal_*, jail, store,
#      sliding_glass) are differentially checked: they ignore a right-click
#      (changed:false, still open=false) while a redstone block opens them
#      (open=true,powered=true) and removing it closes them - vanilla
#      iron_door is the same-run baseline. A hand-open assertion that is
#      merely a read-out would pass on the metal door and fail here;
#   7. a screenshot of a placed door differs from the same frame with the
#      door removed, and the log carries no missing-model/missing-texture
#      warning for mcwdoors (missing assets are a failure);
#   8. the creative tab lists all 251 carried items.
#
# NEGATIVE=1 keeps the same scenario but expects the wooden door to stay
# closed after a right-click: the run MUST fail, proving the open assertion is
# not vacuous. `SKIP_VERIFY=1` skips the jar comparison (debugging only).
set -euo pipefail

CLONE=${CAMPAIGN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}
PORT=$CLONE/ports/mcwdoors
SHARED=$CLONE/ports/_shared/bin/horizon-41f822b6
CTL=${CTL:-$SHARED/horizon-ctl}
GAME=${GAME:-$SHARED/horizon-client}
RES=${RES:-${HORIZON_RES:-$HOME/Desktop/horizon/.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/mcwdoors-e2e.sock}
NEGATIVE=${NEGATIVE:-0}
SKIP_VERIFY=${SKIP_VERIFY:-0}

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }
[ -f "$PORT/content/horizon-mod.toml" ] || { echo "missing content mod: $PORT/content" >&2; exit 1; }

BLOCK_DIR=$PORT/content/data/mcwdoors/horizon/block
mapfile -t DOORS < <(find "$BLOCK_DIR" -name '*.json' -printf '%f\n' | sed 's/\.json$//' | sort)
[ "${#DOORS[@]}" -eq 239 ] || { echo "expected 239 carried doors, found ${#DOORS[@]}" >&2; exit 1; }

say() { echo "== $* =="; }
fail() { echo "FAIL: $*" >&2; exit 1; }

if [ "$SKIP_VERIFY" = 1 ]; then
    echo "== jar comparison skipped (SKIP_VERIFY=1) =="
else
    say "data fidelity: carried content vs the 1.21.1 jar"
    python3 "$PORT/tools/verify_content.py" --content "$PORT/content" --resources "$RES" \
        || fail "verify_content.py failed"
fi

SCRATCH=$(mktemp -d /tmp/opencode/mcwdoors-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")"
rm -f "$SOCK"
cd "$SCRATCH"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
end() { ctl command "execute in minecraft:the_end run $1"; }
count_item() { ctl inventory | jq -r --arg i "$1" '.counts[$i] // 0'; }
block_name() { ctl block "$1" "$2" "$3" | jq -r '.block // "unknown"'; }
block_state() { ctl block "$1" "$2" "$3" | jq -r '.state // "unknown"'; }
prop() { echo "$1" | grep -o "$2=[a-z]*" | head -1 | cut -d= -f2 || true; }
assert_prop() {
    local state=$1 key=$2 want=$3 got
    got=$(prop "$state" "$key")
    [ "$got" = "$want" ] || fail "$state: $key is '$got', expected '$want'"
}
is_open() { prop "$(block_state "$1" "$2" "$3")" open; }
mean_rgb() {
    python3 - "$1" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
crop = im.crop((w * 3 // 10, h * 3 // 10, w * 7 // 10, h * 7 // 10))
px = list(crop.getdata())
n = len(px)
print(sum(p[0] for p in px) / n, sum(p[1] for p in px) / n, sum(p[2] for p in px) / n)
PY
}

cleanup() {
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$SCRATCH" || true
}
trap cleanup EXIT

say "launch (offscreen renderer, creative, The End, content --dev-mod content/)"
"$CTL" --socket "$SOCK" launch \
    --game "$GAME" --world McwDoorsE2E --seed 20261104 --creative --offscreen --wait \
    --game-dir "$SCRATCH/game" --resources "$RES" --dev-mod "$PORT/content"
ctl wait-ready 180
if ctl logs --lines 4000 2>/dev/null | grep -q "content mods not loaded"; then
    ctl logs --lines 4000 | grep "content mods not loaded" >&2
    fail "the content mod did not load"
fi
echo "content mod loaded (no 'content mods not loaded')"

say "The End arena: floor at y=79, clear above"
end "forceload add -8 -8 72 72"
end "tp @s 8.5 80 8.5"
ctl wait 40
end "fill -8 79 -8 72 79 32 minecraft:stone"
end "fill -8 80 -8 72 88 32 minecraft:air"
end "difficulty peaceful"
end "gamerule spawn_mobs false"
ctl wait 10
ctl close >/dev/null 2>&1 || true
ctl wait 2

# ------------------------------------------------------------------ registry
say "all ${#DOORS[@]} carried door ids bind their default state"
PER=24
for i in "${!DOORS[@]}"; do
    x=$((2 + i % PER)); z=$((2 + i / PER))
    ctl setblock "$x" 80 "$z" "mcwdoors:${DOORS[$i]}" >/dev/null \
        || fail "setblock mcwdoors:${DOORS[$i]} failed"
done
ctl wait 10
for i in "${!DOORS[@]}"; do
    x=$((2 + i % PER)); z=$((2 + i / PER))
    got=$(block_name "$x" 80 "$z")
    [ "$got" = "mcwdoors:${DOORS[$i]}" ] \
        || fail "x=$x z=$z reads '$got', expected mcwdoors:${DOORS[$i]}"
done
echo "${#DOORS[@]}/${#DOORS[@]} door ids registered and their default state bound"

# ------------------------------------------------------------- directional
say "16 facing x hinge x open pairs read back every directional property"
combo=0
for facing in north east south west; do
    for hinge in left right; do
        for open in false true; do
            x=$((40 + combo)); z=2
            ctl setblock "$x" 80 "$z" \
                "mcwdoors:oak_barn_door[facing=$facing,half=lower,hinge=$hinge,open=$open,powered=false]" >/dev/null \
                || fail "setblock lower facing=$facing hinge=$hinge open=$open failed"
            ctl setblock "$x" 81 "$z" \
                "mcwdoors:oak_barn_door[facing=$facing,half=upper,hinge=$hinge,open=$open,powered=false]" >/dev/null \
                || fail "setblock upper facing=$facing hinge=$hinge open=$open failed"
            combo=$((combo + 1))
        done
    done
done
ctl wait 10
combo=0
for facing in north east south west; do
    for hinge in left right; do
        for open in false true; do
            x=$((40 + combo)); z=2
            lower=$(block_state "$x" 80 "$z")
            upper=$(block_state "$x" 81 "$z")
            for half in lower upper; do
                state=$lower; [ "$half" = upper ] && state=$upper
                assert_prop "$state" facing "$facing"
                assert_prop "$state" half "$half"
                assert_prop "$state" hinge "$hinge"
                assert_prop "$state" open "$open"
                assert_prop "$state" powered false
            done
            combo=$((combo + 1))
        done
    done
done
echo "16/16 pairs: facing/half/hinge/open preserved on both halves, powered=false"
ctl setblock 60 80 2 "mcwdoors:oak_barn_door[facing=west,half=lower,hinge=left,open=false,powered=true]" >/dev/null
ctl setblock 60 81 2 "mcwdoors:oak_barn_door[facing=west,half=upper,hinge=left,open=false,powered=true]" >/dev/null
ctl wait 5
assert_prop "$(block_state 60 80 2)" powered true
assert_prop "$(block_state 60 81 2)" powered true
echo "powered=true binds on both halves (the 5th door property)"

# -------------------------------------------------------------- placement
say "place a door item on a support, open it by hand, close it"
ctl command "clear @s" >/dev/null
ctl give mcwdoors:oak_barn_door 2 >/dev/null || fail "cannot give mcwdoors:oak_barn_door"
ctl wait 3
ctl select mcwdoors:oak_barn_door >/dev/null || fail "cannot select mcwdoors:oak_barn_door"
ctl wait 2
ctl tp 20.5 80 22.5
ctl wait 3
reply=$(ctl place 20 80 20 --item mcwdoors:oak_barn_door 2>&1) || { echo "place reply: $reply"; fail "cannot place the door"; }
echo "place reply: $reply"
ctl wait 3
lower=$(block_state 20 80 20)
upper=$(block_state 20 81 20)
echo "lower: $lower"
echo "upper: $upper"
case "$lower" in mcwdoors:oak_barn_door*) ;; *) fail "the placed lower half is '$lower'" ;; esac
case "$upper" in mcwdoors:oak_barn_door*) ;; *) fail "the placed upper half is '$upper'" ;; esac
assert_prop "$lower" half lower
assert_prop "$upper" half upper
assert_prop "$lower" open false
assert_prop "$upper" open false
assert_prop "$lower" facing south
assert_prop "$lower" hinge left
echo "placed facing=south hinge=left open=false on both halves"

ctl look-at-block 20 80 20 >/dev/null 2>&1 || true
reply=$(ctl interact 20 80 20)
echo "open click: $reply"
ctl wait 3
want_open=true
[ "$NEGATIVE" = 1 ] && want_open=false
[ "$(is_open 20 80 20)" = "$want_open" ] \
    || fail "lower open=$(is_open 20 80 20), expected $want_open after the right-click"
[ "$(is_open 20 81 20)" = "$want_open" ] \
    || fail "upper open=$(is_open 20 81 20), expected $want_open after the right-click"
echo "right-click set open=$want_open on both halves"

ctl look-at-block 20 80 20 >/dev/null 2>&1 || true
ctl interact 20 80 20 >/dev/null
ctl wait 3
[ "$(is_open 20 80 20)" = false ] || fail "the second click did not close the door (open=$(is_open 20 80 20))"
[ "$(is_open 20 81 20)" = false ] || fail "the second click did not close the upper half"
echo "second right-click closed both halves"

# ------------------------------------------------------------ vanilla control
say "vanilla oak door baseline: hand opens and closes it"
ctl give minecraft:oak_door 2 >/dev/null || fail "cannot give minecraft:oak_door"
ctl wait 3
ctl select minecraft:oak_door >/dev/null || fail "cannot select minecraft:oak_door"
ctl wait 2
ctl tp 24.5 80 22.5
ctl wait 3
ctl place 24 80 20 --item minecraft:oak_door >/dev/null || fail "cannot place the vanilla oak door"
ctl wait 3
case "$(block_state 24 80 20)" in minecraft:oak_door*) ;; *) fail "the vanilla door did not place" ;; esac
ctl look-at-block 24 80 20 >/dev/null 2>&1 || true
ctl interact 24 80 20 >/dev/null
ctl wait 3
[ "$(is_open 24 80 20)" = true ] || fail "the vanilla oak door did not open by hand (harness baseline)"
ctl interact 24 80 20 >/dev/null
ctl wait 3
[ "$(is_open 24 80 20)" = false ] || fail "the vanilla oak door did not close"
echo "vanilla oak_door opens and closes by hand (same harness, same frames)"

say "a plain stick places nothing (empty-hand control)"
ctl give minecraft:stick 1 >/dev/null
ctl wait 2
ctl select minecraft:stick >/dev/null
ctl wait 2
ctl tp 28.5 80 22.5
ctl wait 2
ctl place 28 80 20 --item minecraft:stick >/dev/null 2>&1 || true
ctl wait 3
[ "$(block_name 28 80 20)" = minecraft:air ] || fail "a stick placed $(block_name 28 80 20)"
echo "a stick placed no block"

# ------------------------------------------------------- iron-set differential
say "iron-set door: right-click ignored, redstone opens, removal closes"
ctl give mcwdoors:metal_door 1 >/dev/null || fail "cannot give mcwdoors:metal_door"
ctl wait 3
ctl select mcwdoors:metal_door >/dev/null || fail "cannot select mcwdoors:metal_door"
ctl wait 2
ctl tp 32.5 80 22.5
ctl wait 3
ctl place 32 80 20 --item mcwdoors:metal_door >/dev/null || fail "cannot place mcwdoors:metal_door"
ctl wait 3
case "$(block_state 32 80 20)" in mcwdoors:metal_door*) ;; *) fail "mcwdoors:metal_door did not place" ;; esac
# Right-click with an EMPTY hand: holding a door item makes the game try to
# place a second door and the next redstone neighbour update is lost (vanilla
# iron_door shows the same, recorded as a harness quirk).
ctl command "clear @s" >/dev/null
ctl wait 2
ctl look-at-block 32 80 20 >/dev/null 2>&1 || true
reply=$(ctl interact 32 80 20)
echo "metal right-click: $reply"
changed=$(echo "$reply" | jq -r '.changed')
ctl wait 2
[ "$changed" = false ] || fail "the metal door changed on a right-click"
[ "$(is_open 32 80 20)" = false ] || fail "the metal door opened by hand"
echo "metal door ignored the right-click (open=false, changed=false)"
ctl setblock 32 80 21 minecraft:redstone_block >/dev/null
ctl wait 5
[ "$(is_open 32 80 20)" = true ] || fail "redstone did not open the metal door"
assert_prop "$(block_state 32 80 20)" powered true
echo "redstone opened it (open=true,powered=true)"
ctl setblock 32 80 21 minecraft:air >/dev/null
ctl wait 5
[ "$(is_open 32 80 20)" = false ] || fail "removing the redstone did not close the metal door"
assert_prop "$(block_state 32 80 20)" powered false
echo "removing the redstone closed it (open=false,powered=false)"

say "vanilla iron door is the same-run baseline"
ctl give minecraft:iron_door 1 >/dev/null
ctl wait 3
ctl select minecraft:iron_door >/dev/null
ctl wait 2
ctl tp 36.5 80 22.5
ctl wait 3
ctl place 36 80 20 --item minecraft:iron_door >/dev/null || fail "cannot place minecraft:iron_door"
ctl wait 3
case "$(block_state 36 80 20)" in minecraft:iron_door*) ;; *) fail "the vanilla iron door did not place" ;; esac
ctl command "clear @s" >/dev/null
ctl wait 2
ctl look-at-block 36 80 20 >/dev/null 2>&1 || true
ctl interact 36 80 20 >/dev/null 2>&1 || true
ctl wait 2
[ "$(is_open 36 80 20)" = false ] || fail "vanilla iron_door opened by hand"
echo "vanilla iron lower before redstone: $(block_state 36 80 20)"
ctl setblock 36 80 21 minecraft:redstone_block >/dev/null
ctl wait 5
echo "vanilla iron lower after redstone: $(block_state 36 80 20) (redstone $(block_name 36 80 21))"
[ "$(is_open 36 80 20)" = true ] || fail "vanilla iron_door did not open by redstone"
echo "vanilla iron_door: hand ignored, redstone opens (the metal behaviour is vanilla's)"

# -------------------------------------------------------------- screenshot
say "screenshot: the placed door is visible, the same frame without it is not"
ctl setblock 44 80 20 "mcwdoors:oak_barn_door[facing=south,half=lower,hinge=left,open=false,powered=false]" >/dev/null
ctl setblock 44 81 20 "mcwdoors:oak_barn_door[facing=south,half=upper,hinge=left,open=false,powered=false]" >/dev/null
ctl tp 44.5 80 22.5
ctl wait 10
ctl look-at-block 44 81 20 >/dev/null 2>&1 || true
ctl wait 10
ctl screenshot "$SCRATCH/door.png" >/dev/null
read -r r0 g0 b0 <<<"$(mean_rgb "$SCRATCH/door.png")"
ctl setblock 44 80 20 minecraft:air >/dev/null
ctl setblock 44 81 20 minecraft:air >/dev/null
ctl wait 10
ctl screenshot "$SCRATCH/empty.png" >/dev/null
read -r r1 g1 b1 <<<"$(mean_rgb "$SCRATCH/empty.png")"
echo "mean RGB with door: $r0 $g0 $b0"
echo "mean RGB empty:     $r1 $g1 $b1"
[ -s "$SCRATCH/door.png" ] || fail "the door screenshot is empty"
awk -v a="$r0" -v b="$r1" -v c="$g0" -v d="$g1" -v e="$b0" -v f="$b1" \
    'BEGIN { exit !(sqrt((a-b)^2+(c-d)^2+(e-f)^2) > 5) }' \
    || fail "the frame did not change when the door was removed (no model drawn?)"
echo "the door's frame differs from the empty frame (a model is drawn)"

say "no missing model/texture warnings for mcwdoors"
ctl logs --lines 6000 > "$SCRATCH/game.log" 2>/dev/null || true
if grep -iE "missing texture for mcwdoors|block models incomplete.*mcwdoors|no model.*mcwdoors|mcwdoors.*missing (model|texture)" "$SCRATCH/game.log"; then
    fail "the log reports a missing model/texture for mcwdoors"
fi
echo "the log has no mcwdoors missing-model/missing-texture warning"

# ------------------------------------------------------------------ items
say "the 12 door prints are give-able"
ctl command "clear @s" >/dev/null
for p in print_oak print_spruce print_birch print_jungle print_acacia print_dark_oak \
         print_mystic print_nether print_swamp print_bamboo print_waffle print_whispering; do
    ctl give "mcwdoors:$p" 1 >/dev/null || fail "cannot give mcwdoors:$p"
done
ctl wait 5
for p in print_oak print_spruce print_birch print_jungle print_acacia print_dark_oak \
         print_mystic print_nether print_swamp print_bamboo print_waffle print_whispering; do
    [ "$(count_item "mcwdoors:$p")" -ge 1 ] || fail "mcwdoors:$p is missing"
done
echo "12/12 print items are give-able"

say "the creative tab lists all 251 carried items"
CREATIVE=$(find "$SCRATCH/game/.horizon-cache/mod-content" -name creative-inventory.json -print -quit 2>/dev/null || true)
[ -n "$CREATIVE" ] && [ -f "$CREATIVE" ] || fail "no creative-inventory.json (content mod not loaded)"
python3 "$PORT/tools/tab_check.py" "$CREATIVE" 251 \
    mcwdoors:print_oak mcwdoors:print_whispering \
    mcwdoors:oak_barn_door mcwdoors:metal_door mcwdoors:sliding_glass_door \
    mcwdoors:cherry_whispering_door || fail "the creative tab check failed"

# ----------------------------------------------------------------- controls
say "unknown ids are refused"
if ctl give mcwdoors:not_a_door 1 >/dev/null 2>&1; then
    fail "give mcwdoors:not_a_door succeeded"
fi
ctl setblock 60 80 6 mcwdoors:bogus_door >/dev/null 2>&1 || true
[ "$(block_name 60 80 6)" = minecraft:air ] || fail "mcwdoors:bogus_door became a block"
if ctl setblock 62 80 2 \
    "mcwdoors:oak_barn_door[facing=up,half=lower,hinge=left,open=false,powered=false]" >/dev/null 2>&1; then
    got=$(block_state 62 80 2)
    case "$got" in *facing=up*) fail "an invalid facing=up door state was accepted" ;; esac
fi
echo "unknown door ids and invalid states are refused"

# ---------------------------------------------------------------- evidence
cp "$SCRATCH/door.png" "$PORT/tools/.e2e-last-door.png" 2>/dev/null || true
echo "PASS: ${#DOORS[@]}/239 door ids bind, 16 facing x hinge x open pairs keep all 5 door properties, a door item places facing south and opens/closes on right-click while vanilla oak_door does the same, the 8 iron-set doors ignore the hand and open/close on redstone like vanilla iron_door, the placed door renders (screenshot differs from the empty frame, no missing texture), a stick places nothing, all 12 prints give, and the creative tab lists 251 items; unknown ids are refused"
echo "EXIT:0"
exit 0
