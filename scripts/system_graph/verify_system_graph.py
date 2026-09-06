#!/usr/bin/env python3
"""Fail closed when FlowSpace's visible product and system graph diverge."""

from __future__ import annotations

import json
import re
import sys
from collections import deque
from pathlib import Path

import generate_system_graph as generator


ROOT = generator.REPO_ROOT
REGISTRY_PATH = ROOT / "client_flutter/lib/system_graph/shipping_surface_registry.dart"
SHELL_PATH = ROOT / "client_flutter/lib/ui/shell/app_shell.dart"
MAIN_PATH = ROOT / "client_flutter/lib/main.dart"
FORBIDDEN_UI_MARKERS = (
    re.compile(r"\bTODO\b", re.IGNORECASE),
    re.compile(r"coming[ -]soon", re.IGNORECASE),
    re.compile(r"\bplaceholder\b", re.IGNORECASE),
    re.compile(r"on(?:Pressed|Tap)\s*:\s*\(\)\s*\{\s*\}", re.MULTILINE),
    re.compile(r"on(?:Pressed|Tap)\s*:\s*null\b", re.MULTILINE),
)


class VerificationError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def verify_generated_outputs(graph: dict, contract: dict) -> None:
    for path, expected in generator.outputs(graph, contract).items():
        require(path.exists(), f"generated output is missing: {generator.relative(path)}")
        actual = path.read_text(encoding="utf-8")
        require(
            actual == expected,
            f"generated output is stale: {generator.relative(path)}; run the generator",
        )


def verify_evidence(contract: dict, graph: dict) -> None:
    graph_nodes = {node["id"]: node for node in graph["nodes"]}
    for node_id, node in graph_nodes.items():
        require(node.get("layer"), f"node has no layer: {node_id}")
        require(node.get("kind"), f"node has no kind: {node_id}")
        require(node.get("status"), f"node has no status: {node_id}")
        evidence_path = node.get("path")
        if evidence_path:
            require(
                (ROOT / evidence_path).is_file(),
                f"evidence path does not exist for {node_id}: {evidence_path}",
            )
            symbol = node.get("symbol")
            if symbol:
                source = (ROOT / evidence_path).read_text(
                    encoding="utf-8", errors="replace"
                )
                require(
                    symbol in source,
                    f"evidence symbol {symbol!r} is absent for {node_id}",
                )

    for edge in graph["edges"]:
        require(edge["from"] in graph_nodes, f"edge source is absent: {edge['from']}")
        require(edge["to"] in graph_nodes, f"edge target is absent: {edge['to']}")

    quarantined = {item["id"] for item in contract["quarantined_surfaces"]}
    for node_id in quarantined:
        node = graph_nodes[node_id]
        require(node["status"] == "quarantined", f"{node_id} is not quarantined")
        require(node["visible"] is False, f"{node_id} is incorrectly visible")


def verify_shipping_registry(contract: dict) -> None:
    registry = REGISTRY_PATH.read_text(encoding="utf-8")
    registered_ids = re.findall(r"graphNodeId:\s*'([^']+)'", registry)
    expected_ids = [
        item["id"] for item in contract["shipping_surfaces"] if item["nav_visible"]
    ]
    require(
        registered_ids == expected_ids,
        f"shipping registry {registered_ids} does not match contract {expected_ids}",
    )

    reachable_paths = [REGISTRY_PATH, SHELL_PATH, MAIN_PATH]
    reachable_paths.extend(ROOT / item["source"] for item in contract["shipping_surfaces"])
    reachable_source = "\n".join(
        path.read_text(encoding="utf-8") for path in reachable_paths
    )
    for item in contract["quarantined_surfaces"]:
        basename = Path(item["source"]).name
        require(
            basename not in reachable_source,
            f"quarantined surface is reachable from the shipping shell: {basename}",
        )
    require("app_router.dart" not in reachable_source, "dormant AppRouter is shipping")
    require(
        "workspace_shell.dart" not in reachable_source,
        "legacy WorkspaceShell is reachable from a shipping surface",
    )


def verify_shipping_sources(contract: dict) -> None:
    paths = {REGISTRY_PATH, SHELL_PATH, MAIN_PATH}
    for surface in contract["shipping_surfaces"]:
        source_path = ROOT / surface["source"]
        test_path = ROOT / surface["test"]
        require(source_path.is_file(), f"shipping source is missing: {surface['source']}")
        require(test_path.is_file(), f"shipping proof is missing: {surface['test']}")
        source = source_path.read_text(encoding="utf-8", errors="replace")
        require(
            surface["symbol"] in source,
            f"shipping symbol {surface['symbol']} is missing from {surface['source']}",
        )
        paths.add(source_path)

    violations: list[str] = []
    for path in sorted(paths):
        source = path.read_text(encoding="utf-8", errors="replace")
        for marker in FORBIDDEN_UI_MARKERS:
            match = marker.search(source)
            if match:
                line = source.count("\n", 0, match.start()) + 1
                violations.append(
                    f"{generator.relative(path)}:{line}: {match.group(0)!r}"
                )
    require(
        not violations,
        "shipping UI contains an unwired marker:\n  " + "\n  ".join(violations),
    )


def reachable_ids(graph: dict, start: str) -> set[str]:
    outgoing: dict[str, list[str]] = {}
    for edge in graph["edges"]:
        outgoing.setdefault(edge["from"], []).append(edge["to"])
    visited = {start}
    queue = deque([start])
    while queue:
        current = queue.popleft()
        for target in outgoing.get(current, []):
            if target not in visited:
                visited.add(target)
                queue.append(target)
    return visited


def verify_surface_wiring(contract: dict, graph: dict) -> None:
    graph_nodes = {node["id"]: node for node in graph["nodes"]}
    incoming = {(edge["to"], edge["from"]) for edge in graph["edges"]}
    validation_nodes = {
        node["id"] for node in graph["nodes"] if node["layer"] == "validation"
    }
    authority_layers = {"state", "service", "persistence", "backend"}

    for surface in contract["shipping_surfaces"]:
        node_id = surface["id"]
        node = graph_nodes.get(node_id)
        require(node is not None, f"shipping surface has no graph node: {node_id}")
        require(node["status"] == "wired", f"shipping surface is not wired: {node_id}")
        downstream = reachable_ids(graph, node_id)
        require(
            any(graph_nodes[item]["layer"] in authority_layers for item in downstream),
            f"shipping surface has no state/service/persistence/backend path: {node_id}",
        )
        require(
            any((node_id, validation) in incoming for validation in validation_nodes),
            f"shipping surface has no graph-linked validation: {node_id}",
        )


def main() -> int:
    try:
        graph, contract = generator.build_graph()
        verify_generated_outputs(graph, contract)
        verify_evidence(contract, graph)
        verify_shipping_registry(contract)
        verify_shipping_sources(contract)
        verify_surface_wiring(contract, graph)
    except (VerificationError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"SYSTEM GRAPH GATE FAILED: {error}", file=sys.stderr)
        return 1

    print(
        "SYSTEM GRAPH GATE PASSED: "
        f"{graph['summary']['nodes']} nodes, {graph['summary']['edges']} edges, "
        f"{graph['summary']['contract_nodes']} contract nodes"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
