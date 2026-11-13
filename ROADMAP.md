# Roadmap

The plan for this game. It is the authority on tooling, dependencies, folder
layout, lifecycle, naming, comments, server authority and commit format.
`CLAUDE.md` only adds style rules on top. Fill in the empty sections before
the first phase starts.

## 1. What we're building

One paragraph: the game, who plays it, and what a session feels like.
List the systems it needs and the final deliverables.

## 2. Tech stack and tooling

- **Language:** Luau, `--!strict` at the top of every module.
- **Project sync:** [Rojo](https://rojo.space) (`default.project.json`).
- **Packages:** [Wally](https://wally.run) for dependencies.
- **Formatting and linting:** StyLua and Selene, with config files committed.
- **Unit tests:** [Lune](https://lune-org.github.io/docs) runs specs in
  `tests/` outside Studio, with a small in-repo runner (`tests/run.luau`), no
  test framework package.
- **Toolchain manager:** Rokit, with a `rokit.toml` pinning Rojo, Wally,
  StyLua, Selene and Lune versions.
- **No other frameworks** (no Knit, no full networking libraries) unless the
  owner approves. Plain modules are easier to read and explain.

## 3. Folder structure

Create folders as phases need them, not all up front.

```
./
├── ROADMAP.md                 # this file
├── CLAUDE.md, AGENTS.md       # agent rules
├── game.toml                  # names and numbers the framework reads
├── default.project.json       # Rojo tree
├── wally.toml, rokit.toml, selene.toml, stylua.toml
├── framework/                 # shared, pinned copy; never edited here
├── art/
│   ├── src/                   # model sources
│   └── models/                # generated from art/src; never edit by hand
├── docs/
│   └── team/                  # the agent team's rules and log
├── tests/                     # Lune unit tests, never synced into Studio
│   ├── run.luau               # runner: `lune run tests/run`
│   ├── Test.luau              # describe / it / expect
│   ├── Roblox.luau            # fakes for the engine bits modules touch
│   ├── Source.luau            # resolves Roblox requires to files
│   └── shared/ server/ ...    # *.spec.luau, mirroring src/
└── src/
    ├── shared/                # ReplicatedStorage.Shared
    │   ├── Config/            # tuning tables
    │   ├── Net/               # remote definitions, one module per system
    │   └── Util/              # small pure helpers (Boot, Signal, Trove, ...)
    ├── server/                # ServerScriptService.Server
    │   ├── init.server.luau   # single entry point, boots services in order
    │   ├── Services/          # one <System>Service.luau per system
    │   └── <System>/          # a system's rules modules and <System>Types.luau
    └── client/                # StarterPlayerScripts.Client
        ├── init.client.luau   # single entry point, boots controllers
        ├── Controllers/       # one <System>Controller.luau per system
        └── UI/                # Kit/ primitives and Screens/
```

Each system keeps its shared types in its own `<System>Types.luau` with
`export type`.

## 4. Conventions (apply everywhere)

### Server authority
- The **server decides everything that matters**: damage, currency, item
  grants, trades, loot. Clients only send *intent* ("I want to attack",
  "I want to buy X").
- Every remote handler validates: argument types, player state, distance,
  cooldowns and ownership.
- Rate-limit every client-to-server remote.

### Code style
- `--!strict` and typed function signatures everywhere.
- One service or controller per file. Each exposes `init()` and `start()`;
  the entry script calls all `init()`s, then all `start()`s.
- `PascalCase` for modules and types, `camelCase` for functions and locals,
  `UPPER_SNAKE` for constants.
- No magic numbers in logic. Tuning goes in `src/shared/Config/`.
- Every asset ID lives in one asset table (`Assets.luau` in `src/shared`).
  Code checks `Assets.isSet(id)` and skips the effect when it's a placeholder.
- Clean up connections on player leave and object destroy (use `Trove`).

### Testing
- Split each system into a **rules module** (plain tables in, results out;
  time passed in as `now` or an injected clock) and a **service** (remotes,
  instances, `Players` events) that calls it. Rules modules get Lune specs;
  service glue gets Studio checklist steps.
- Write the spec with the code, not after. A task is ticked only when its
  specs pass (`lune run tests/run`) and its Studio test passes.
- Specs mirror `src/` (`tests/shared/Util/Signal.spec.luau` tests
  `src/shared/Util/Signal.luau`) and load source with
  `Source.require("src/...")`, which resolves normal Roblox requires to files.
  Game code needs no test-only require style.
- Only fake engine pieces in `tests/Roblox.luau`, and only what code under
  test actually touches.

### Comments
- Every file starts with a header block: what the module does, how it fits
  with other modules, and its public API.
- Comment the **why**, not the what.
- Mark every anti-exploit check with `-- SECURITY:` and every anti-dupe step
  with `-- DUPE-SAFE:` so they're easy to find.
- Keep comments plain English. No jargon without a one-line explanation.

### Git
- Small commits, one task per commit, message format: `phase N: short summary`.
- Never commit `.rbxl` / `.rbxlx` place files (ignored in `.gitignore`).

## 5. Phases

One heading per phase, in order. Each task lists its acceptance criteria
(*Done when:*) and a Studio test where code alone can't prove it.

## 6. Definition of done

A checklist for the whole game: what must work, with how many players, and
which checks pass (`selene`, `stylua --check`, `lune run tests/run`).

## 7. Rules for the agent

1. Read this file and the current code before each session.
2. Don't skip ahead. Finish a phase's acceptance criteria first.
3. Don't add frameworks or libraries beyond those in section 2 without asking.
4. Don't wait on art. Placeholders always.
5. When a task needs a Studio check, write the test steps and tell the owner
   exactly what to try.
6. Keep this file updated: tick boxes, and add a short note under a task if
   the plan changed.
