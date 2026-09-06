# FlowSpace System Node Graph

> Visible UI is a shipping claim. Every visible surface and control must resolve to real code, state, authority, persistence, and proof.

This file is generated. Edit `system_graph/flowspace.systemgraph.contract.json` or source code, then regenerate it.

- Source fingerprint: `d064d5132450544a877c19e7dfcfd6230f6350e5cb7310d974fe4f5cb648c140`
- Nodes: 422
- Edges: 378
- Contract nodes: 23

## Shipping surfaces

| Graph node | Surface | Source | Proof |
| --- | --- | --- | --- |
| `surface.system_graph` | System | `client_flutter/lib/ui/screens/system_graph_screen.dart` | `client_flutter/test/system_graph_screen_test.dart` |
| `surface.onboarding.welcome` | Welcome | `client_flutter/lib/ui/onboarding/welcome_screen.dart` | `client_flutter/test/shipping_surface_contract_test.dart` |
| `surface.onboarding.login` | Login | `client_flutter/lib/ui/onboarding/login_screen.dart` | `client_flutter/test/shipping_surface_contract_test.dart` |
| `surface.onboarding.setup` | Create local account | `client_flutter/lib/ui/onboarding/setup_user_screen.dart` | `client_flutter/test/shipping_surface_contract_test.dart` |
| `surface.onboarding.setup_complete` | Local account ready | `client_flutter/lib/ui/onboarding/setup_complete_screen.dart` | `client_flutter/test/shipping_surface_contract_test.dart` |

## Quarantined surfaces

These files remain in the repository, but are not reachable from the shipping shell.

| Graph node | Surface | Reason |
| --- | --- | --- |
| `surface.workspace` | Workspace | Hard-coded user, workspace, activity, project, progress, and release data plus empty navigation actions. |
| `surface.streams` | Streams | Core read/send paths have local fallback, but visible reactions, threads, pins, and header actions are not locally wired. |
| `surface.connect` | Connect | Visible meeting actions require backend endpoints and have no truthful local-mode capability path. |
| `surface.calendar` | Calendar | The visible surface is a date picker without event state, persistence, scheduling, or calendar tests. |
| `surface.vault` | Vault | Listing can fall back to SQLite, but visible upload, delete, and open paths are not a complete local-first contract. |
| `surface.projects` | Projects | Local project/task code exists, but the complete visible journey lacks an isolated integration proof and graph-bound control inventory. |
| `surface.settings` | Settings | The visible settings tree contains null handlers and explicit coming-soon actions. |

## Commands

```powershell
python scripts/system_graph/generate_system_graph.py
python scripts/system_graph/verify_system_graph.py
```

The visual graph is bundled into the app and is also available in `docs/system_graph/FLOWSPACE_SYSTEM_GRAPH.html`.
