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


# Register built-in methods
register_method("classify_intent", _handle_classify_intent)
register_method("build_plan", _handle_build_plan)
register_method("validate_plan", _handle_validate_plan)
register_method("format_output", _handle_format_output)
register_method("ping", _handle_ping)
