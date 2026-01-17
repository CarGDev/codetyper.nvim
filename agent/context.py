"""
Context management module.

This module handles the context passed from Lua to the agent.
It provides utilities for parsing, enriching, and managing
the context needed for intent classification and planning.

Responsibilities:
- Parse raw context from Lua
- Extract relevant information (file type, cursor position, etc.)
- Enrich context with additional information if needed
- Provide context to other modules in a structured format

Context includes:
- Buffer content (current file)
- Cursor position
- Selection (if any)
- File path and type
- Visible range
- Referenced files (from @file syntax)
"""

from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field


@dataclass
class BufferContext:
    """Context about the current buffer."""
    filepath: str
    filetype: str
    content: str
    cursor_line: int
    cursor_col: int
    selection_start: Optional[tuple[int, int]] = None  # (line, col)
    selection_end: Optional[tuple[int, int]] = None
    visible_start: int = 0
    visible_end: int = 0


@dataclass
class Context:
    """Full context for agent operations."""
    buffer: BufferContext
    prompt: str
    referenced_files: Dict[str, str] = field(default_factory=dict)
    project_root: Optional[str] = None
    extra: Dict[str, Any] = field(default_factory=dict)


class ContextBuilder:
    """
    Builds and manages context for agent operations.

    Lua sends raw context data; this class parses it into
    a structured format for use by other modules.
    """

    def __init__(self):
        """Initialize the context builder."""
        pass

    def from_raw(self, raw: Dict[str, Any]) -> Context:
        """
        Build context from raw Lua data.

        Args:
            raw: Raw context dict from Lua

        Returns:
            Structured Context object
        """
        # TODO: Implement context parsing
        # 1. Extract buffer info
        # 2. Parse cursor position
        # 3. Parse selection if present
        # 4. Extract referenced files
        # 5. Build Context object
        pass

    def enrich(self, ctx: Context) -> Context:
        """
        Enrich context with additional information.

        May read additional files, analyze imports, etc.
        """
        # TODO: Implement context enrichment
        pass

    def extract_prompt(self, ctx: Context) -> str:
        """Extract the user's prompt from context."""
        # TODO: Implement prompt extraction
        pass
