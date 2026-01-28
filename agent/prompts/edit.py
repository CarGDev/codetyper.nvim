"""
Code editing prompt templates.

This module contains prompts for code modification operations.

Migrated from:
- lua/codetyper/prompts/code.lua
- lua/codetyper/prompts/refactor.lua
- lua/codetyper/prompts/agents/tools.lua
"""

from typing import Dict, List, Any

from ..schemas import IntentType


# SEARCH/REPLACE format instructions
SEARCH_REPLACE_INSTRUCTIONS = """
When modifying code, use the SEARCH/REPLACE format:

<<<<<<< SEARCH
[exact code to find]
=======
[replacement code]
>>>>>>> REPLACE

## Critical Rules

1. **EXACT MATCH REQUIRED**: The SEARCH block must match the file content character-for-character:
   - Match ALL whitespace (spaces, tabs, newlines)
   - Match ALL punctuation and formatting
   - Include complete lines - never truncate mid-line

2. **UNIQUE IDENTIFICATION**: Include enough context to uniquely identify the location:
   - If a line appears multiple times, include 2-3 surrounding lines
   - Include function signatures, class names, or unique nearby code
   - Better to include too much context than too little

3. **ONE CHANGE PER BLOCK**: Each SEARCH/REPLACE block handles one logical change:
   - Multiple changes = multiple blocks
   - List blocks in the order they appear in the file
   - Don't include long unchanged sections in blocks

4. **PRESERVE FORMATTING**: Match the file's existing style:
   - Keep the same indentation (spaces vs tabs)
   - Keep the same quote style (' vs ")
   - Keep the same line ending patterns

## Examples

**Adding a parameter:**
<<<<<<< SEARCH
def hello():
    print("Hello")
=======
def hello(name: str) -> None:
    print(f"Hello, {name}")
>>>>>>> REPLACE

**Adding an import (include context to be unique):**
<<<<<<< SEARCH
import React from 'react';
import { useState } from 'react';
=======
import React from 'react';
import { useState, useEffect } from 'react';
>>>>>>> REPLACE

**Deleting code (empty replacement):**
<<<<<<< SEARCH
    // TODO: remove this debug line
    console.log('debug:', data);
=======
>>>>>>> REPLACE

**Moving code requires TWO blocks:**
Block 1 - Delete from original location:
<<<<<<< SEARCH
function helper() {
  return true;
}

function main() {
=======
function main() {
>>>>>>> REPLACE

Block 2 - Insert at new location:
<<<<<<< SEARCH
// Utils section
=======
// Utils section

function helper() {
  return true;
}
>>>>>>> REPLACE

## Common Mistakes to Avoid

- DON'T guess file contents - read the file first
- DON'T include partial lines in SEARCH blocks
- DON'T change indentation unless that's the goal
- DON'T put long unchanged code inside SEARCH blocks
- If edit fails, RE-READ the file - content may have changed
"""

# Edit prompt template
EDIT_PROMPT_TEMPLATE = """
{intent_description}

Files to consider:
{files}

User request:
{request}

{search_replace_instructions}

Provide your changes using the SEARCH/REPLACE format above.
"""

# Intent-specific descriptions
INTENT_DESCRIPTIONS = {
    IntentType.CODE: "Generate or add new code as requested.",
    IntentType.REFACTOR: "Refactor the code to improve structure while preserving behavior.",
    IntentType.FIX: "Fix the bug or issue described.",
    IntentType.DOCUMENT: "Add or improve documentation/comments.",
    IntentType.TEST: "Write tests for the specified code.",
}


def get_edit_prompt(
    intent: IntentType,
    files: Dict[str, str],
    request: str,
) -> str:
    """
    Get the prompt for a code edit operation.

    Args:
        intent: The classified intent
        files: Dict of filepath -> content
        request: The user's request

    Returns:
        Formatted edit prompt
    """
    intent_desc = INTENT_DESCRIPTIONS.get(
        intent,
        "Perform the requested code modification.",
    )

    files_str = ""
    for path, content in files.items():
        files_str += f"\n--- {path} ---\n```\n{content}\n```\n"

    return EDIT_PROMPT_TEMPLATE.format(
        intent_description=intent_desc,
        files=files_str,
        request=request,
        search_replace_instructions=SEARCH_REPLACE_INSTRUCTIONS,
    )


def get_search_replace_instructions() -> str:
    """Get the SEARCH/REPLACE format instructions."""
    return SEARCH_REPLACE_INSTRUCTIONS


def get_multi_file_prompt(
    files: Dict[str, str],
    request: str,
) -> str:
    """
    Get prompt for multi-file operations.

    Args:
        files: Dict of filepath -> content
        request: The user's request

    Returns:
        Formatted multi-file prompt
    """
    files_str = ""
    for path, content in files.items():
        files_str += f"\n--- {path} ---\n```\n{content}\n```\n"

    return f"""
You need to modify multiple files to complete this request.

Files:
{files_str}

Request: {request}

For each file that needs changes, provide SEARCH/REPLACE blocks.
Prefix each file's changes with:

=== FILE: path/to/file ===

{SEARCH_REPLACE_INSTRUCTIONS}
"""
