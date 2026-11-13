# Scrap Heist: models in Studio

The game-specific parts of "Importing into Studio" in `framework/docs/art/pipeline.md`. Paths are relative to `proof/scrap-heist` unless they start with `framework/`.

## Bots, machines, crates and weapons

1. `framework/scripts/build-model.sh Scrapper Bruiser Zapper SalvageMachine PartBundle StarterWeapon BigSpanner`
   (for the bots this also refreshes their clip modules in
   `src/shared/Animations`, which `BotAnimationController` plays). The bots
   use the clips `Idle`, `Move` and `Attack`. `art/models/PartBundle/model.luau`
   is a short reference for the script API.
2. `ROBLOX_API_KEY=... ROBLOX_CREATOR_ID=<user id> framework/scripts/upload-model.sh <Name>...`
   uploads each GLB as a Model and writes its ID into `Assets.Models`.
3. In Studio (edit mode, Rojo synced) run `framework/studio/PlaceModels.luau`
   in the command bar, then save the place. It loads:
   - each bot into `ServerStorage.NpcModels`, with a HumanoidRootPart,
     Humanoid and Head built round the imported rig, for `NpcRig`;
   - the salvage machine's tiers into `ServerStorage.MachineModels` as
     `SalvageMachine1`-`3`, pivoted at their art centre, for `MachineService`;
   - the storage crate's six heaps into `ServerStorage.CrateFills`, lined up
     on Yard1's crate in the placed map (so run `PlaceMap` first), for
     `PlotService`;
   - the part bundle's fill levels into `ServerStorage.PartBundle`, for
     `RaidService`;
   - the weapons into `ServerStorage.WeaponModels`, named after their
     WeaponConfig weapon (StarterWeapon is the Bat, BigSpanner the Spanner)
     with a `Grip` attachment, for `HeldWeaponService`.

The storage crate model is not in this proof copy's `art/src`.

## The Server Map

- `ServerMap` is the default layout. Its ledger is `art/src/layouts/ServerMapUploads.tsv`, and a second build with nothing changed took about 15 s against 100 s cold.
- Copies of one model are one object: the eight yard islands, every fence panel.
- `PlaceMap` files every part under `workspace.Map` by object: `Map > Line > Walk > 1_0_0`, `Map > Yard1 > Gate > Frame`. It turns collision off on the yard gates, then hooks the map up to the game: `YardSpots`, a SpawnLocation, and the kit.
- The game is owned by a group and the uploads by a user, so each new asset needs the game's permission.

## The kit

Models the game places itself (pads, the build bay, the crate, the mound, the press, each tier's capsule and each junkrot) are built in the layout, one of each under the label `Kit_<Name>`, out of sight under the hub (`KIT` at the end of `ServerMap.luau`). `PlaceMap` files them where the game clones them from: `Capsule<Tier>` in `ServerStorage.Capsules` as `<Tier>`, `Junkrot<Id>` in `ServerStorage.Junkrots` as `<Id>`, and the rest in `ServerStorage.YardKit`. Where a model is missing the game shows a plain block, so a junkrot can ship before its art.
