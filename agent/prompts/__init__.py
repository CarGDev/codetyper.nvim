"""
Prompt templates for the agent.

This package contains all LLM prompt templates used by the agent.
Prompts are centralized here to ensure consistency and make
them easy to update.

Modules:
- system: Base system prompts and context injection
- edit: Code modification prompts
- intent: Intent classification prompts

Usage:
    from agent.prompts import get_system_prompt, get_edit_prompt

    system = get_system_prompt(context)
    edit = get_edit_prompt(intent, files)

Migrated from:
- lua/codetyper/prompts/ (entire directory)
"""

from .system import get_system_prompt, get_context_injection
from .edit import get_edit_prompt, get_search_replace_instructions
from .intent import get_intent_prompt, get_clarification_prompt

__all__ = [
    "get_system_prompt",
    "get_context_injection",
    "get_edit_prompt",
    "get_search_replace_instructions",
    "get_intent_prompt",
    "get_clarification_prompt",
]
