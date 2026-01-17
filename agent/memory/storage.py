"""
Persistent storage for the memory graph.

This module handles saving and loading the memory graph
to/from disk. Each project has its own memory file.

Storage format:
- JSON file per project
- Located in .codetyper/ directory
- Hash-based change detection for efficient updates

Migrated from:
- lua/codetyper/core/memory/storage.lua
- lua/codetyper/core/memory/hash.lua
"""

import json
import hashlib
from pathlib import Path
from typing import Optional, Dict, Any

from .graph import MemoryGraph


class MemoryStorage:
    """
    Persistent storage for memory graphs.

    Saves and loads memory graphs to/from JSON files
    in the project's .codetyper directory.
    """

    STORAGE_DIR = ".codetyper"
    MEMORY_FILE = "memory.json"

    def __init__(self, project_root: str):
        """
        Initialize storage for a project.

        Args:
            project_root: Root directory of the project
        """
        self.project_root = Path(project_root)
        self.storage_path = self.project_root / self.STORAGE_DIR / self.MEMORY_FILE
        self._last_hash: Optional[str] = None

    def load(self) -> MemoryGraph:
        """
        Load memory graph from disk.

        Returns:
            Loaded MemoryGraph, or empty graph if file doesn't exist
        """
        if not self.storage_path.exists():
            return MemoryGraph()

        try:
            with open(self.storage_path, "r") as f:
                data = json.load(f)
            self._last_hash = self._compute_hash(data)
            return MemoryGraph.from_dict(data)
        except (json.JSONDecodeError, KeyError) as e:
            # Corrupted file, return empty graph
            return MemoryGraph()

    def save(self, graph: MemoryGraph) -> bool:
        """
        Save memory graph to disk.

        Only writes if the graph has changed (hash comparison).

        Args:
            graph: The MemoryGraph to save

        Returns:
            True if saved, False if unchanged
        """
        data = graph.to_dict()
        current_hash = self._compute_hash(data)

        # Skip save if unchanged
        if current_hash == self._last_hash:
            return False

        # Ensure directory exists
        self.storage_path.parent.mkdir(parents=True, exist_ok=True)

        # Write atomically (write to temp, then rename)
        temp_path = self.storage_path.with_suffix(".tmp")
        with open(temp_path, "w") as f:
            json.dump(data, f, indent=2)
        temp_path.rename(self.storage_path)

        self._last_hash = current_hash
        return True

    def _compute_hash(self, data: Dict[str, Any]) -> str:
        """Compute hash of data for change detection."""
        serialized = json.dumps(data, sort_keys=True)
        return hashlib.sha256(serialized.encode()).hexdigest()[:16]

    def exists(self) -> bool:
        """Check if memory file exists."""
        return self.storage_path.exists()

    def delete(self) -> bool:
        """Delete the memory file."""
        if self.storage_path.exists():
            self.storage_path.unlink()
            self._last_hash = None
            return True
        return False

    def get_storage_info(self) -> Dict[str, Any]:
        """Get information about the storage."""
        info = {
            "path": str(self.storage_path),
            "exists": self.exists(),
        }
        if self.exists():
            info["size_bytes"] = self.storage_path.stat().st_size
            info["last_modified"] = self.storage_path.stat().st_mtime
        return info
