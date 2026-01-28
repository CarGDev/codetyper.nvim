"""
JSON-RPC protocol implementation for Lua <-> Agent communication.

This module defines:
- Request/response message formats
- Method routing and dispatch
- Error handling with structured error codes

Protocol:
    Request:  {"jsonrpc": "2.0", "method": str, "params": dict, "id": int}
    Response: {"jsonrpc": "2.0", "result": any, "id": int}
    Error:    {"jsonrpc": "2.0", "error": {"code": int, "message": str}, "id": int}

Methods:
    - classify_intent: Classify user intent
    - build_plan: Build execution plan
    - validate_plan: Validate plan
    - format_output: Format output for display

Error Codes:
    - -32700: Parse error
    - -32600: Invalid request
    - -32601: Method not found
    - -32602: Invalid params
    - -32603: Internal error
    - -32000 to -32099: Server errors (custom)
"""

from typing import Any, Callable, Dict, Optional, TypeVar, Union
from dataclasses import dataclass, asdict
import json
import traceback

from .schemas import (
    IntentRequest,
    IntentResponse,
    PlanRequest,
    PlanResponse,
    ValidationRequest,
    ValidationResponse,
    serialize,
    deserialize,
)


# Type alias for method handlers
MethodHandler = Callable[[Dict[str, Any]], Any]

# Registry of method handlers
_method_registry: Dict[str, MethodHandler] = {}


class RPCErrorCodes:
    """Standard JSON-RPC error codes."""
    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603
    # Custom server errors
    INTENT_CLASSIFICATION_FAILED = -32001
    PLAN_CONSTRUCTION_FAILED = -32002
    VALIDATION_FAILED = -32003
    CONTEXT_ERROR = -32004
    FORMATTING_ERROR = -32005


@dataclass
class RPCError(Exception):
    """JSON-RPC error with code and message."""
    code: int
    message: str
    data: Optional[Any] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to JSON-RPC error object."""
        error = {
            "code": self.code,
            "message": self.message,
        }
        if self.data is not None:
            error["data"] = self.data
        return error


@dataclass
class RPCRequest:
    """Parsed JSON-RPC request."""
    jsonrpc: str
    method: str
    params: Dict[str, Any]
    id: Union[int, str, None]

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "RPCRequest":
        """Parse request from dict."""
        return cls(
            jsonrpc=data.get("jsonrpc", ""),
            method=data.get("method", ""),
            params=data.get("params", {}),
            id=data.get("id"),
        )

    def validate(self) -> None:
        """Validate request structure."""
        if self.jsonrpc != "2.0":
            raise RPCError(
                RPCErrorCodes.INVALID_REQUEST,
                "Invalid JSON-RPC version, expected '2.0'",
            )
        if not self.method:
            raise RPCError(
                RPCErrorCodes.INVALID_REQUEST,
                "Missing 'method' field",
            )
        if not isinstance(self.method, str):
            raise RPCError(
                RPCErrorCodes.INVALID_REQUEST,
                "'method' must be a string",
            )
        if self.params is not None and not isinstance(self.params, dict):
            raise RPCError(
                RPCErrorCodes.INVALID_PARAMS,
                "'params' must be an object",
            )


def make_response(result: Any, request_id: Union[int, str, None]) -> Dict[str, Any]:
    """Create a JSON-RPC success response."""
    return {
        "jsonrpc": "2.0",
        "result": serialize(result) if hasattr(result, "__dataclass_fields__") else result,
        "id": request_id,
    }


def make_error_response(
    error: RPCError,
    request_id: Union[int, str, None] = None,
) -> Dict[str, Any]:
    """Create a JSON-RPC error response."""
    return {
        "jsonrpc": "2.0",
        "error": error.to_dict(),
        "id": request_id,
    }


def register_method(name: str, handler: MethodHandler) -> None:
    """
    Register a method handler.

    Args:
        name: Method name (e.g., "classify_intent")
        handler: Function that takes params dict and returns result
    """
    _method_registry[name] = handler


def unregister_method(name: str) -> None:
    """Unregister a method handler."""
    _method_registry.pop(name, None)


def get_registered_methods() -> list:
    """Get list of registered method names."""
    return list(_method_registry.keys())


def handle_request(request: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle a JSON-RPC request and return a response.

    Args:
        request: Parsed JSON-RPC request dict

    Returns:
        JSON-RPC response dict
    """
    request_id = request.get("id")

    try:
        # Parse and validate request
        rpc_request = RPCRequest.from_dict(request)
        rpc_request.validate()

        # Look up method handler
        handler = _method_registry.get(rpc_request.method)
        if handler is None:
            raise RPCError(
                RPCErrorCodes.METHOD_NOT_FOUND,
                f"Method '{rpc_request.method}' not found",
            )

        # Execute handler
        result = handler(rpc_request.params)

        return make_response(result, request_id)

    except RPCError as e:
        return make_error_response(e, request_id)
    except Exception as e:
        # Wrap unexpected errors
        return make_error_response(
            RPCError(
                RPCErrorCodes.INTERNAL_ERROR,
                str(e),
                data=traceback.format_exc(),
            ),
            request_id,
        )


