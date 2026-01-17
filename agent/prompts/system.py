"""
System prompt templates.

This module contains the base system prompts that set up
the agent's behavior and capabilities.

Migrated from:
- lua/codetyper/prompts/init.lua
- lua/codetyper/prompts/agents/init.lua
"""

from typing import Dict, Any, Optional


# Base system prompt for the agent
BASE_SYSTEM_PROMPT = """You are a code assistant integrated into the user's editor.
Your role is to help with code modifications, explanations, and refactoring.

Guidelines:
- Be precise and concise in your responses
- When modifying code, use the SEARCH/REPLACE format
- If you're unsure what the user wants, ask for clarification
- Respect the existing code style and conventions
- Never make changes beyond what was requested

Available tools:
{tools}

Current context:
{context}
"""

# Context injection template
CONTEXT_TEMPLATE = """
File: {filepath}
Language: {language}
Cursor position: line {line}, column {col}

{selection_info}

Content:
```{language}
{content}
```
"""


def get_system_prompt(
    context: Dict[str, Any],
    tools: Optional[str] = None,
) -> str:
    """
    Get the system prompt with context injected.

    Args:
        context: Context dict with file info, cursor pos, etc.
        tools: Optional tool descriptions

    Returns:
        Formatted system prompt
    """
    context_str = get_context_injection(context)
    return BASE_SYSTEM_PROMPT.format(
        tools=tools or "No tools available",
        context=context_str,
    )


def get_context_injection(context: Dict[str, Any]) -> str:
    """
    Format context for injection into prompts.

    Args:
        context: Context dict from Lua

    Returns:
        Formatted context string
    """
    selection_info = ""
    if context.get("selection"):
        selection_info = f"Selection: {context['selection']}"

    return CONTEXT_TEMPLATE.format(
        filepath=context.get("filepath", "unknown"),
        language=context.get("language", "text"),
        line=context.get("line", 1),
        col=context.get("col", 1),
        selection_info=selection_info,
        content=context.get("content", ""),
    )
