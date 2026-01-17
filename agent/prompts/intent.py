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

Possible intents:
- ask: User wants information/explanation without code changes
- code: User wants new code written
- refactor: User wants existing code restructured
- fix: User wants a bug or issue fixed
- document: User wants documentation/comments added
- explain: User wants code explained
- test: User wants tests written

Respond with:
1. intent: The primary intent (one of the above)
2. confidence: How confident you are (0.0 to 1.0)
3. reasoning: Brief explanation of your classification

If the request is ambiguous, set confidence below 0.7 and
include clarification questions.

JSON format:
{{
  "intent": "code",
  "confidence": 0.85,
  "reasoning": "User explicitly asks to 'add a function'",
  "clarification_needed": false,
  "questions": []
}}
"""

# Clarification prompt template
CLARIFICATION_PROMPT = """
The user's request is ambiguous. Before proceeding, I need to understand:

{questions}

Please clarify so I can better assist you.
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


def get_ambiguity_questions(context: str, prompt: str) -> List[str]:
    """
    Generate clarification questions for ambiguous requests.

    Args:
        context: The surrounding context
        prompt: The user's prompt

    Returns:
        List of clarification questions
    """
    # TODO: Implement smart question generation
    # For now, return generic questions
    questions = []

    # Check for common ambiguities
    if "this" in prompt.lower() or "it" in prompt.lower():
        questions.append("What specific code or file are you referring to?")

    if "improve" in prompt.lower() or "better" in prompt.lower():
        questions.append("What specific aspect would you like improved (performance, readability, etc.)?")

    if "change" in prompt.lower() and "to" not in prompt.lower():
        questions.append("What would you like to change it to?")

    if not questions:
        questions.append("Could you provide more details about what you'd like me to do?")

    return questions
