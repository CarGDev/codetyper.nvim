"""
Tests for intent classification.

Tests the IntentClassifier for various input types and edge cases.
"""

import sys
import os

# Add agent to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from agent.intent import IntentClassifier, classify_intent
from agent.schemas import IntentRequest, IntentType


class TestIntentClassifier:
    """Tests for IntentClassifier."""

    def setup_method(self):
        """Create a classifier instance for each test."""
        self.classifier = IntentClassifier()

    def test_classify_code_intent(self):
        """Test classification of code generation requests."""
        request = IntentRequest(
            context="",
            prompt="write a function to sort an array",
        )
        result = self.classifier.classify(request)
        assert result.intent == IntentType.CODE
        assert result.confidence >= 0.7

    def test_classify_refactor_intent(self):
        """Test classification of refactoring requests."""
        request = IntentRequest(
            context="def foo(): pass",
            prompt="refactor this code to be more efficient",
        )
        result = self.classifier.classify(request)
        assert result.intent == IntentType.REFACTOR
        assert result.confidence >= 0.7

    def test_classify_fix_intent(self):
        """Test classification of bug fix requests."""
        request = IntentRequest(
            context="",
            prompt="fix the bug in the login function",
        )
        result = self.classifier.classify(request)
        assert result.intent == IntentType.FIX
        assert result.confidence >= 0.7

    def test_classify_test_intent(self):
        """Test classification of test writing requests."""
        request = IntentRequest(
            context="",
            prompt="write unit tests for the user service",
        )
        result = self.classifier.classify(request)
        assert result.intent == IntentType.TEST
        assert result.confidence >= 0.7

    def test_classify_document_intent(self):
        """Test classification of documentation requests."""
        request = IntentRequest(
            context="",
            prompt="add docstrings to this module",
        )
        result = self.classifier.classify(request)
        assert result.intent == IntentType.DOCUMENT
        assert result.confidence >= 0.7

    def test_classify_explain_intent(self):
        """Test classification of explanation requests."""
        request = IntentRequest(
            context="def complex_algo(): ...",
            prompt="explain what this function does",
        )
        result = self.classifier.classify(request)
        assert result.intent == IntentType.EXPLAIN
        assert result.confidence >= 0.7

    def test_strong_indicator_high_confidence(self):
        """Test that strong indicators give high confidence."""
        result = classify_intent("", "implement a new feature")
        assert result.confidence >= 0.9

    def test_ambiguous_request_low_confidence(self):
        """Test that ambiguous requests have lower confidence."""
        result = classify_intent("", "change it")
        # Should either have low confidence or need clarification
        assert result.confidence < 0.7 or result.needs_clarification

    def test_short_prompt_needs_clarification(self):
        """Test that very short prompts may need clarification."""
        result = classify_intent("", "do")
        assert result.needs_clarification or result.confidence < 0.7

    def test_clarification_questions_generated(self):
        """Test that clarification questions are generated when needed."""
        result = classify_intent("", "improve this")
        if result.needs_clarification:
            assert len(result.clarification_questions) > 0

    def test_convenience_function(self):
        """Test the classify_intent convenience function."""
        result = classify_intent(
            context="some code context",
            prompt="add error handling",
            files=["main.py"],
        )
        assert result.intent is not None
        assert 0 <= result.confidence <= 1
        assert result.reasoning != ""


class TestIntentPatterns:
    """Test specific pattern matching."""

    def test_question_marks_suggest_ask(self):
        """Test that question marks influence ASK intent."""
        result = classify_intent("", "what is the purpose of this code?")
        assert result.intent in (IntentType.ASK, IntentType.EXPLAIN)

    def test_create_keywords_suggest_code(self):
        """Test that create/build keywords suggest CODE."""
        result = classify_intent("", "create a new component for the dashboard")
        assert result.intent == IntentType.CODE

    def test_fix_keywords_suggest_fix(self):
        """Test that fix/bug keywords suggest FIX."""
        result = classify_intent("", "there's a bug when users login")
        assert result.intent == IntentType.FIX

    def test_test_keywords_suggest_test(self):
        """Test that test keywords suggest TEST."""
        result = classify_intent("", "we need more test coverage")
        assert result.intent == IntentType.TEST
