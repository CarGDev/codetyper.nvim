"""
Memory subsystem for the agent.

This package provides persistent memory and learning capabilities:
- Graph-based knowledge storage
- Learning from user corrections
- Pattern recognition
- Convention learning

The memory system allows the agent to improve over time
by learning from interactions and remembering project-specific
knowledge.

Migrated from:
- lua/codetyper/core/memory/ (entire directory)
"""

from .graph import MemoryGraph
from .storage import MemoryStorage
from .learners import PatternLearner, ConventionLearner, CorrectionLearner

__all__ = [
    "MemoryGraph",
    "MemoryStorage",
    "PatternLearner",
    "ConventionLearner",
    "CorrectionLearner",
]
