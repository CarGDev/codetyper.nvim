"""
Output formatting module.

This module handles all output formatting for the agent.
It ensures consistent, predictable output formats.

Responsibilities:
- Format plans for human readability
- Generate diff output
- Format SEARCH/REPLACE blocks
- Format error messages

Migrated from:
- lua/codetyper/core/memory/output/formatter.lua
- lua/codetyper/core/diff/diff.lua (formatting only)
- lua/codetyper/core/diff/search_replace.lua (formatting only)
"""

import difflib
from typing import List, Dict, Any, Optional
from .schemas import PlanResponse, PlanStep, ActionType


class OutputFormatter:
    """
    Formats agent output for display.

    All output goes through this formatter to ensure
    consistent formatting across the system.
    """

    def __init__(self):
        """Initialize the formatter."""
        pass

    def format_plan(self, plan: PlanResponse) -> str:
        """
        Format a plan for human-readable display.

        Args:
            plan: The plan to format

        Returns:
            Human-readable plan summary
        """
        if not plan.steps:
            if plan.needs_clarification:
                return self.format_clarification(plan.clarification_questions)
            return "Empty plan - no actions to perform."

        lines = ["## Execution Plan", ""]

        # Group steps by action type
        reads = [s for s in plan.steps if s.action == ActionType.READ]
        writes = [s for s in plan.steps if s.action == ActionType.WRITE]
        edits = [s for s in plan.steps if s.action == ActionType.EDIT]
        deletes = [s for s in plan.steps if s.action == ActionType.DELETE]

        if reads:
            lines.append(f"**Read** {len(reads)} file(s):")
            for step in reads:
                lines.append(f"  - {step.target}")
            lines.append("")

        if edits:
            lines.append(f"**Edit** {len(edits)} file(s):")
            for step in edits:
                lines.append(f"  - {step.target}")
            lines.append("")

        if writes:
            lines.append(f"**Create** {len(writes)} file(s):")
            for step in writes:
                lines.append(f"  - {step.target}")
            lines.append("")

        if deletes:
            lines.append(f"**Delete** {len(deletes)} file(s):")
            for step in deletes:
                lines.append(f"  - {step.target}")
            lines.append("")

        # Add dependency info if complex
        has_deps = any(s.depends_on for s in plan.steps)
        if has_deps:
            lines.append("**Execution Order:**")
            for i, step in enumerate(plan.steps, 1):
                action_str = step.action.value.upper()
                lines.append(f"  {i}. [{action_str}] {step.target}")
            lines.append("")

        # Add rollback info
        if plan.rollback_steps:
            lines.append(f"*Rollback available ({len(plan.rollback_steps)} steps)*")

        return "\n".join(lines)

    def format_diff(self, original: str, modified: str) -> str:
        """
        Format a diff between two strings.

        Args:
            original: Original content
            modified: Modified content

        Returns:
            Unified diff format string
        """
        if not original and not modified:
            return ""

        original_lines = original.splitlines(keepends=True)
        modified_lines = modified.splitlines(keepends=True)

        diff = difflib.unified_diff(
            original_lines,
            modified_lines,
            fromfile="original",
            tofile="modified",
            lineterm="",
        )

        return "".join(diff)

    def format_search_replace(
        self,
        edits: List[Dict[str, str]],
    ) -> str:
        """
        Format edits as SEARCH/REPLACE blocks.

        Args:
            edits: List of {search: str, replace: str} dicts

        Returns:
            Formatted SEARCH/REPLACE blocks
        """
        blocks = []

        for edit in edits:
            search = edit.get("search", "")
            replace = edit.get("replace", "")

            block = [
                "<<<<<<< SEARCH",
                search,
                "=======",
                replace,
                ">>>>>>> REPLACE",
            ]
            blocks.append("\n".join(block))

        return "\n\n".join(blocks)

    def format_error(self, error: Exception, context: Optional[str] = None) -> str:
        """
        Format an error for display.

        Args:
            error: The exception to format
            context: Optional context about where error occurred

        Returns:
            Formatted error message
        """
        error_type = type(error).__name__
        error_msg = str(error)

        if context:
            return f"**Error** in {context}:\n  {error_type}: {error_msg}"
        else:
            return f"**Error**: {error_type}: {error_msg}"

    def format_clarification(self, questions: List[str]) -> str:
        """
        Format clarification questions for display.

        Args:
            questions: List of clarification questions

        Returns:
            Formatted questions
        """
        if not questions:
            return "I need more information to proceed."

        lines = ["I need some clarification before proceeding:", ""]
        for i, q in enumerate(questions, 1):
            lines.append(f"  {i}. {q}")

        return "\n".join(lines)

    def format_step_result(self, step: PlanStep, success: bool, message: str = "") -> str:
        """
        Format the result of a single step execution.

        Args:
            step: The step that was executed
            success: Whether it succeeded
            message: Optional result message

        Returns:
            Formatted result
        """
        status = "✓" if success else "✗"
        action = step.action.value.upper()

        result = f"{status} [{action}] {step.target}"
        if message:
            result += f"\n    {message}"

        return result

    def format_validation_result(
        self,
        valid: bool,
        errors: List[str],
        warnings: List[str],
    ) -> str:
        """
        Format validation results.

        Args:
            valid: Whether validation passed
            errors: List of errors
            warnings: List of warnings

        Returns:
            Formatted validation result
        """
        lines = []

        if valid:
            lines.append("✓ Plan validation passed")
        else:
            lines.append("✗ Plan validation failed")

        if errors:
            lines.append("")
            lines.append("**Errors:**")
            for error in errors:
                lines.append(f"  - {error}")

        if warnings:
            lines.append("")
            lines.append("**Warnings:**")
            for warning in warnings:
                lines.append(f"  - {warning}")

        return "\n".join(lines)

    def format_intent_result(
        self,
        intent: str,
        confidence: float,
        reasoning: str,
    ) -> str:
        """
        Format intent classification result.

        Args:
            intent: Classified intent
            confidence: Confidence score
            reasoning: Reasoning for classification

        Returns:
            Formatted result
        """
        conf_pct = int(confidence * 100)
        conf_bar = "█" * (conf_pct // 10) + "░" * (10 - conf_pct // 10)

        lines = [
            f"**Intent**: {intent}",
            f"**Confidence**: {conf_bar} {conf_pct}%",
            f"**Reasoning**: {reasoning}",
        ]

        return "\n".join(lines)


# Convenience functions
def format_plan(plan: PlanResponse) -> str:
    """Format a plan for display."""
    return OutputFormatter().format_plan(plan)


def format_diff(original: str, modified: str) -> str:
    """Format a diff between two strings."""
    return OutputFormatter().format_diff(original, modified)


def format_search_replace(edits: List[Dict[str, str]]) -> str:
    """Format edits as SEARCH/REPLACE blocks."""
    return OutputFormatter().format_search_replace(edits)
