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

## Response Style
- Be concise and direct. Answer the user's question without unnecessary preamble.
- Avoid phrases like "Certainly!", "Great question!", "Here's what I'll do...". Just do it.
- Do NOT add comments to code unless explicitly requested or the logic is genuinely complex.
- Keep explanations brief unless the user asks for detail.
- After completing a code change, give a brief 1-2 sentence summary. Don't over-explain.

## Code Conventions (CRITICAL)
Before making any changes:
1. NEVER assume you know the file contents - read the file first
2. NEVER assume a library is available - check dependency files first
3. Mimic existing code style: indentation, naming conventions, patterns
4. Use existing utilities and helpers from the codebase
5. Match the surrounding code's error handling approach
6. Look at neighboring files to understand project conventions

## Security
- Never introduce code that exposes secrets, API keys, or credentials
- Never hardcode sensitive values - use environment variables
- Never commit secrets to version control

## Making Code Changes
When modifying code, use the SEARCH/REPLACE format:
- The SEARCH block must EXACTLY match existing code (character-for-character)
- Include enough context to uniquely identify the location
- Preserve exact indentation and whitespace
- If a match fails, re-read the file - it may have changed

## Verification
After making changes, suggest running lint/test commands if available.
If you introduce errors, fix them before considering the task complete.

Available tools:
{tools}

Current context:
{context}
"""

# Minimal system prompt for simple operations
MINIMAL_SYSTEM_PROMPT = """You are a code assistant. Help the user with their request.

Be concise. When modifying code, use SEARCH/REPLACE format with exact string matching.
Match existing code style. Don't add unnecessary comments.

Context:
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
    minimal: bool = False,
) -> str:
    """
    Get the system prompt with context injected.

    Args:
        context: Context dict with file info, cursor pos, etc.
        tools: Optional tool descriptions
        minimal: If True, use a shorter prompt for simple operations

    Returns:
        Formatted system prompt
    """
    context_str = get_context_injection(context)

    if minimal:
        return MINIMAL_SYSTEM_PROMPT.format(context=context_str)

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
