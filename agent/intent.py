"""
Intent classification module.

This module is responsible for understanding what the user wants to do.
It replaces all intent classification logic previously in Lua.

Responsibilities:
- Classify user prompts into intent types (ask, code, refactor, etc.)
- Score confidence in the classification
- Detect ambiguity and generate clarification questions
- Never guess when uncertain - ask for clarification

Migrated from:
- lua/codetyper/core/intent/init.lua
- lua/codetyper/features/ask/intent.lua
- lua/codetyper/params/agents/intent.lua
"""

import re
from typing import List, Dict, Tuple, Optional
from .schemas import IntentRequest, IntentResponse, IntentType


# Keyword patterns for each intent type
INTENT_PATTERNS: Dict[IntentType, List[str]] = {
    IntentType.ASK: [
        r"\b(what|why|how|when|where|who|which|explain|describe|tell me|help me understand)\b",
        r"\bis\s+(it|this|that)\b",
        r"\?$",
        r"\b(mean|meaning|purpose|difference|between)\b",
    ],
    IntentType.CODE: [
        r"\b(write|create|generate|implement|add|make|build)\b",
        r"\b(function|class|method|module|component|api|endpoint)\b",
        r"\b(new|from scratch)\b",
    ],
    IntentType.REFACTOR: [
        r"\b(refactor|restructure|reorganize|clean up|improve|simplify)\b",
        r"\b(extract|split|merge|combine|move)\b",
        r"\b(better|cleaner|more readable|more maintainable)\b",
    ],
    IntentType.FIX: [
        r"\b(fix|bug|error|issue|problem|broken|wrong|incorrect)\b",
        r"\b(doesn't work|not working|fails|failing|crash)\b",
        r"\b(debug|troubleshoot|solve)\b",
    ],
    IntentType.DOCUMENT: [
        r"\b(document|documentation|docstring|comment|jsdoc|typedoc)\b",
        r"\b(add comments|write docs|explain the code)\b",
        r"\b(readme|changelog)\b",
    ],
    IntentType.EXPLAIN: [
        r"\b(explain|walk me through|how does|what does)\b",
        r"\b(this code|this function|this class)\b",
        r"\b(step by step|in detail)\b",
    ],
    IntentType.TEST: [
        r"\b(test|tests|testing|spec|specs)\b",
        r"\b(unit test|integration test|e2e|end.to.end)\b",
        r"\b(coverage|assert|expect|mock)\b",
    ],
}

# Keywords that strongly indicate specific intents
STRONG_INDICATORS: Dict[str, IntentType] = {
    "write a function": IntentType.CODE,
    "create a class": IntentType.CODE,
    "implement": IntentType.CODE,
    "refactor": IntentType.REFACTOR,
    "fix the bug": IntentType.FIX,
    "fix this": IntentType.FIX,
    "add tests": IntentType.TEST,
    "write tests": IntentType.TEST,
    "add documentation": IntentType.DOCUMENT,
    "add comments": IntentType.DOCUMENT,
    "explain this": IntentType.EXPLAIN,
    "what does this": IntentType.EXPLAIN,
    "how does this": IntentType.EXPLAIN,
}

# Ambiguous phrases that need clarification
AMBIGUOUS_PATTERNS = [
    r"\bthis\b(?!\s+(code|function|class|file|method))",  # "this" without specifier
    r"\bit\b",  # generic "it"
    r"\b(improve|better|update)\b",  # vague action verbs
    r"\b(change|modify)\b(?!\s+to)",  # change without target
]