def parse_request(raw: str) -> Dict[str, Any]:
    """
    Parse a raw JSON string into a request dict.

    Args:
        raw: Raw JSON string

    Returns:
        Parsed request dict

    Raises:
        RPCError: If JSON parsing fails
    """
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        raise RPCError(
            RPCErrorCodes.PARSE_ERROR,
            f"Invalid JSON: {e.msg}",
        )


def format_response(response: Dict[str, Any]) -> str:
    """
    Format a response dict as JSON string.

    Args:
        response: Response dict

    Returns:
        JSON string
    """
    return json.dumps(response, ensure_ascii=False)


# ============================================================
# Method Handlers
# ============================================================

def _handle_classify_intent(params: Dict[str, Any]) -> Dict[str, Any]:
    """Handle classify_intent method."""
    from .intent import IntentClassifier
    from .schemas import IntentRequest

    try:
        request = deserialize(IntentRequest, params)
    except (KeyError, TypeError) as e:
        raise RPCError(
            RPCErrorCodes.INVALID_PARAMS,
            f"Invalid params for classify_intent: {e}",
        )

    classifier = IntentClassifier()
    response = classifier.classify(request)
    return serialize(response)


def _handle_build_plan(params: Dict[str, Any]) -> Dict[str, Any]:
    """Handle build_plan method."""
    from .planner import Planner
    from .schemas import PlanRequest

    try:
        request = deserialize(PlanRequest, params)
    except (KeyError, TypeError) as e:
        raise RPCError(
            RPCErrorCodes.INVALID_PARAMS,
            f"Invalid params for build_plan: {e}",
        )

    planner = Planner()
    response = planner.build_plan(request)
    return serialize(response)


def _handle_validate_plan(params: Dict[str, Any]) -> Dict[str, Any]:
    """Handle validate_plan method."""
    from .validator import PlanValidator
    from .schemas import ValidationRequest

    try:
        request = deserialize(ValidationRequest, params)
    except (KeyError, TypeError) as e:
        raise RPCError(
            RPCErrorCodes.INVALID_PARAMS,
            f"Invalid params for validate_plan: {e}",
        )

    validator = PlanValidator()
    response = validator.validate(request)
    return serialize(response)


def _handle_format_output(params: Dict[str, Any]) -> Dict[str, Any]:
    """Handle format_output method."""
    from .formatter import OutputFormatter

    formatter = OutputFormatter()
    format_type = params.get("type", "plan")
    data = params.get("data", {})

    if format_type == "plan":
        from .schemas import PlanResponse
        plan = deserialize(PlanResponse, data)
        return {"formatted": formatter.format_plan(plan)}
    elif format_type == "diff":
        return {"formatted": formatter.format_diff(
            data.get("original", ""),
            data.get("modified", ""),
        )}
    elif format_type == "error":
        return {"formatted": formatter.format_error(
            Exception(data.get("message", "Unknown error")),
            data.get("context"),
        )}
    else:
        raise RPCError(
            RPCErrorCodes.INVALID_PARAMS,
            f"Unknown format type: {format_type}",
        )


def _handle_ping(params: Dict[str, Any]) -> Dict[str, Any]:
    """Handle ping method for health checks."""
    return {"status": "ok", "version": "0.1.0"}


# ============================================================
# Memory Methods
# ============================================================

# Global memory state (initialized per project)
_memory_graph = None
_memory_storage = None
_memory_learners = None


def _ensure_memory_initialized(project_root: str):
    """Ensure memory system is initialized for the project."""
    global _memory_graph, _memory_storage, _memory_learners

    from .memory import MemoryGraph, MemoryStorage, PatternLearner, ConventionLearner, CorrectionLearner

    if _memory_storage is None or str(_memory_storage.project_root) != project_root:
        _memory_storage = MemoryStorage(project_root)
        _memory_graph = _memory_storage.load()
        _memory_learners = {
            "pattern": PatternLearner(_memory_graph),
            "convention": ConventionLearner(_memory_graph),
            "correction": CorrectionLearner(_memory_graph),
        }


