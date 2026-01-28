"""
Intent classification prompt templates.

This module contains prompts for classifying user intent.

Migrated from:
- lua/codetyper/prompts/ask.lua
- lua/codetyper/prompts/agents/intent.lua
"""

from typing import List


# Intent classification prompt
INTENT_CLASSIFICATION_PROMPT = """
Analyze the user's request and classify their intent.

Context:
{context}

User request:
{prompt}

## Intent Categories

| Intent | Description | Example phrases |
|--------|-------------|-----------------|
| ask | Information/explanation, no code changes | "what does", "how does", "explain", "why" |
| code | New code to be written/added | "add", "create", "implement", "write" |
| refactor | Restructure existing code, preserve behavior | "refactor", "clean up", "reorganize", "simplify" |
| fix | Bug fix or error resolution | "fix", "debug", "not working", "error", "broken" |
| document | Add/update documentation or comments | "document", "add comments", "jsdoc", "docstring" |
| explain | Detailed code explanation/walkthrough | "walk me through", "explain step by step" |
| test | Write or update tests | "test", "spec", "coverage", "unit test" |

## Classification Rules

1. Look for explicit action words first (add, fix, refactor, etc.)
2. Consider the context - if cursor is on broken code, "fix" is likely
3. Questions about code behavior = "ask" or "explain"
4. Requests to modify code = "code", "refactor", or "fix"

## Confidence Guidelines

- 0.9+: Explicit intent keyword present ("add a function", "fix this bug")
- 0.7-0.9: Intent is clear from context but not explicit
- 0.5-0.7: Ambiguous, could be multiple intents
- <0.5: Very unclear, clarification needed

## Response Format (JSON)

{{
  "intent": "code",
  "confidence": 0.85,
  "reasoning": "User explicitly asks to 'add a function'",
  "clarification_needed": false,
  "questions": []
}}

## Examples

Request: "add a login form"
→ {{"intent": "code", "confidence": 0.95, "reasoning": "'add' indicates new code"}}

Request: "this is broken"
→ {{"intent": "fix", "confidence": 0.8, "reasoning": "'broken' suggests bug fix"}}

Request: "make this cleaner"
→ {{"intent": "refactor", "confidence": 0.85, "reasoning": "'cleaner' suggests restructuring"}}

Request: "what does this do"
→ {{"intent": "explain", "confidence": 0.9, "reasoning": "Question about behavior"}}

Request: "improve this"
→ {{"intent": "refactor", "confidence": 0.6, "reasoning": "Ambiguous - could be refactor or fix", "clarification_needed": true, "questions": ["What aspect would you like improved? (performance, readability, correctness)"]}}
"""

# Clarification prompt template
CLARIFICATION_PROMPT = """
I need a bit more information to help you effectively:

{questions}
"""


def get_intent_prompt(context: str, prompt: str) -> str:
    """
    Get the prompt for intent classification.

    Args:
        context: The surrounding context
        prompt: The user's prompt

    Returns:
        Formatted classification prompt
    """
    return INTENT_CLASSIFICATION_PROMPT.format(
        context=context,
        prompt=prompt,
    )


def get_clarification_prompt(questions: List[str]) -> str:
    """
    Get a clarification prompt with questions.

    Args:
        questions: List of clarification questions

    Returns:
        Formatted clarification prompt
    """
    questions_str = "\n".join(f"- {q}" for q in questions)
    return CLARIFICATION_PROMPT.format(questions=questions_str)


# Ambiguity patterns and their clarifying questions
AMBIGUITY_PATTERNS = {
    # Vague references
    "this": "What specific code are you referring to?",
    "it": "What specifically would you like me to work on?",
    "here": "Which part of the code should I focus on?",

    # Vague actions
    "improve": "What aspect would you like improved? (performance, readability, maintainability)",
    "better": "In what way should it be better? (faster, cleaner, more robust)",
    "fix": "What specific issue or behavior needs fixing?",
    "update": "What should be updated and to what?",
    "change": "What should the new behavior or value be?",
    "make it": "What specific change would you like?",

    # Scope ambiguity
    "some": "Which specific items should be affected?",
    "few": "How many, and which ones specifically?",
    "similar": "Could you point to an example of what you mean?",

    # Missing targets
    "add": "Where should it be added?",
    "remove": "What specifically should be removed?",
    "move": "Where should it be moved to?",
}


def get_ambiguity_questions(context: str, prompt: str) -> List[str]:
    """
    Generate clarification questions for ambiguous requests.

    Uses pattern matching to identify common ambiguities and
    generate relevant clarifying questions.

    Args:
        context: The surrounding context
        prompt: The user's prompt

    Returns:
        List of clarification questions (max 3)
    """
    questions = []
    prompt_lower = prompt.lower()

    # Check for ambiguity patterns
    for pattern, question in AMBIGUITY_PATTERNS.items():
        if pattern in prompt_lower:
            # Avoid duplicate questions
            if question not in questions:
                questions.append(question)

    # Check for very short requests (likely missing context)
    words = prompt.split()
    if len(words) < 4 and not questions:
        questions.append("Could you provide more detail about what you'd like me to do?")

    # Check for requests without clear action
    action_words = {"add", "create", "fix", "update", "remove", "refactor", "explain", "test"}
    if not any(word.lower() in action_words for word in words):
        if not questions:
            questions.append("What action would you like me to take? (add, fix, refactor, explain, etc.)")

    # Limit to 3 questions max
    return questions[:3] if questions else [
        "Could you provide more details about what you'd like me to do?"
    ]