class IntentClassifier:
    """
    Classifies user prompts into actionable intents.

    The classifier prioritizes precision over recall - it's better
    to ask for clarification than to misunderstand the user.
    """

    # Minimum confidence to return a classification without clarification
    CONFIDENCE_THRESHOLD = 0.7

    # Weights for different signal sources
    WEIGHTS = {
        "strong_indicator": 0.5,
        "pattern_match": 0.3,
        "context_signal": 0.2,
    }

    def __init__(self):
        """Initialize the classifier."""
        pass

    def classify(self, request: IntentRequest) -> IntentResponse:
        """
        Classify a user prompt into an intent.

        Args:
            request: The classification request with context and prompt

        Returns:
            IntentResponse with classified intent and confidence
        """
        prompt = request.prompt.lower().strip()
        context = request.context.lower() if request.context else ""

        # Check for strong indicators first
        intent, confidence = self._check_strong_indicators(prompt)
        if intent and confidence >= self.CONFIDENCE_THRESHOLD:
            return IntentResponse(
                intent=intent,
                confidence=confidence,
                reasoning=f"Strong indicator phrase detected",
                needs_clarification=False,
            )

        # Score all intent types
        scores = self._score_intents(prompt, context)

        # Find best match
        best_intent = max(scores, key=scores.get)
        best_score = scores[best_intent]

        # Check for ambiguity
        is_ambiguous, ambiguity_reasons = self._check_ambiguity(prompt, scores)

        # Generate reasoning
        reasoning = self._generate_reasoning(best_intent, scores, prompt)

        # Check if we need clarification
        needs_clarification = best_score < self.CONFIDENCE_THRESHOLD or is_ambiguous
        questions = []

        if needs_clarification:
            questions = self._generate_clarification(prompt, scores, ambiguity_reasons)

        return IntentResponse(
            intent=best_intent,
            confidence=best_score,
            reasoning=reasoning,
            needs_clarification=needs_clarification,
            clarification_questions=questions,
        )

    def _check_strong_indicators(self, prompt: str) -> Tuple[Optional[IntentType], float]:
        """Check for strong indicator phrases."""
        for phrase, intent in STRONG_INDICATORS.items():
            if phrase in prompt:
                return intent, 0.9
        return None, 0.0

    def _score_intents(self, prompt: str, context: str) -> Dict[IntentType, float]:
        """Score each intent type based on patterns and context."""
        scores = {intent: 0.0 for intent in IntentType if intent != IntentType.UNKNOWN}

        for intent, patterns in INTENT_PATTERNS.items():
            pattern_score = 0.0
            matches = 0

            for pattern in patterns:
                if re.search(pattern, prompt, re.IGNORECASE):
                    matches += 1
                    pattern_score += 1.0 / len(patterns)

            # Boost if multiple patterns match
            if matches > 1:
                pattern_score = min(pattern_score * 1.2, 1.0)

            scores[intent] = pattern_score

        # Normalize scores
        total = sum(scores.values())
        if total > 0:
            for intent in scores:
                scores[intent] = scores[intent] / total

        # Apply minimum floor to prevent 0 scores
        for intent in scores:
            scores[intent] = max(scores[intent], 0.05)

        # Re-normalize after floor
        total = sum(scores.values())
        for intent in scores:
            scores[intent] = scores[intent] / total

        return scores

    def _check_ambiguity(
        self,
        prompt: str,
        scores: Dict[IntentType, float],
    ) -> Tuple[bool, List[str]]:
        """Check if the prompt is ambiguous."""
        reasons = []

        # Check for ambiguous patterns
        for pattern in AMBIGUOUS_PATTERNS:
            if re.search(pattern, prompt, re.IGNORECASE):
                reasons.append(f"Vague reference detected")
                break

        # Check if top scores are too close
        sorted_scores = sorted(scores.values(), reverse=True)
        if len(sorted_scores) >= 2:
            top_diff = sorted_scores[0] - sorted_scores[1]
            if top_diff < 0.15:
                reasons.append("Multiple intents seem equally likely")

        # Check if prompt is too short
        word_count = len(prompt.split())
        if word_count < 3:
            reasons.append("Prompt is very short")

        return len(reasons) > 0, reasons

    def _generate_reasoning(
        self,
        intent: IntentType,
        scores: Dict[IntentType, float],
        prompt: str,
    ) -> str:
        """Generate human-readable reasoning for the classification."""
        score = scores[intent]

        if score > 0.8:
            return f"Strong match for {intent.value} intent based on keywords and patterns"
        elif score > 0.6:
            return f"Likely {intent.value} intent, though some ambiguity exists"
        elif score > 0.4:
            return f"Possibly {intent.value} intent, but confidence is low"
        else:
            return f"Weak signal for {intent.value} intent, clarification recommended"

    def _generate_clarification(
        self,
        prompt: str,
        scores: Dict[IntentType, float],
        ambiguity_reasons: List[str],
    ) -> List[str]:
        """Generate clarification questions when intent is ambiguous."""
        questions = []

        # Get top 2 intents
        sorted_intents = sorted(scores.items(), key=lambda x: x[1], reverse=True)
        top_intents = [i[0] for i in sorted_intents[:2]]

        # Ask about the distinction
        if IntentType.CODE in top_intents and IntentType.REFACTOR in top_intents:
            questions.append(
                "Do you want to write new code or refactor existing code?"
            )
        elif IntentType.ASK in top_intents and IntentType.EXPLAIN in top_intents:
            questions.append(
                "Are you asking a general question or do you want an explanation of specific code?"
            )
        elif IntentType.FIX in top_intents and IntentType.REFACTOR in top_intents:
            questions.append(
                "Is there a bug to fix, or do you want to improve the code structure?"
            )

        # Generic questions based on ambiguity
        if "Vague reference detected" in ambiguity_reasons:
            questions.append(
                "Could you specify which file, function, or code section you're referring to?"
            )

        if "Prompt is very short" in ambiguity_reasons:
            questions.append(
                "Could you provide more details about what you'd like me to do?"
            )

        # Default question if none generated
        if not questions:
            questions.append(
                "I'm not sure I understand. Could you clarify what you'd like me to do?"
            )

        return questions[:3]  # Limit to 3 questions


# Convenience function for direct classification
def classify_intent(context: str, prompt: str, files: List[str] = None) -> IntentResponse:
    """
    Classify a prompt into an intent.

    Args:
        context: Buffer/file context
        prompt: User's prompt
        files: Referenced file paths

    Returns:
        IntentResponse with classification
    """
    classifier = IntentClassifier()
    request = IntentRequest(
        context=context,
        prompt=prompt,
        files=files or [],
    )
    return classifier.classify(request)
