"""
Tests for plan construction.

Tests the Planner for various intent types and file configurations.
"""

import sys
import os

# Add agent to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from agent.planner import Planner, build_plan
from agent.schemas import PlanRequest, IntentType, ActionType


class TestPlanner:
    """Tests for Planner."""

    def setup_method(self):
        """Create a planner instance for each test."""
        self.planner = Planner()

    def test_build_plan_for_code_intent(self):
        """Test plan construction for code generation."""
        request = PlanRequest(
            intent=IntentType.CODE,
            context="create a new utility",
            files={"utils.py": "# utils"},
        )
        result = self.planner.build_plan(request)

        assert len(result.steps) >= 1
        # Should have READ for context and WRITE for new code
        actions = [s.action for s in result.steps]
        assert ActionType.READ in actions
        assert ActionType.WRITE in actions

    def test_build_plan_for_refactor_intent(self):
        """Test plan construction for refactoring."""
        request = PlanRequest(
            intent=IntentType.REFACTOR,
            context="refactor",
            files={"main.py": "def foo(): pass"},
        )
        result = self.planner.build_plan(request)

        assert len(result.steps) >= 2
        # Should have READ then EDIT
        assert result.steps[0].action == ActionType.READ
        assert result.steps[-1].action == ActionType.EDIT

    def test_build_plan_for_fix_intent(self):
        """Test plan construction for bug fixes."""
        request = PlanRequest(
            intent=IntentType.FIX,
            context="fix bug",
            files={"buggy.py": "def bug(): ..."},
        )
        result = self.planner.build_plan(request)

        assert len(result.steps) >= 2
        actions = [s.action for s in result.steps]
        assert ActionType.READ in actions
        assert ActionType.EDIT in actions

    def test_build_plan_for_test_intent(self):
        """Test plan construction for test generation."""
        request = PlanRequest(
            intent=IntentType.TEST,
            context="write tests",
            files={"module.py": "def func(): pass"},
        )
        result = self.planner.build_plan(request)

        assert len(result.steps) >= 2
        # Should READ source and WRITE test
        actions = [s.action for s in result.steps]
        assert ActionType.READ in actions
        assert ActionType.WRITE in actions

    def test_read_only_for_explain(self):
        """Test that EXPLAIN intent only reads files."""
        request = PlanRequest(
            intent=IntentType.EXPLAIN,
            context="explain",
            files={"code.py": "# code"},
        )
        result = self.planner.build_plan(request)

        # All steps should be READ
        for step in result.steps:
            assert step.action == ActionType.READ

    def test_dependency_resolution(self):
        """Test that dependencies between steps are resolved correctly."""
        request = PlanRequest(
            intent=IntentType.REFACTOR,
            context="refactor",
            files={"a.py": "x", "b.py": "y"},
        )
        result = self.planner.build_plan(request)

        # EDIT steps should depend on READ steps
        read_ids = [s.id for s in result.steps if s.action == ActionType.READ]
        edit_steps = [s for s in result.steps if s.action == ActionType.EDIT]

        for edit in edit_steps:
            # Each EDIT should depend on at least some READs
            assert len(edit.depends_on) > 0

    def test_rollback_generation(self):
        """Test that rollback steps are generated."""
        request = PlanRequest(
            intent=IntentType.REFACTOR,
            context="refactor",
            files={"main.py": "original content"},
        )
        result = self.planner.build_plan(request)

        # Should have rollback steps
        assert len(result.rollback_steps) > 0

    def test_clarification_when_no_files(self):
        """Test that clarification is requested when no files provided."""
        request = PlanRequest(
            intent=IntentType.REFACTOR,
            context="refactor",
            files={},  # No files
        )
        result = self.planner.build_plan(request)

        assert result.needs_clarification
        assert len(result.clarification_questions) > 0

    def test_convenience_function(self):
        """Test the build_plan convenience function."""
        result = build_plan(
            intent=IntentType.CODE,
            context="create",
            files={"file.py": "content"},
        )
        assert result is not None
        assert len(result.steps) > 0


class TestPlanStepOrdering:
    """Test plan step ordering."""

    def test_reads_before_writes(self):
        """Test that READs come before WRITEs/EDITs."""
        planner = Planner()
        request = PlanRequest(
            intent=IntentType.CODE,
            context="create",
            files={"existing.py": "code"},
        )
        result = planner.build_plan(request)

        # Find first READ and first non-READ
        first_read_idx = None
        first_write_idx = None

        for i, step in enumerate(result.steps):
            if step.action == ActionType.READ and first_read_idx is None:
                first_read_idx = i
            if step.action in (ActionType.WRITE, ActionType.EDIT) and first_write_idx is None:
                first_write_idx = i

        if first_read_idx is not None and first_write_idx is not None:
            assert first_read_idx < first_write_idx

    def test_test_file_path_derivation(self):
        """Test that test file paths are derived correctly."""
        planner = Planner()

        # Python
        assert "test_" in planner._derive_test_path("module.py")

        # JavaScript
        assert ".test." in planner._derive_test_path("component.js")

        # Lua
        assert "_spec" in planner._derive_test_path("module.lua")
