#!/usr/bin/env python3
"""Generate FlowSpace's deterministic system graph from source and contract."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Iterable


REPO_ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = REPO_ROOT / "system_graph" / "flowspace.systemgraph.contract.json"
OUTPUT_PATHS = {
    "json": REPO_ROOT
    / "client_flutter"
    / "assets"
    / "system_graph"
    / "flowspace_system_graph.json",
    "docs_json": REPO_ROOT
    / "docs"
    / "system_graph"
    / "FLOWSPACE_SYSTEM_GRAPH.json",
    "markdown": REPO_ROOT
    / "docs"
    / "system_graph"
    / "FLOWSPACE_SYSTEM_GRAPH.md",
    "html": REPO_ROOT
    / "docs"
    / "system_graph"
    / "FLOWSPACE_SYSTEM_GRAPH.html",
}
SOURCE_ROOTS = (
    REPO_ROOT / "client_flutter" / "lib",
    REPO_ROOT / "client_flutter" / "test",
    REPO_ROOT / "backend" / "src",
)
SOURCE_SUFFIXES = {".dart", ".ts"}
DART_IMPORT = re.compile(r"^\s*import\s+['\"]([^'\"]+)['\"]", re.MULTILINE)
TS_IMPORT = re.compile(
    r"(?:from\s+|import\s*)['\"](\.[^'\"]+)['\"]", re.MULTILINE
)


def relative(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def digest_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def source_files() -> list[Path]:
    files: list[Path] = []
    for root in SOURCE_ROOTS:
        if not root.exists():
            continue
        files.extend(
            path
            for path in root.rglob("*")
            if path.is_file() and path.suffix in SOURCE_SUFFIXES
        )
    return sorted(files, key=relative)


def classify(path: Path) -> tuple[str, str]:
    rel = relative(path)
    if rel.endswith("/main.dart"):
        return "entry", "entry"
    if "/test/" in rel:
        return "validation", "test"
    if rel.startswith("backend/"):
        if "/entities/" in rel or rel.endswith(".entity.ts"):
            return "domain", "model"
        return "backend", "backend"
    if "/ui/screens/" in rel or "/ui/views/" in rel or "/ui/onboarding/" in rel:
        return "surface", "surface"
    if "/ui/" in rel or "/widgets/" in rel or "/modules/" in rel:
        return "surface", "component"
    if "/state/" in rel or "/providers/" in rel or "/sync/" in rel:
        return "state", "state"
    if "/services/" in rel:
        return "service", "service"
    if "/models/" in rel or "/engine/" in rel or "/core/" in rel:
        return "domain", "domain"
    return "domain", "source"


def file_node(path: Path) -> dict[str, Any]:
    rel = relative(path)
    layer, kind = classify(path)
    return {
        "id": f"file:{rel}",
        "label": path.name,
        "layer": layer,
        "kind": kind,
        "status": "present",
        "contract": False,
        "path": rel,
        "sha256": digest_bytes(path.read_bytes()),
    }


def resolve_import(source: Path, import_path: str, known: set[Path]) -> Path | None:
    if import_path.startswith("package:flo/"):
        candidate = REPO_ROOT / "client_flutter" / "lib" / import_path.removeprefix(
            "package:flo/"
        )
    elif import_path.startswith("."):
        candidate = source.parent / import_path
    else:
        return None

    candidates = [candidate]
    if candidate.suffix == "":
        candidates.extend(
            [candidate.with_suffix(".dart"), candidate.with_suffix(".ts"), candidate / "index.ts"]
        )
    normalized = [Path(os.path.normpath(str(item))) for item in candidates]
    return next((item for item in normalized if item in known), None)


def import_edges(files: Iterable[Path]) -> list[dict[str, str]]:
    file_list = list(files)
    known = set(file_list)
    edges: set[tuple[str, str, str]] = set()
    for source in file_list:
        text = source.read_text(encoding="utf-8", errors="replace")
        imports = DART_IMPORT.findall(text) if source.suffix == ".dart" else TS_IMPORT.findall(text)
        for import_path in imports:
            target = resolve_import(source, import_path, known)
            if target is not None:
                edges.add(
                    (f"file:{relative(source)}", f"file:{relative(target)}", "imports")
                )
    return [
        {"from": source, "to": target, "kind": kind}
        for source, target, kind in sorted(edges)
    ]


def load_contract() -> dict[str, Any]:
    return json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))


def contract_surface_nodes(contract: dict[str, Any]) -> list[dict[str, Any]]:
    nodes: list[dict[str, Any]] = []
    for item in contract["shipping_surfaces"]:
        nodes.append(
            {
                "id": item["id"],
                "label": item["label"],
                "layer": "surface",
                "kind": "surface",
                "status": item["status"],
                "contract": True,
                "visible": True,
                "nav_visible": item["nav_visible"],
                "path": item["source"],
                "symbol": item["symbol"],
                "test": item["test"],
            }
        )
    for item in contract["quarantined_surfaces"]:
        nodes.append(
            {
                "id": item["id"],
                "label": item["label"],
                "layer": "surface",
                "kind": "surface",
                "status": "quarantined",
                "contract": True,
                "visible": False,
                "nav_visible": False,
                "path": item["source"],
                "reason": item["reason"],
            }
        )
    return nodes


def build_graph() -> tuple[dict[str, Any], dict[str, Any]]:
    contract = load_contract()
    files = source_files()
    nodes = [file_node(path) for path in files]
    nodes.extend(contract_surface_nodes(contract))
    nodes.extend(contract["manual_nodes"])

    node_map: dict[str, dict[str, Any]] = {}
    for node in nodes:
        if node["id"] in node_map:
            raise ValueError(f"duplicate graph node: {node['id']}")
        node_map[node["id"]] = node

    edges = import_edges(files) + list(contract["manual_edges"])
    edge_map = {
        (edge["from"], edge["to"], edge["kind"]): edge for edge in edges
    }
    for edge in edge_map.values():
        if edge["from"] not in node_map:
            raise ValueError(f"edge source is missing: {edge['from']}")
        if edge["to"] not in node_map:
            raise ValueError(f"edge target is missing: {edge['to']}")

    ordered_nodes = sorted(node_map.values(), key=lambda node: node["id"])
    ordered_edges = [edge_map[key] for key in sorted(edge_map)]
    fingerprint_input = "\n".join(
        f"{node['path']}\0{node['sha256']}"
        for node in ordered_nodes
        if node["id"].startswith("file:")
    ).encode("utf-8")
    status_counts = Counter(node["status"] for node in ordered_nodes)
    layer_counts = Counter(node["layer"] for node in ordered_nodes)

    graph = {
        "schema": "flowspace.systemgraph.v1",
        "title": contract["title"],
        "product_rule": contract["product_rule"],
        "source_fingerprint": digest_bytes(fingerprint_input),
        "layer_order": contract["layer_order"],
        "summary": {
            "nodes": len(ordered_nodes),
            "edges": len(ordered_edges),
            "contract_nodes": sum(bool(node.get("contract")) for node in ordered_nodes),
            "statuses": dict(sorted(status_counts.items())),
            "layers": dict(sorted(layer_counts.items())),
        },
        "nodes": ordered_nodes,
        "edges": ordered_edges,
    }
    return graph, contract


def json_text(graph: dict[str, Any]) -> str:
    return json.dumps(graph, indent=2, ensure_ascii=False) + "\n"


def markdown_text(graph: dict[str, Any], contract: dict[str, Any]) -> str:
    shipping = "\n".join(
        f"| `{item['id']}` | {item['label']} | `{item['source']}` | `{item['test']}` |"
        for item in contract["shipping_surfaces"]
    )
    quarantined = "\n".join(
        f"| `{item['id']}` | {item['label']} | {item['reason']} |"
        for item in contract["quarantined_surfaces"]
    )
    return f"""# FlowSpace System Node Graph

