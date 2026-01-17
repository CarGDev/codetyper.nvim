"""
Plan construction module.

This module builds execution plans from classified intents.
It replaces all plan construction logic previously in Lua.

Responsibilities:
- Construct step-by-step execution plans
- Resolve dependencies between steps
- Generate rollback steps for safe undo
- Detect when more information is needed

Migrated from:
- lua/codetyper/features/agents/planner.lua
- lua/codetyper/core/scheduler/scheduler.lua (plan logic only)
"""

import uuid
from typing import Dict, List, Optional, Set, Tuple
from .schemas import (
    PlanRequest,
    PlanResponse,
    PlanStep,
    IntentType,
    ActionType,
)


class Planner:
    """
    Builds execution plans from intents.

    The planner is conservative - it prefers to ask for
    clarification rather than make assumptions about
    what the user wants.
    """

    def __init__(self):
        """Initialize the planner."""
        pass

    def build_plan(self, request: PlanRequest) -> PlanResponse:
        """
        Build an execution plan from an intent and context.

        Args:
            request: Plan request with intent, context, and files

        Returns:
            PlanResponse with ordered steps and optional clarifications
        """
        intent = request.intent
        context = request.context
        files = request.files

        # Check if clarification is needed
        needs_clarification, questions = self._needs_clarification(intent, context, files)
        if needs_clarification:
            return PlanResponse(
                steps=[],
                needs_clarification=True,
                clarification_questions=questions,
            )

        # Create steps based on intent
        steps = self._create_steps(intent, context, files)

        # Resolve dependencies
        steps = self._resolve_dependencies(steps)

        # Generate rollback steps
        rollback = self._generate_rollback(steps, files)

        return PlanResponse(
            steps=steps,
            needs_clarification=False,
            clarification_questions=[],
            rollback_steps=rollback,
        )

    def _create_steps(
        self,
        intent: IntentType,
        context: str,
        files: Dict[str, str],
    ) -> List[PlanStep]:
        """Create plan steps for the given intent."""
        steps = []

        if intent == IntentType.CODE:
            # For code generation, typically write to a file
            steps = self._plan_code_generation(context, files)
        elif intent == IntentType.REFACTOR:
            # For refactoring, read then edit existing files
            steps = self._plan_refactor(context, files)
        elif intent == IntentType.FIX:
            # For bug fixes, read then edit
            steps = self._plan_fix(context, files)
        elif intent == IntentType.DOCUMENT:
            # For documentation, edit existing files
            steps = self._plan_document(context, files)
        elif intent == IntentType.TEST:
            # For tests, create new test files
            steps = self._plan_tests(context, files)
        elif intent in (IntentType.ASK, IntentType.EXPLAIN):
            # For questions, just read files
            steps = self._plan_read_only(context, files)
        else:
            # Unknown intent - read files only
            steps = self._plan_read_only(context, files)

        return steps

    def _plan_code_generation(
        self,
        context: str,
        files: Dict[str, str],
    ) -> List[PlanStep]:
        """Plan for code generation intent."""
        steps = []

        # First, read existing files for context
        for path in files:
            steps.append(PlanStep(
                id=self._generate_id(),
                action=ActionType.READ,
                target=path,
                params={},
                depends_on=[],
            ))

        # Then write new code (file path determined by LLM)
        steps.append(PlanStep(
            id=self._generate_id(),
            action=ActionType.WRITE,
            target="<to_be_determined>",
            params={"content": "<generated_code>"},
            depends_on=[s.id for s in steps],  # Depends on all reads
        ))

        return steps

    def _plan_refactor(
        self,
        context: str,
        files: Dict[str, str],
    ) -> List[PlanStep]:
        """Plan for refactoring intent."""
        steps = []
        read_ids = []

        # Read all files first
        for path in files:
            step = PlanStep(
                id=self._generate_id(),
                action=ActionType.READ,
                target=path,
                params={},
                depends_on=[],
            )
            steps.append(step)
            read_ids.append(step.id)

        # Then edit each file
        for path in files:
            steps.append(PlanStep(
                id=self._generate_id(),
                action=ActionType.EDIT,
                target=path,
                params={"edits": []},  # Edits determined by LLM
                depends_on=read_ids,
            ))

        return steps

    def _plan_fix(
        self,
        context: str,
        files: Dict[str, str],
    ) -> List[PlanStep]:
        """Plan for bug fix intent."""
        # Similar to refactor - read then edit
        return self._plan_refactor(context, files)

    def _plan_document(
        self,
        context: str,
        files: Dict[str, str],
    ) -> List[PlanStep]:
        """Plan for documentation intent."""
        # Similar to refactor - read then edit
        return self._plan_refactor(context, files)

    def _plan_tests(
        self,
        context: str,
        files: Dict[str, str],
    ) -> List[PlanStep]:
        """Plan for test generation intent."""
        steps = []
        read_ids = []

        # Read source files first
        for path in files:
            step = PlanStep(
                id=self._generate_id(),
                action=ActionType.READ,
                target=path,
                params={},
                depends_on=[],
            )
            steps.append(step)
            read_ids.append(step.id)

        # Create test file(s)
        for path in files:
            test_path = self._derive_test_path(path)
            steps.append(PlanStep(
                id=self._generate_id(),
                action=ActionType.WRITE,
                target=test_path,
                params={"content": "<test_code>"},
                depends_on=read_ids,
            ))

        return steps

    def _plan_read_only(
        self,
        context: str,
        files: Dict[str, str],
    ) -> List[PlanStep]:
        """Plan for read-only operations (ask, explain)."""
        steps = []

        for path in files:
            steps.append(PlanStep(
                id=self._generate_id(),
                action=ActionType.READ,
                target=path,
                params={},
                depends_on=[],
            ))

        return steps

    def _derive_test_path(self, source_path: str) -> str:
        """Derive test file path from source file path."""
        import os

        dirname = os.path.dirname(source_path)
        basename = os.path.basename(source_path)
        name, ext = os.path.splitext(basename)

        # Common test file naming conventions
        if ext == ".py":
            return os.path.join(dirname, f"test_{name}{ext}")
        elif ext in (".js", ".ts", ".jsx", ".tsx"):
            return os.path.join(dirname, f"{name}.test{ext}")
        elif ext == ".lua":
            return os.path.join("tests", "spec", f"{name}_spec{ext}")
        else:
            return os.path.join(dirname, f"{name}_test{ext}")

    def _resolve_dependencies(self, steps: List[PlanStep]) -> List[PlanStep]:
        """
        Resolve dependencies and order steps.

        Uses topological sort to ensure no step runs before its dependencies.
        """
        if not steps:
            return steps

        # Build dependency graph
        step_map = {s.id: s for s in steps}
        in_degree = {s.id: len(s.depends_on) for s in steps}

        # Find steps with no dependencies
        queue = [s.id for s in steps if in_degree[s.id] == 0]
        ordered = []

        while queue:
            step_id = queue.pop(0)
            ordered.append(step_map[step_id])

            # Reduce in-degree for dependent steps
            for s in steps:
                if step_id in s.depends_on:
                    in_degree[s.id] -= 1
                    if in_degree[s.id] == 0:
                        queue.append(s.id)

        # Check for cycles
        if len(ordered) != len(steps):
            raise ValueError("Circular dependency detected in plan")

        return ordered

    def _generate_rollback(
        self,
        steps: List[PlanStep],
        original_files: Dict[str, str],
    ) -> List[PlanStep]:
        """Generate rollback steps to undo the plan."""
        rollback = []

        # Process in reverse order
        for step in reversed(steps):
            if step.action == ActionType.WRITE:
                # Rollback: delete the written file
                rollback.append(PlanStep(
                    id=self._generate_id(),
                    action=ActionType.DELETE,
                    target=step.target,
                    params={},
                    depends_on=[],
                ))
            elif step.action == ActionType.EDIT:
                # Rollback: restore original content
                if step.target in original_files:
                    rollback.append(PlanStep(
                        id=self._generate_id(),
                        action=ActionType.WRITE,
                        target=step.target,
                        params={"content": original_files[step.target]},
                        depends_on=[],
                    ))
            elif step.action == ActionType.DELETE:
                # Rollback: restore the deleted file
                if step.target in original_files:
                    rollback.append(PlanStep(
                        id=self._generate_id(),
                        action=ActionType.WRITE,
                        target=step.target,
                        params={"content": original_files[step.target]},
                        depends_on=[],
                    ))

        return rollback

    def _needs_clarification(
        self,
        intent: IntentType,
        context: str,
        files: Dict[str, str],
    ) -> Tuple[bool, List[str]]:
        """Check if clarification is needed before building plan."""
        questions = []

        # No files provided for file-modifying intents
        if intent in (IntentType.REFACTOR, IntentType.FIX, IntentType.DOCUMENT):
            if not files:
                questions.append("Which file(s) should I modify?")

        # CODE intent without clear target
        if intent == IntentType.CODE:
            if not files and not context:
                questions.append("Where should I create the new code? (file path)")

        # TEST intent without source files
        if intent == IntentType.TEST:
            if not files:
                questions.append("Which code should I write tests for?")

        return len(questions) > 0, questions

    def _generate_id(self) -> str:
        """Generate a unique step ID."""
        return str(uuid.uuid4())[:8]


# Convenience function
def build_plan(
    intent: IntentType,
    context: str,
    files: Dict[str, str],
) -> PlanResponse:
    """
    Build an execution plan.

    Args:
        intent: Classified intent
        context: Context string
        files: File path -> content mapping

    Returns:
        PlanResponse with steps
    """
    planner = Planner()
    request = PlanRequest(
        intent=intent,
        context=context,
        files=files,
    )
    return planner.build_plan(request)
