"""
Codetyper Agent - The reasoning engine for code transformations.

This package contains all reasoning logic extracted from Lua:
- Intent classification
- Plan construction
- Validation
- Output formatting
- Memory/learning systems

The agent communicates with Neovim/Lua via JSON-RPC over stdin/stdout.
Lua's role is reduced to: gather context, forward to agent, execute plan.

Principle: Only reasoning moves here; reaction stays in Lua.
"""

__version__ = "0.1.0"