def _handle_memory_learn(params: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle memory_learn method.

    Learns from an event (edit, correction, approval, etc.)

    Params:
        project_root: str - Project root directory
        event_type: str - Type of event (edit, correction, approval, rejection)
        data: dict - Event data
    """
    project_root = params.get("project_root", ".")
    event_type = params.get("event_type", "")
    event_data = params.get("data", {})

    if not event_type:
        raise RPCError(RPCErrorCodes.INVALID_PARAMS, "event_type is required")

    _ensure_memory_initialized(project_root)

    from .memory.learners import Event

    event = Event(type=event_type, data=event_data)

    # Let all learners observe the event
    for learner in _memory_learners.values():
        learner.observe(event)

    # Save changes
    saved = _memory_storage.save(_memory_graph)

    return {
        "learned": True,
        "saved": saved,
        "node_count": len(_memory_graph._nodes),
    }


def _handle_memory_query(params: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle memory_query method.

    Query the memory graph for relevant knowledge.

    Params:
        project_root: str - Project root directory
        node_type: str|None - Filter by node type
        content_pattern: str|None - Filter by content pattern
        limit: int - Maximum results (default 20)
    """
    project_root = params.get("project_root", ".")
    node_type_str = params.get("node_type")
    content_pattern = params.get("content_pattern")
    limit = params.get("limit", 20)

    _ensure_memory_initialized(project_root)

    from .memory.graph import NodeType

    node_type = None
    if node_type_str:
        try:
            node_type = NodeType(node_type_str)
        except ValueError:
            pass  # Invalid type, ignore filter

    nodes = _memory_graph.query(node_type=node_type, content_pattern=content_pattern)

    # Limit results
    nodes = nodes[:limit]

    return {
        "nodes": [
            {
                "id": n.id,
                "type": n.type.value,
                "content": n.content,
                "metadata": n.metadata,
            }
            for n in nodes
        ],
        "total": len(nodes),
    }


def _handle_memory_get_context(params: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle memory_get_context method.

    Get formatted memory context for LLM prompts.

    Params:
        project_root: str - Project root directory
        context_type: str - Type of context (patterns, conventions, corrections, all)
        max_tokens: int - Maximum tokens budget (default 2000)
    """
    project_root = params.get("project_root", ".")
    context_type = params.get("context_type", "all")
    max_tokens = params.get("max_tokens", 2000)

    _ensure_memory_initialized(project_root)

    from .memory.graph import NodeType

    lines = []
    char_budget = max_tokens * 4  # Rough estimate: 4 chars per token

    # Gather relevant nodes based on context type
    if context_type in ("patterns", "all"):
        patterns = _memory_graph.query(node_type=NodeType.PATTERN)
        if patterns:
            lines.append("## Learned Patterns")
            for p in patterns[:10]:
                lines.append(f"- {p.content}")

    if context_type in ("conventions", "all"):
        conventions = _memory_graph.query(node_type=NodeType.CONVENTION)
        if conventions:
            lines.append("\n## Project Conventions")
            for c in conventions[:10]:
                lines.append(f"- {c.content}")

    if context_type in ("corrections", "all"):
        corrections = _memory_graph.query(node_type=NodeType.CORRECTION)
        if corrections:
            lines.append("\n## Past Corrections (avoid these mistakes)")
            for c in corrections[:5]:
                lines.append(f"- {c.content}")

    context_text = "\n".join(lines)

    # Truncate if needed
    if len(context_text) > char_budget:
        context_text = context_text[:char_budget] + "\n... (truncated)"

    return {
        "context": context_text,
        "char_count": len(context_text),
        "estimated_tokens": len(context_text) // 4,
    }


def _handle_memory_stats(params: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle memory_stats method.

    Get statistics about the memory system.

    Params:
        project_root: str - Project root directory
    """
    project_root = params.get("project_root", ".")

    _ensure_memory_initialized(project_root)

    from .memory.graph import NodeType

    # Count nodes by type
    type_counts = {}
    for node_type in NodeType:
        count = len(_memory_graph.query(node_type=node_type))
        if count > 0:
            type_counts[node_type.value] = count

    storage_info = _memory_storage.get_storage_info()

    return {
        "node_count": len(_memory_graph._nodes),
        "edge_count": len(_memory_graph._edges),
        "type_counts": type_counts,
        "storage": storage_info,
    }


def _handle_memory_clear(params: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle memory_clear method.

    Clear all memory for the project.

    Params:
        project_root: str - Project root directory
    """
    project_root = params.get("project_root", ".")

    _ensure_memory_initialized(project_root)

    _memory_graph.clear()
    deleted = _memory_storage.delete()

    return {
        "cleared": True,
        "file_deleted": deleted,
    }


# Register built-in methods
register_method("classify_intent", _handle_classify_intent)
register_method("build_plan", _handle_build_plan)
register_method("validate_plan", _handle_validate_plan)
register_method("format_output", _handle_format_output)
register_method("ping", _handle_ping)

# Register memory methods
register_method("memory_learn", _handle_memory_learn)
register_method("memory_query", _handle_memory_query)
register_method("memory_get_context", _handle_memory_get_context)
register_method("memory_stats", _handle_memory_stats)
register_method("memory_clear", _handle_memory_clear)
