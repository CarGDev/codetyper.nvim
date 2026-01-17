"""
Graph-based memory storage.

This module implements a knowledge graph for storing and
querying project-specific knowledge.

The graph consists of:
- Nodes: Represent entities (files, functions, concepts, etc.)
- Edges: Represent relationships between entities

Supports:
- Adding/removing nodes and edges
- Querying by node type or relationship
- Pattern matching across the graph

Migrated from:
- lua/codetyper/core/memory/graph/init.lua
- lua/codetyper/core/memory/graph/node.lua
- lua/codetyper/core/memory/graph/edge.lua
- lua/codetyper/core/memory/graph/query.lua
"""

from typing import Dict, List, Optional, Any, Set
from dataclasses import dataclass, field
from enum import Enum
import uuid


class NodeType(Enum):
    """Types of nodes in the memory graph."""
    FILE = "file"
    FUNCTION = "function"
    CLASS = "class"
    CONCEPT = "concept"
    PATTERN = "pattern"
    CONVENTION = "convention"
    CORRECTION = "correction"


class EdgeType(Enum):
    """Types of edges in the memory graph."""
    CONTAINS = "contains"       # File contains function/class
    IMPORTS = "imports"         # File imports another
    CALLS = "calls"             # Function calls another
    INHERITS = "inherits"       # Class inherits from another
    RELATES_TO = "relates_to"   # Generic relationship
    LEARNED_FROM = "learned_from"  # Knowledge source


@dataclass
class Node:
    """A node in the memory graph."""
    id: str
    type: NodeType
    content: str
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class Edge:
    """An edge in the memory graph."""
    source: str  # Node ID
    target: str  # Node ID
    type: EdgeType
    metadata: Dict[str, Any] = field(default_factory=dict)


class MemoryGraph:
    """
    Graph-based knowledge storage.

    Stores entities and relationships for project-specific
    knowledge that the agent can use for better understanding.
    """

    def __init__(self):
        """Initialize an empty graph."""
        self._nodes: Dict[str, Node] = {}
        self._edges: List[Edge] = []
        self._adjacency: Dict[str, Set[str]] = {}  # node_id -> connected node_ids

    def add_node(
        self,
        node_type: NodeType,
        content: str,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> str:
        """
        Add a node to the graph.

        Args:
            node_type: Type of the node
            content: Node content/label
            metadata: Optional metadata

        Returns:
            The node ID
        """
        # TODO: Implement node addition
        node_id = str(uuid.uuid4())[:8]
        self._nodes[node_id] = Node(
            id=node_id,
            type=node_type,
            content=content,
            metadata=metadata or {},
        )
        self._adjacency[node_id] = set()
        return node_id

    def add_edge(
        self,
        source: str,
        target: str,
        edge_type: EdgeType,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> None:
        """
        Add an edge between two nodes.

        Args:
            source: Source node ID
            target: Target node ID
            edge_type: Type of relationship
            metadata: Optional metadata
        """
        # TODO: Implement edge addition
        if source not in self._nodes or target not in self._nodes:
            raise ValueError("Source or target node not found")

        self._edges.append(Edge(
            source=source,
            target=target,
            type=edge_type,
            metadata=metadata or {},
        ))
        self._adjacency[source].add(target)

    def get_node(self, node_id: str) -> Optional[Node]:
        """Get a node by ID."""
        return self._nodes.get(node_id)

    def query(
        self,
        node_type: Optional[NodeType] = None,
        content_pattern: Optional[str] = None,
    ) -> List[Node]:
        """
        Query nodes by type and/or content pattern.

        Args:
            node_type: Filter by node type
            content_pattern: Filter by content (substring match)

        Returns:
            List of matching nodes
        """
        # TODO: Implement query logic
        results = []
        for node in self._nodes.values():
            if node_type and node.type != node_type:
                continue
            if content_pattern and content_pattern not in node.content:
                continue
            results.append(node)
        return results

    def get_connected(
        self,
        node_id: str,
        edge_type: Optional[EdgeType] = None,
    ) -> List[Node]:
        """
        Get nodes connected to a given node.

        Args:
            node_id: The source node ID
            edge_type: Filter by edge type

        Returns:
            List of connected nodes
        """
        # TODO: Implement connected node retrieval
        if node_id not in self._adjacency:
            return []

        connected_ids = self._adjacency[node_id]
        if edge_type:
            # Filter by edge type
            connected_ids = {
                e.target for e in self._edges
                if e.source == node_id and e.type == edge_type
            }

        return [self._nodes[nid] for nid in connected_ids if nid in self._nodes]

    def remove_node(self, node_id: str) -> None:
        """Remove a node and its edges."""
        # TODO: Implement node removal
        if node_id in self._nodes:
            del self._nodes[node_id]
            del self._adjacency[node_id]
            # Remove edges
            self._edges = [e for e in self._edges if e.source != node_id and e.target != node_id]
            # Update adjacency
            for adj in self._adjacency.values():
                adj.discard(node_id)

    def clear(self) -> None:
        """Clear all nodes and edges."""
        self._nodes.clear()
        self._edges.clear()
        self._adjacency.clear()

    def to_dict(self) -> Dict[str, Any]:
        """Serialize graph to dict for storage."""
        # TODO: Implement serialization
        return {
            "nodes": [
                {
                    "id": n.id,
                    "type": n.type.value,
                    "content": n.content,
                    "metadata": n.metadata,
                }
                for n in self._nodes.values()
            ],
            "edges": [
                {
                    "source": e.source,
                    "target": e.target,
                    "type": e.type.value,
                    "metadata": e.metadata,
                }
                for e in self._edges
            ],
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "MemoryGraph":
        """Deserialize graph from dict."""
        # TODO: Implement deserialization
        graph = cls()
        for node_data in data.get("nodes", []):
            node = Node(
                id=node_data["id"],
                type=NodeType(node_data["type"]),
                content=node_data["content"],
                metadata=node_data.get("metadata", {}),
            )
            graph._nodes[node.id] = node
            graph._adjacency[node.id] = set()

        for edge_data in data.get("edges", []):
            edge = Edge(
                source=edge_data["source"],
                target=edge_data["target"],
                type=EdgeType(edge_data["type"]),
                metadata=edge_data.get("metadata", {}),
            )
            graph._edges.append(edge)
            if edge.source in graph._adjacency:
                graph._adjacency[edge.source].add(edge.target)

        return graph
