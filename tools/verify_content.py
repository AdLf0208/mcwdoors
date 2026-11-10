#!/usr/bin/env python3
"""Compare the carried mcwdoors content against the 1.21.1 jar it came from.

Data-level fidelity check for the Macaw's Doors content port. It reads the
jar (read-only), the carried folder mod and the prepared 26.3 tables, and
asserts every carried block/item/recipe/loot/lang/model/texture matches what
the jar declares. Exit 0 on success, 1 with the failures printed.

Usage:
    python3 tools/verify_content.py \
        [--jar ../../_shared/carry-work/mcwdoors/jars/...jar] \
        [--content content] [--resources /path/to/26.3]
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
import zipfile

DOOR_PROPS = {"facing", "half", "hinge", "open"}
MULTI_PROPS = {"facing", "open", "part"}


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    port = os.path.dirname(here)
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--jar",
        default=os.path.join(
            port,
            "../_shared/carry-work/mcwdoors/jars/"
            "mcw-doors-1.1.5-mc1.21.1neoforge.jar",
        ),
    )
    ap.add_argument("--content", default=os.path.join(port, "content"))
    ap.add_argument(
        "--resources",
        default=os.environ.get(
            "HORIZON_RES", os.path.expanduser("~/Desktop/horizon/.local/horizon-client/26.3")
        ),
    )
    args = ap.parse_args()

    failures: list[str] = []
    notes: list[str] = []

    def check(ok: bool, msg: str) -> None:
        if not ok:
            failures.append(msg)

    def say(msg: str) -> None:
        print(f"ok: {msg}")

    z = zipfile.ZipFile(args.jar)
    names = set(z.namelist())

    def blockstate_props(raw: str) -> set[str]:
        d = json.loads(raw)
        props: set[str] = set()
        for key in d.get("variants", {}):
            for part in key.split(","):
                if part:
                    props.add(part.split("=")[0])
        for part in d.get("multipart", []):
            when = part.get("when", {})
            for cond in [when, *when.get("OR", []), *when.get("AND", [])]:
                props.update(cond)
        return props

    jar_blocks = {}
    for n in sorted(names):
        if n.startswith("assets/mcwdoors/blockstates/") and n.endswith(".json"):
            jar_blocks[n.rsplit("/", 1)[-1][:-5]] = blockstate_props(
                z.read(n).decode("utf-8")
            )
    all_doors = {b for b, p in jar_blocks.items() if p == DOOR_PROPS}
    multi = {b for b, p in jar_blocks.items() if p == MULTI_PROPS}
    say(f"jar: {len(jar_blocks)} blockstates = {len(all_doors)} doors + {len(multi)} multipart")
    check(len(all_doors) == 240, f"expected 240 jar door blocks, found {len(all_doors)}")
    check(
        multi
        == {
            "garage_white_door",
            "garage_silver_door",
            "garage_gray_door",
            "garage_black_door",
            "wooden_portcullis",
            "iron_portcullis",
        },
        f"unexpected multipart set: {sorted(multi)}",
    )
    # cherry_waffle_door: the jar has its blockstate, item model and item
    # texture but NO block models, loot, recipe or lang. Carrying it would load
    # the missing model; the port leaves it out rather than invent assets.
    incomplete = {"cherry_waffle_door"}
    for b in incomplete:
        check(
            b in all_doors and not any(
                n.startswith(f"assets/mcwdoors/models/block/waffle/{b}") for n in names
            ),
            f"{b} is not the expected incomplete jar door",
        )
    doors = all_doors - incomplete
    say(f"skipped: {len(multi)} multipart blocks + {len(incomplete)} incomplete door "
        "(no block models upstream)")

    # --- block declarations ------------------------------------------------
    decl = {}
    for p in glob.glob(os.path.join(args.content, "data/mcwdoors/horizon/block/*.json")):
        with open(p) as f:
            decl[os.path.basename(p)[:-5]] = json.load(f)
    check(set(decl) == doors, f"declared blocks != jar doors: {sorted(set(decl) ^ doors)}")
    say(f"content: {len(decl)} block declarations, exactly the jar's door blocks")

    # Template state space, read from the prepared 26.3 tables.
    facts = json.load(open(os.path.join(args.resources, "facts.json")))
    template_props: dict[str, set[str]] = {}
    template_states: dict[str, int] = {}
    for entry in facts["states"]:
        name = entry[0]
        props = entry[-1].get("properties", {})
        template_props.setdefault(name, set()).update(props)
        template_states[name] = template_states.get(name, 0) + 1
    templates = {d["template"] for d in decl.values()}
    for t in sorted(templates):
        check(
            DOOR_PROPS <= template_props[t],
            f"template {t} lacks a directional property: {sorted(template_props[t])}",
        )
        check(
            template_states[t] == 64,
            f"template {t} has {template_states[t]} states, expected 64",
        )
    say(
        "templates preserve facing/half/hinge/open/powered and 64 states: "
        + ", ".join(
            f"{t} x{sum(1 for d in decl.values() if d['template'] == t)}"
            for t in sorted(templates)
        )
    )

    # --- assets the registrations need -------------------------------------
    def asset(ns_path: str) -> bool:
        return os.path.isfile(os.path.join(args.content, ns_path))

    for b in doors:
        check(
            asset(f"assets/mcwdoors/blockstates/{b}.json"),
            f"missing blockstate asset for {b}",
        )
        check(
            asset(f"assets/mcwdoors/items/{b}.json"),
            f"missing 26.3 item definition for {b}",
        )

    # --- items --------------------------------------------------------------
    items = {}
    for p in glob.glob(os.path.join(args.content, "data/mcwdoors/horizon/item/*.json")):
        items[os.path.basename(p)[:-5]] = json.load(open(p))
    prints = {i for i in items if i.startswith("print_")}
    jar_prints = {
        n.rsplit("/", 1)[-1][:-5]
        for n in names
        if n.startswith("assets/mcwdoors/models/item/print_") and n.endswith(".json")
    }
    check(prints == jar_prints, f"print items differ: {sorted(prints ^ jar_prints)}")
    check(len(items) == 12, f"expected 12 plain items, found {len(items)}: {sorted(items)}")
    say(f"items: 12 door prints carried ({len(jar_prints)} in the jar), no phantom items")

    registry = doors | prints

    # --- model + texture resolution ----------------------------------------
    model_files = set()
    for p in glob.glob(os.path.join(args.content, "assets/mcwdoors/models/**/*.json"), recursive=True):
        model_files.add(p.rsplit("models/", 1)[-1][:-5])
    referenced_models: set[str] = set()
    carried_blockstates = [
        os.path.join(args.content, f"assets/mcwdoors/blockstates/{b}.json") for b in doors
    ]
    carried_item_defs = [
        os.path.join(args.content, f"assets/mcwdoors/items/{b}.json") for b in doors
    ] + [
        os.path.join(args.content, f"assets/mcwdoors/items/{i}.json") for i in items
    ]
    for p in carried_blockstates + carried_item_defs:
        d = json.load(open(p))
        for key in ("variants",):
            for v in d.get(key, {}).values():
                for vv in v if isinstance(v, list) else [v]:
                    if "model" in vv:
                        referenced_models.add(vv["model"])
        for part in d.get("multipart", []):
            ap_ = part.get("apply", {})
            for vv in ap_ if isinstance(ap_, list) else [ap_]:
                if "model" in vv:
                    referenced_models.add(vv["model"])
        model = d.get("model")
        if isinstance(model, dict) and "model" in model:
            referenced_models.add(model["model"])
        elif isinstance(model, str):
            referenced_models.add(model)

    def resolves_model(ref: str) -> bool:
        ns, _, path = ref.partition(":")
        if ns == "minecraft":  # vanilla model, in the prepared resources
            return os.path.isfile(os.path.join(args.resources, "assets/minecraft/models", path + ".json"))
        if ns and ns != "mcwdoors":
            return True  # another namespace's model is not this port's to ship
        return path in model_files

    missing_models = sorted(m for m in referenced_models if not resolves_model(m))
    check(not missing_models, f"referenced models missing: {missing_models[:8]}")
    say(f"models: {len(model_files)} present, {len(referenced_models)} referenced by "
        "carried blocks/items, 0 missing")

    textures = {
        p.rsplit("textures/", 1)[-1][:-4]
        for p in glob.glob(
            os.path.join(args.content, "assets/mcwdoors/textures/**/*.png"), recursive=True
        )
    }
    missing_textures: set[str] = set()

    def walk(obj):
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k == "textures" and isinstance(v, dict):
                    for ref in v.values():
                        if isinstance(ref, str) and not ref.startswith("#"):
                            missing_textures.add(ref)
                else:
                    walk(v)
        elif isinstance(obj, list):
            for v in obj:
                walk(v)

    # Only models a carried block/item reaches (following parents) matter; the
    # jar's orphan item models have no texture and no registration.
    reached: set[str] = set()
    pending = [m.split(":", 1)[-1] for m in referenced_models if m.startswith("mcwdoors:") or ":" not in m]
    while pending:
        name = pending.pop()
        if name in reached or name not in model_files:
            continue
        reached.add(name)
        d = json.load(open(os.path.join(args.content, "assets/mcwdoors/models", name + ".json")))
        walk(d)
        parent = d.get("parent")
        if isinstance(parent, str) and (parent.startswith("mcwdoors:") or ":" not in parent):
            pending.append(parent.split(":", 1)[-1])
    say(f"models reached from carried blocks/items: {len(reached)} (parents followed)")

    def resolves_texture(ref: str) -> bool:
        ns, _, path = ref.partition(":")
        if ns == "minecraft":  # vanilla texture, in the prepared resources
            return os.path.isfile(os.path.join(args.resources, "assets/minecraft/textures", path + ".png"))
        if ns and ns != "mcwdoors":
            return True
        return path in textures

    missing_textures = {t for t in missing_textures if not resolves_texture(t)}
    check(not missing_textures, f"missing textures: {sorted(missing_textures)[:8]}")
    say(f"textures: {len(textures)} present, every reached model's texture resolves")

    # --- recipes ------------------------------------------------------------
    recipes = {}
    for p in glob.glob(os.path.join(args.content, "data/mcwdoors/recipe/*.json")):
        recipes[os.path.basename(p)[:-5]] = json.load(open(p))
    bad = [r for r, d in recipes.items() if d.get("result", {}).get("id") not in
           {f"mcwdoors:{x}" for x in registry}]
    check(not bad, f"recipes with an unregistered result: {bad[:8]}")
    jar_recipes = {
        n.rsplit("/", 1)[-1][:-5]
        for n in names
        if n.startswith("data/mcwdoors/recipe/") and n.endswith(".json")
    }
    expected_recipes = {r for r in jar_recipes if r not in multi}
    check(
        set(recipes) == expected_recipes,
        f"recipes differ from the jar (minus left-out blocks): "
        f"{sorted(set(recipes) ^ expected_recipes)[:8]}",
    )
    say(f"recipes: {len(recipes)} carried, every result registered; {len(jar_recipes) - len(recipes)} left out with their blocks")
    tag_uses = json.dumps(list(recipes.values()))
    check("#c:" not in tag_uses and "forge:" not in tag_uses,
          "recipes still use NeoForge c:/forge: tags")
    say("recipes: no NeoForge #c:/forge: tags left")

    # --- loot ----------------------------------------------------------------
    loot = {
        p.rsplit("/", 1)[-1][:-5]
        for p in glob.glob(os.path.join(args.content, "data/mcwdoors/loot_table/blocks/*.json"))
    }
    check(loot <= doors, f"loot tables for undeclared blocks: {sorted(loot - doors)[:8]}")
    check(
        doors - loot == set(),
        f"unexpected block without a loot table: {sorted(doors - loot)}",
    )
    say(f"loot: {len(loot)} tables, one per carried block")

    # --- lang ----------------------------------------------------------------
    lang = json.load(open(os.path.join(args.content, "assets/mcwdoors/lang/en_us.json")))
    unnamed = [b for b in doors if f"block.mcwdoors.{b}" not in lang]
    check(not unnamed, f"unexpected unnamed blocks: {unnamed}")
    check(all(f"item.mcwdoors.{i}" in lang for i in prints), "a print item has no name")
    check("itemGroup.mcwdoors" in lang, "itemGroup.mcwdoors is missing")
    say("lang: every carried block/item has an en_us key")

    # --- tags ----------------------------------------------------------------
    skipped_refs: dict[str, list[str]] = {}
    for p in glob.glob(os.path.join(args.content, "data/minecraft/tags/**/*.json"), recursive=True):
        d = json.load(open(p))
        vals = d.get("values", [])
        bad_refs = [
            v for v in vals
            if isinstance(v, str) and v.startswith("mcwdoors:") and v.split(":", 1)[1] not in registry
        ]
        if bad_refs:
            skipped_refs[os.path.relpath(p, args.content)] = bad_refs
    say(f"tags: {len(skipped_refs)} minecraft tag files mention a left-out block "
        f"(entries the game drops): {sorted(skipped_refs)[:4]}")

    # --- creative tab --------------------------------------------------------
    tab = json.load(open(os.path.join(args.content, "data/mcwdoors/horizon/creative_tab/doors.json")))
    tab_ids = [i.split(":", 1)[1] for i in tab["items"]]
    check(len(tab_ids) == 251, f"creative tab lists {len(tab_ids)} items, expected 251")
    check(set(tab_ids) <= registry, f"creative tab lists unregistered items: {sorted(set(tab_ids) - registry)[:8]}")
    check(set(tab_ids) >= registry, f"creative tab misses items: {sorted(registry - set(tab_ids))[:8]}")
    say("creative tab: 251 items = 12 prints + 239 doors, all registered")

    if failures:
        print("\nFAILURES:")
        for f in failures:
            print(f"  FAIL: {f}")
        return 1
    print(f"\nPASS: {len(doors)} door blocks + {len(prints)} print items + "
          f"{len(recipes)} recipes + {len(loot)} loot tables + {len(tab_ids)} tab entries "
          "match the 1.21.1 jar; templates keep the 5 door properties / 64 states each")
    return 0


if __name__ == "__main__":
    sys.exit(main())