> {graph['product_rule']}

This file is generated. Edit `system_graph/flowspace.systemgraph.contract.json` or source code, then regenerate it.

- Source fingerprint: `{graph['source_fingerprint']}`
- Nodes: {graph['summary']['nodes']}
- Edges: {graph['summary']['edges']}
- Contract nodes: {graph['summary']['contract_nodes']}

## Shipping surfaces

| Graph node | Surface | Source | Proof |
| --- | --- | --- | --- |
{shipping}

## Quarantined surfaces

These files remain in the repository, but are not reachable from the shipping shell.

| Graph node | Surface | Reason |
| --- | --- | --- |
{quarantined}

## Commands

```powershell
python scripts/system_graph/generate_system_graph.py
python scripts/system_graph/verify_system_graph.py
```

The visual graph is bundled into the app and is also available in `docs/system_graph/FLOWSPACE_SYSTEM_GRAPH.html`.
"""


def html_text(graph: dict[str, Any]) -> str:
    embedded = json.dumps(graph, ensure_ascii=False).replace("</", "<\\/")
    title = html.escape(graph["title"])
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<style>
:root{{--bg:#0a0e14;--panel:#111823;--line:#334155;--text:#f8fafc;--muted:#a9b7c8;--accent:#62e6b8;--warn:#f3b65c}}
*{{box-sizing:border-box}} body{{margin:0;background:var(--bg);color:var(--text);font:14px/1.45 system-ui,sans-serif}}
header{{position:sticky;top:0;z-index:2;padding:18px 24px;background:#0a0e14ee;border-bottom:1px solid var(--line)}}
h1{{font-size:20px;margin:0 0 4px}} p{{color:var(--muted);margin:0}} main{{padding:20px;display:grid;gap:18px}}
.stats{{display:flex;gap:10px;flex-wrap:wrap}} .pill{{padding:7px 10px;border:1px solid var(--line);border-radius:99px;background:var(--panel)}}
#graph{{min-width:1100px;display:grid;grid-template-columns:repeat(9,minmax(180px,1fr));gap:14px;align-items:start}}
.layer{{display:grid;gap:9px}} h2{{font-size:12px;text-transform:uppercase;letter-spacing:.12em;color:var(--muted)}}
.node{{padding:10px;border:1px solid var(--line);border-radius:8px;background:var(--panel);overflow-wrap:anywhere}}
.node.contract{{border-color:var(--accent)}} .node.quarantined{{border-color:var(--warn);opacity:.78}}
.kind{{color:var(--muted);font-size:11px}} .path{{font:10px ui-monospace,monospace;color:#b8c4d2;margin-top:6px}}
</style></head>
<body><header><h1>{title}</h1><p>{html.escape(graph['product_rule'])}</p></header>
<main><div class="stats" id="stats"></div><div style="overflow:auto"><section id="graph"></section></div></main>
<script>const graph={embedded};
const stats=document.querySelector('#stats');
for(const [k,v] of Object.entries(graph.summary)){{if(typeof v!=='object')stats.insertAdjacentHTML('beforeend',`<span class="pill">${{k}}: <b>${{v}}</b></span>`)}}
const root=document.querySelector('#graph');
for(const layer of graph.layer_order){{const col=document.createElement('div');col.className='layer';col.innerHTML=`<h2>${{layer}}</h2>`;
for(const n of graph.nodes.filter(n=>n.layer===layer)){{const el=document.createElement('article');el.className=`node ${{n.contract?'contract':''}} ${{n.status==='quarantined'?'quarantined':''}}`;el.title=n.id;el.innerHTML=`<b>${{n.label}}</b><div class="kind">${{n.kind}} · ${{n.status}}</div><div class="path">${{n.path||''}}</div>`;col.appendChild(el)}}root.appendChild(col)}}
</script></body></html>
"""


def outputs(graph: dict[str, Any], contract: dict[str, Any]) -> dict[Path, str]:
    payload = json_text(graph)
    return {
        OUTPUT_PATHS["json"]: payload,
        OUTPUT_PATHS["docs_json"]: payload,
        OUTPUT_PATHS["markdown"]: markdown_text(graph, contract),
        OUTPUT_PATHS["html"]: html_text(graph),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if generated files are stale")
    args = parser.parse_args()
    graph, contract = build_graph()
    generated = outputs(graph, contract)
    stale: list[str] = []
    for path, content in generated.items():
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != content:
                stale.append(relative(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
            print(f"generated {relative(path)}")
    if stale:
        print("stale system graph outputs:", file=sys.stderr)
        for path in stale:
            print(f"  {path}", file=sys.stderr)
        print("run: python scripts/system_graph/generate_system_graph.py", file=sys.stderr)
        return 1
    if args.check:
        print(
            f"system graph is fresh: {graph['summary']['nodes']} nodes, "
            f"{graph['summary']['edges']} edges"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
