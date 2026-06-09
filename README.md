# BMF Omegga Windows Runtime Fork

This repository is the BMF-supported Omegga fork for Windows Brickadia
dedicated-server automation.

Use this fork when BMF documentation says the supported Omegga runtime:

- BMF repository: <https://github.com/Ty-lerCox/brickadia-modding-framework>
- Supported Omegga fork: <https://github.com/Ty-lerCox/bmf-omegga-fork>

Stock upstream Omegga and the global npm package are Linux/WSL-oriented and are
not the supported Windows runtime for BMF. This fork intentionally trails the
latest upstream Omegga builds because BMF validates against the Windows/UE4SS
bridge surfaces in this repository.

## What This Fork Provides

- Windows-oriented Omegga runtime support for BMF.
- UE4SS bridge templates, including `OmeggaBridge`.
- BMF command routing through `Omegga.Bridge.BMF`.
- Helper surfaces used by BMF canaries and live-player APIs.
- Packaging hooks for BMF/Omegga integration work.

This repository is not a general replacement for upstream Omegga. Use upstream
Omegga for generic Linux/WSL Omegga server work unless BMF specifically requires
the Windows runtime fork.

## Layout

```text
omegga-master/omegga-master/      Omegga runtime source and templates
docs/                             BMF/Omegga bridge and prefab API notes
brickadia-ue4ss-re/               Brickadia UE4SS compatibility workspace
scripts/                          Local helper scripts
```

Generated runtime data, local Brickadia server state, logs, and build outputs
are intentionally ignored.

## Development

From the Omegga source directory:

```powershell
cd .\omegga-master\omegga-master
npm install
npm run build
```

Build the Windows console bridge when changing bridge code:

```powershell
npm run build:bridge
```

Run package or BMF validation from the BMF repository when the change affects
BMF behavior. Keep BMF documentation and this fork's runtime contract aligned.

## Runtime Contract

When updating this fork, keep these BMF-facing surfaces intact unless the BMF
repo is updated and validated at the same time:

- `Omegga.Bridge.BMF`
- `Omegga.Bridge.ForceConsoleExecutor`
- `OmeggaBridge`
- `OmeggaExecuteConsoleManagerInput`
- `OmeggaExecuteKismetConsoleCommand`
- `OmeggaExecuteCachedConsoleExec`
- `OmeggaCallFunctionByNameWithArguments`

Environment preset reloads are part of this contract. The Omegga fork routes
`Server.Environment.LoadPreset ...` and `Server.Environment.Reset` through
`Omegga.Bridge.ForceConsoleExecutor consolemanager ...` on the Windows UE4SS
runtime so plugins can apply weather/environment files without restarting the
Brickadia server.

Do not replace this fork with a newer upstream Omegga build until BMF has
validated that build against the Windows UE4SS bridge, player-sync adapters,
command transport, and canaries.
