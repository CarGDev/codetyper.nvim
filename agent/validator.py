"""
Plan validation module.

This module validates execution plans before they are executed.
It ensures plans are safe, complete, and correct.

Responsibilities:
- Validate that all referenced files exist or will be created
- Check for circular dependencies
- Detect destructive operations on protected files
- Validate edit operations have valid targets
- Check file permissions

Migrated from:
- lua/codetyper/executor/validate.lua (logic only)
"""

import os
import fnmatch
from typing import Dict, List, Set
from .schemas import (
    ValidationRequest,
    ValidationResponse,
    PlanResponse,
    PlanStep,
    ActionType,
)


class PlanValidator:
    """
    Validates execution plans before execution.

    The validator is strict - it rejects any plan that
    might cause unintended consequences.
    """

    # Files/directories that should never be modified
    PROTECTED_PATHS = {
        ".git",
        ".git/",
        ".gitignore",
        "node_modules",
        "node_modules/",
        "__pycache__",
        "__pycache__/",
        ".env",
        ".env.local",
        ".env.production",
        "*.pem",
        "*.key",
        "*.crt",
        "id_rsa",
        "id_ed25519",
        ".ssh/",
        "credentials.json",
        "secrets.json",
        "package-lock.json",
        "yarn.lock",
        "Cargo.lock",
    }

    # Patterns for protected files
    PROTECTED_PATTERNS = [
        "*.pem",
        "*.key",
        "*.crt",
        "*.p12",
        "*secret*",
        "*credential*",
        ".env*",
    ]

    def __init__(self):
        """Initialize the validator."""
        pass

    def validate(self, request: ValidationRequest) -> ValidationResponse:
        """
        Validate an execution plan.

        Args:
            request: Validation request with plan and original files

        Returns:
            ValidationResponse with result and any errors/warnings
        """
        errors: List[str] = []
        warnings: List[str] = []

        # Run all validation checks
        errors.extend(self._check_file_references(request))
        errors.extend(self._check_circular_dependencies(request.plan))
        errors.extend(self._check_protected_paths(request.plan))
        errors.extend(self._check_edit_targets(request))
        warnings.extend(self._check_permissions(request.plan))
        warnings.extend(self._check_large_changes(request))

        return ValidationResponse(
            valid=len(errors) == 0,
            errors=errors,
            warnings=warnings,
        )

    def _check_file_references(self, request: ValidationRequest) -> List[str]:
        """Check that all referenced files exist or will be created."""
        errors = []
        plan = request.plan
        original_files = request.original_files

        # Track files that will be created
        will_be_created: Set[str] = set()

        for step in plan.steps:
            if step.action == ActionType.WRITE:
                will_be_created.add(step.target)

        # Check READ and EDIT targets
        for step in plan.steps:
            if step.action in (ActionType.READ, ActionType.EDIT):
                target = step.target
                if target not in original_files and target not in will_be_created:
                    # Check if it's a placeholder
                    if not target.startswith("<"):
                        errors.append(f"File not found: {target}")

            if step.action == ActionType.DELETE:
                target = step.target
                if target not in original_files:
                    errors.append(f"Cannot delete non-existent file: {target}")

        return errors

    def _check_circular_dependencies(self, plan: PlanResponse) -> List[str]:
        """Check for circular dependencies in plan steps."""
        errors = []

        # Build adjacency list
        step_ids = {s.id for s in plan.steps}
        adj: Dict[str, List[str]] = {s.id: list(s.depends_on) for s in plan.steps}

        # Check for invalid dependencies
        for step in plan.steps:
            for dep in step.depends_on:
                if dep not in step_ids:
                    errors.append(f"Step {step.id} depends on non-existent step {dep}")

        # DFS to detect cycles
        visited: Set[str] = set()
        rec_stack: Set[str] = set()

        def has_cycle(node: str) -> bool:
            visited.add(node)
            rec_stack.add(node)

            for neighbor in adj.get(node, []):
                if neighbor not in visited:
                    if has_cycle(neighbor):
                        return True
                elif neighbor in rec_stack:
                    return True

            rec_stack.remove(node)
            return False

        for step_id in step_ids:
            if step_id not in visited:
                if has_cycle(step_id):
                    errors.append("Circular dependency detected in plan")
                    break

        return errors

    def _check_protected_paths(self, plan: PlanResponse) -> List[str]:
        """Check that no protected paths are modified."""
        errors = []

        for step in plan.steps:
            if step.action in (ActionType.WRITE, ActionType.EDIT, ActionType.DELETE):
                target = step.target

                # Skip placeholders
                if target.startswith("<"):
                    continue

                # Check exact matches
                basename = os.path.basename(target)
                dirname = os.path.dirname(target)

                if basename in self.PROTECTED_PATHS:
                    errors.append(f"Cannot modify protected file: {target}")
                    continue

                # Check if path contains protected directory
                path_parts = target.split(os.sep)
                for part in path_parts:
                    if part in self.PROTECTED_PATHS or part + "/" in self.PROTECTED_PATHS:
                        errors.append(f"Cannot modify file in protected directory: {target}")
                        break

                # Check patterns
                for pattern in self.PROTECTED_PATTERNS:
                    if fnmatch.fnmatch(basename.lower(), pattern.lower()):
                        errors.append(f"Cannot modify protected file matching pattern '{pattern}': {target}")
                        break

        return errors

    def _check_edit_targets(self, request: ValidationRequest) -> List[str]:
        """Check that edit operations have valid search targets."""
        errors = []
        plan = request.plan
        original_files = request.original_files

        for step in plan.steps:
            if step.action == ActionType.EDIT:
                target = step.target
                edits = step.params.get("edits", [])

                if target not in original_files:
                    continue  # Already caught in file reference check

                content = original_files[target]

                for edit in edits:
                    if isinstance(edit, dict):
                        search = edit.get("search", "")
                        if search and search not in content:
                            errors.append(
                                f"Edit target not found in {target}: '{search[:50]}...'"
                            )

        return errors

    def _check_permissions(self, plan: PlanResponse) -> List[str]:
        """Check file permissions (returns warnings, not errors)."""
        warnings = []

        for step in plan.steps:
            if step.action in (ActionType.WRITE, ActionType.EDIT):
                target = step.target

                # Skip placeholders
                if target.startswith("<"):
                    continue

                # Check if file is writable (if it exists)
                if os.path.exists(target) and not os.access(target, os.W_OK):
                    warnings.append(f"File may not be writable: {target}")

                # Check if directory exists
                dirname = os.path.dirname(target)
                if dirname and not os.path.exists(dirname):
                    warnings.append(f"Directory does not exist: {dirname}")

        return warnings

    def _check_large_changes(self, request: ValidationRequest) -> List[str]:
        """Warn about large changes."""
        warnings = []
        plan = request.plan

        # Count modifications
        write_count = sum(1 for s in plan.steps if s.action == ActionType.WRITE)
        edit_count = sum(1 for s in plan.steps if s.action == ActionType.EDIT)
        delete_count = sum(1 for s in plan.steps if s.action == ActionType.DELETE)

        if write_count > 5:
            warnings.append(f"Plan creates {write_count} new files")

        if edit_count > 10:
            warnings.append(f"Plan modifies {edit_count} files")

        if delete_count > 0:
            warnings.append(f"Plan deletes {delete_count} files")

        total_steps = len(plan.steps)
        if total_steps > 20:
            warnings.append(f"Plan has {total_steps} steps, which is unusually large")

        return warnings


# Convenience function
def validate_plan(
    plan: PlanResponse,
    original_files: Dict[str, str],
) -> ValidationResponse:
    """
    Validate an execution plan.

    Args:
        plan: The plan to validate
        original_files: Original file contents

    Returns:
        ValidationResponse with result
    """
    validator = PlanValidator()
    request = ValidationRequest(
        plan=plan,
        original_files=original_files,
    )
    return validator.validate(request)
