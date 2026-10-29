# Feature and settings inventory

Status: design inventory, including future capabilities. The [README](../../README.md#what-it-does) is the shipped feature contract. Prototype interactions simulate all operations and use synthetic data; a feature appearing here does not mean it is implemented.

## Resource and workflow scope

| Area | First release | Follow-up / explored in prototype |
| --- | --- | --- |
| Containers | Compose grouping; standalone section; search; state filters; start/stop/restart; logs; inspect; ports; metrics | Run from image; terminal/exec; file browsing; duplicate/recreate configuration |
| Compose | Discover projects from Compose labels; aggregate service state; control existing containers | Register local Compose files; profiles; environment-file references; validate; apply/recreate; build/pull controls |
| Groups | Automatic Compose projects; preserve disclosure state | Custom named groups/favorites, scoped to context, without changing Docker ownership |
| Images | List tags, size, architecture, usage; inspect | Pull, run, delete with preview, build history |
| Volumes | List driver, size when available, mount references, usage; inspect | Explicit deletion; backup/export investigation |
| Networks | List driver, subnet, attached containers; inspect | Create/remove with affected-resource preview |
| Activity | In-progress operations; partial failures; retry; engine state | Searchable local operation history; redacted diagnostics export |
| Engine | Connect to existing local context; detect Colima status; explain recovery | Deliberate Colima start/stop; runtime resource editing; more connection types |

## Grouping contract

- Compose project identity is scoped to an engine context; service/replica metadata comes from Compose labels. Names alone do not establish ownership.
- Multiple replicas appear under their service. One-off containers are marked separately.
- Aggregate states include running, stopped, partially running, starting, stopping, and unhealthy. Running does not imply healthy; unavailable health checks display as unavailable.
- A collapsed group still shows a running/total count and unhealthy count. Filter matches temporarily expose matching children without overwriting saved disclosure state.
- Standalone containers remain visible. Custom groups are app metadata and can include references to resources; removing a custom group never removes a container.
- A group action reports each result and retains successful operations if another service fails. Repeated clicks while pending are disabled.

## Operation vocabulary

| UI action | Meaning | Guardrail |
| --- | --- | --- |
| Start container | Start an existing container | Never silently create or replace it |
| Start project | Start existing Compose containers | When the Compose files cannot be resolved, offer an explicitly named bulk start of discovered containers; do not imply dependency handling |
| Apply Compose | Validate configuration and run the chosen `compose up` operation | Preview project, files, profiles, build/pull behavior, and possible recreation; require a known, authorized local file set |
| Stop project | Stop existing containers | Keep containers, networks, and volumes |
| Restart | Restart existing resources | State that changed environment/image configuration is not applied |
| Remove container | Delete exactly selected container(s) | Separate volume deletion; explain writable-layer loss; handle running state explicitly |
| Remove project resources | Explicit teardown operation | Show the plan; volumes excluded by default; separate volume confirmation |
| Start custom group | Start referenced existing containers | No implied dependency ordering |
| Edit container configuration | Update supported live fields or explicitly recreate | Ports/environment/mount changes are not presented as universally editable in place |

## Settings inventory

Settings are categorized by owner: **App**, **Runtime**, **Container**, or **Project**. Runtime-dependent options require capability/version checks before enabling. The settings design uses explicit Apply/Cancel for runtime changes; application appearance changes are immediate.

| Category | Proposed controls | Owner / application behavior |
| --- | --- | --- |
| General | Open app at login; menu bar visibility; close-window behavior; default screen; check for updates | App; opening the app is separate from starting the engine |
| Appearance | System/light/dark; compact/comfortable rows; interface text size; log text size; reduced motion; visible columns | App; use system accessibility preferences and allow readable scaling |
| Connections | Selected local Docker context; resolved socket; CLI/Compose executable paths; timeout; reconnect; diagnostics | App; no global context switch; no unauthenticated TCP endpoint |
| Startup | Start the selected Colima profile when app opens; opt-in project startup | App/runtime; default off; honor existing container restart policies and avoid competing startup mechanisms |
| Resources | VM CPUs, memory in GiB, disk capacity in GiB | Runtime; preview affected profile; CPU/memory changes may require restart; disk expansion only after creation |
| Runtime details | Architecture, VM type, mounts, mount type, Rosetta availability | Runtime; immutable values read-only for existing profiles; never silently recreate a VM |
| File sharing | Authorized shared directories and read/write access | Runtime; changes can require restart; path selection and scope must be explicit |
| Networking | DNS, host mappings, port-forward behavior, supported network mode | Runtime; capability/version gated; mark restart and connectivity effects |
| Proxy / certificates | Use supported proxy configuration; registry CA/certificate diagnostics | Runtime/tooling; separate app networking from daemon/build networking; credential handling must be designed before shipping |
| Registries | Credential-helper status; registry endpoint metadata; authentication entry points | Docker tooling; use existing credential helpers/Keychain; never display raw stored credentials |
| Containers | Default grouping, stopped/system visibility, sort/columns, refresh frequency, default stop timeout | App; timeout defaults do not rewrite a container's existing configuration |
| Logs & terminal | Tail count, bounded session buffer, timestamps, wrap, text size, preferred shell, copy/export | App; session display buffer is different from Docker's daemon log-retention policy; terminal is a later feature |
| Notifications | Operation failures, unhealthy/exited containers, engine disconnect, successful long tasks | App; macOS permission prompt only after enabling notifications |
| Safety & privacy | Resource-removal confirmations; explicit cleanup preview; redacted diagnostics; telemetry off | App; destructive previews always identify context and exact targets; no automatic volume cleanup |
| Advanced | API compatibility information; supported tool versions; open runtime config; reset app preferences | App/tooling; reset preferences does not reset engine data; raw daemon configuration editing deferred |
| About & updates | Version, release notes, update channel, licenses, project links | App; signed/notarized releases; update signing design required before automatic updates |

Per-container settings (restart policy, resource limits, environment, ports, mounts, command, health checks) belong in the resource detail/run flow. Compose profiles, files, environment files, project directory, and build/pull behavior belong in the project view. They should not be hidden in global application settings.

## Startup distinctions

1. Launching the app at login opens the interface.
2. Starting Colima starts the engine VM.
3. Docker restart policies determine whether eligible existing containers start when the daemon starts.
4. Applying a Compose project can create or recreate containers and needs a separate explicit action.

## Sources checked

- [Compose start](https://docs.docker.com/reference/cli/docker/compose/start/): existing containers.
- [Compose up](https://docs.docker.com/reference/cli/docker/compose/up/): creation/recreation behavior.
- [Docker restart policies](https://docs.docker.com/engine/containers/start-containers-automatically/): daemon-owned restart behavior.
- [Colima configuration](https://colima.run/docs/configuration/): resource units, disk expansion, immutable runtime settings, mounts, and networking.
