"""
Tests for plan validation.

Tests the PlanValidator for various plan configurations.
"""

import sys
import os

# Add agent to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from agent.validator import PlanValidator, validate_plan
from agent.schemas import (
    ValidationRequest,
    PlanResponse,
    PlanStep,
    ActionType,
)


class TestPlanValidator:
    """Tests for PlanValidator."""

    def setup_method(self):
        """Create a validator instance for each test."""
        self.validator = PlanValidator()

    def _make_plan(self, steps):
        """Helper to create a PlanResponse."""
        return PlanResponse(steps=steps)

    def test_valid_plan_passes(self):
        """Test that a valid plan passes validation."""
        plan = self._make_plan([
            PlanStep(id="1", action=ActionType.READ, target="file.py"),
            PlanStep(id="2", action=ActionType.EDIT, target="file.py", depends_on=["1"]),
        ])
        request = ValidationRequest(
            plan=plan,
            original_files={"file.py": "content"},
        )
        result = self.validator.validate(request)
        assert result.valid

    def test_empty_plan_is_valid(self):
        """Test that an empty plan is valid."""
        plan = self._make_plan([])
        request = ValidationRequest(plan=plan, original_files={})
        result = self.validator.validate(request)
        assert result.valid

    def test_missing_file_fails_validation(self):
        """Test that referencing a non-existent file fails."""
        plan = self._make_plan([
            PlanStep(id="1", action=ActionType.READ, target="nonexistent.py"),
        ])
        request = ValidationRequest(plan=plan, original_files={})
        result = self.validator.validate(request)
        assert not result.valid
        assert any("not found" in e.lower() for e in result.errors)

    def test_git_directory_is_protected(self):
        """Test that .git directory is protected."""
        plan = self._make_plan([
            PlanStep(id="1", action=ActionType.WRITE, target=".git/config"),
        ])
        request = ValidationRequest(plan=plan, original_files={})
        result = self.validator.validate(request)
        assert not result.valid
        assert any("protected" in e.lower() for e in result.errors)

    def test_node_modules_is_protected(self):
        """Test that node_modules is protected."""
        plan = self._make_plan([
            PlanStep(id="1", action=ActionType.EDIT, target="node_modules/pkg/index.js"),
        ])
        request = ValidationRequest(
            plan=plan,
            original_files={"node_modules/pkg/index.js": "code"},
        )
        result = self.validator.validate(request)
        assert not result.valid

    def test_env_files_protected(self):
        """Test that .env files are protected."""
        plan = self._make_plan([
            PlanStep(id="1", action=ActionType.WRITE, target=".env"),
        ])
        request = ValidationRequest(plan=plan, original_files={})
        result = self.validator.validate(request)
        assert not result.valid

    def test_secret_files_protected(self):
        """Test that files with 'secret' in name are protected."""
        plan = self._make_plan([
            PlanStep(id="1", action=ActionType.WRITE, target="my_secrets.json"),
        ])
        request = ValidationRequest(plan=plan, original_files={})
        result = self.validator.validate(request)
        assert not result.valid

    def test_key_files_protected(self):
        """Test that .pem/.key files are protected."""
        plan = self._make_plan([
            PlanStep(id="1", action=ActionType.WRITE, target="server.key"),
        ])
        request = ValidationRequest(plan=plan, original_files={})
        result = self.validator.validate(request)
        assert not result.valid

    def test_large_changes_warning(self):
        """Test that large changes generate warnings."""
        # Create plan with many writes
        steps = [
            PlanStep(id=str(i), action=ActionType.WRITE, target=f"file{i}.py")
            for i in range(10)
        ]
        plan = self._make_plan(steps)
        request = ValidationRequest(plan=plan, original_files={})
        result = self.validator.validate(request)
        # Should pass but with warnings
        assert len(result.warnings) > 0

    def test_delete_warning(self):
        """Test that delete operations generate warnings."""
        plan = self._make_plan([
            PlanStep(id="1", action=ActionType.DELETE, target="old_file.py"),
        ])
        request = ValidationRequest(
            plan=plan,
            original_files={"old_file.py": "content"},
        )
        result = self.validator.validate(request)
        assert any("delete" in w.lower() for w in result.warnings)

    def test_convenience_function(self):
        """Test the validate_plan convenience function."""
        plan = PlanResponse(steps=[
            PlanStep(id="1", action=ActionType.READ, target="file.py"),
        ])
        result = validate_plan(plan, {"file.py": "content"})
        assert result.valid


class TestCircularDependencies:
    """Test circular dependency detection."""

    def test_no_cycle_valid(self):
        """Test that linear dependencies are valid."""
        validator = PlanValidator()
        plan = PlanResponse(steps=[
            PlanStep(id="1", action=ActionType.READ, target="a.py"),
            PlanStep(id="2", action=ActionType.READ, target="b.py", depends_on=["1"]),
            PlanStep(id="3", action=ActionType.EDIT, target="c.py", depends_on=["2"]),
        ])
        request = ValidationRequest(
            plan=plan,
            original_files={"a.py": "", "b.py": "", "c.py": ""},
        )
        result = validator.validate(request)
        assert not any("circular" in e.lower() for e in result.errors)

    def test_invalid_dependency_detected(self):
        """Test that invalid dependency references are detected."""
        validator = PlanValidator()
        plan = PlanResponse(steps=[
            PlanStep(id="1", action=ActionType.READ, target="a.py", depends_on=["999"]),
        ])
        request = ValidationRequest(
            plan=plan,
            original_files={"a.py": ""},
        )
        result = validator.validate(request)
        assert not result.valid
        assert any("non-existent" in e.lower() for e in result.errors)
