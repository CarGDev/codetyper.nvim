"""
Pydantic-style schemas for request/response validation.

This module defines the data structures for all agent communication:

Intent Classification:
    - IntentRequest: Context and prompt for classification
    - IntentResponse: Classified intent with confidence

Plan Construction:
    - PlanRequest: Intent and context for planning
    - PlanResponse: Execution plan with steps
    - PlanStep: Single step in a plan

Validation:
    - ValidationRequest: Plan to validate
    - ValidationResponse: Validation result

These schemas ensure type safety and provide automatic
validation of all data crossing the Lua/Python boundary.
"""

from typing import List, Dict, Optional, Any, Type, TypeVar, get_type_hints, get_origin, get_args
from enum import Enum
from dataclasses import dataclass, field, fields, is_dataclass


T = TypeVar("T")


class IntentType(Enum):
    """Supported intent types."""
    ASK = "ask"
    CODE = "code"
    REFACTOR = "refactor"
    DOCUMENT = "document"
    FIX = "fix"
    EXPLAIN = "explain"
    TEST = "test"
    UNKNOWN = "unknown"


class ActionType(Enum):
    """Supported plan action types."""
    READ = "read"
    WRITE = "write"
    EDIT = "edit"
    DELETE = "delete"
    RENAME = "rename"
    CREATE_DIR = "create_dir"


@dataclass
class IntentRequest:
    """Request for intent classification."""
    context: str  # Buffer content and surrounding context
    prompt: str   # User's prompt/instruction
    files: List[str] = field(default_factory=list)  # Referenced files


@dataclass
class IntentResponse:
    """Response from intent classification."""
    intent: IntentType
    confidence: float  # 0.0 to 1.0
    reasoning: str     # Explanation of classification
    needs_clarification: bool = False
    clarification_questions: List[str] = field(default_factory=list)


@dataclass
class PlanStep:
    """Single step in an execution plan."""
    id: str
    action: ActionType
    target: str           # File path or identifier
    params: Dict[str, Any] = field(default_factory=dict)
    depends_on: List[str] = field(default_factory=list)  # Step IDs


@dataclass
class PlanRequest:
    """Request for plan construction."""
    intent: IntentType
    context: str
    files: Dict[str, str]  # path -> content


@dataclass
class PlanResponse:
    """Response from plan construction."""
    steps: List[PlanStep]
    needs_clarification: bool = False
    clarification_questions: List[str] = field(default_factory=list)
    rollback_steps: List[PlanStep] = field(default_factory=list)


@dataclass
class ValidationRequest:
    """Request for plan validation."""
    plan: PlanResponse
    original_files: Dict[str, str]  # path -> content


@dataclass
class ValidationResponse:
    """Response from plan validation."""
    valid: bool
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)


# ============================================================
# Serialization / Deserialization
# ============================================================

def serialize(obj: Any) -> Any:
    """
    Serialize a dataclass or value to JSON-compatible dict.

    Handles:
    - Dataclasses -> dict
    - Enums -> string value
    - Lists -> lists with serialized items
    - Dicts -> dicts with serialized values
    - Primitives -> as-is
    """
    if obj is None:
        return None

    if isinstance(obj, Enum):
        return obj.value

    if is_dataclass(obj) and not isinstance(obj, type):
        result = {}
        for f in fields(obj):
            value = getattr(obj, f.name)
            result[f.name] = serialize(value)
        return result

    if isinstance(obj, list):
        return [serialize(item) for item in obj]

    if isinstance(obj, dict):
        return {k: serialize(v) for k, v in obj.items()}

    # Primitive types (str, int, float, bool)
    return obj


def deserialize(cls: Type[T], data: Any) -> T:
    """
    Deserialize a dict to a dataclass instance.

    Handles:
    - dict -> dataclass
    - string -> Enum
    - list -> list with deserialized items
    - Primitives -> as-is
    """
    if data is None:
        return None

    # Handle Enum types
    if isinstance(cls, type) and issubclass(cls, Enum):
        return cls(data)

    # Handle dataclasses
    if is_dataclass(cls):
        if not isinstance(data, dict):
            raise TypeError(f"Expected dict for {cls.__name__}, got {type(data).__name__}")

        type_hints = get_type_hints(cls)
        kwargs = {}

        for f in fields(cls):
            field_name = f.name
            field_type = type_hints.get(field_name, Any)

            if field_name in data:
                kwargs[field_name] = _deserialize_field(field_type, data[field_name])
            elif f.default is not field.default:
                kwargs[field_name] = f.default
            elif f.default_factory is not field.default_factory:
                kwargs[field_name] = f.default_factory()

        return cls(**kwargs)

    # Handle generic types (List, Dict, Optional)
    origin = get_origin(cls)

    if origin is list:
        item_type = get_args(cls)[0] if get_args(cls) else Any
        return [deserialize(item_type, item) for item in data]

    if origin is dict:
        key_type, value_type = get_args(cls) if get_args(cls) else (Any, Any)
        return {k: deserialize(value_type, v) for k, v in data.items()}

    # Primitive or unknown type
    return data


def _deserialize_field(field_type: Any, value: Any) -> Any:
    """Helper to deserialize a single field value."""
    if value is None:
        return None

    origin = get_origin(field_type)

    # Handle Optional[X] (Union[X, None])
    if origin is type(None) or (hasattr(origin, "__origin__") and origin.__origin__ is type(None)):
        return None

    # Handle List[X]
    if origin is list:
        item_type = get_args(field_type)[0] if get_args(field_type) else Any
        return [deserialize(item_type, item) for item in value]

    # Handle Dict[K, V]
    if origin is dict:
        args = get_args(field_type)
        value_type = args[1] if len(args) > 1 else Any
        return {k: deserialize(value_type, v) for k, v in value.items()}

    # Handle Enum
    if isinstance(field_type, type) and issubclass(field_type, Enum):
        return field_type(value)

    # Handle nested dataclass
    if is_dataclass(field_type):
        return deserialize(field_type, value)

    # Primitive type
    return value


# ============================================================
# Validation Helpers
# ============================================================

def validate_intent_request(data: Dict[str, Any]) -> List[str]:
    """Validate intent request data and return list of errors."""
    errors = []

    if "context" not in data:
        errors.append("Missing required field: context")
    elif not isinstance(data["context"], str):
        errors.append("Field 'context' must be a string")

    if "prompt" not in data:
        errors.append("Missing required field: prompt")
    elif not isinstance(data["prompt"], str):
        errors.append("Field 'prompt' must be a string")

    if "files" in data and not isinstance(data["files"], list):
        errors.append("Field 'files' must be a list")

    return errors


def validate_plan_request(data: Dict[str, Any]) -> List[str]:
    """Validate plan request data and return list of errors."""
    errors = []

    if "intent" not in data:
        errors.append("Missing required field: intent")
    else:
        try:
            IntentType(data["intent"])
        except ValueError:
            errors.append(f"Invalid intent type: {data['intent']}")

    if "context" not in data:
        errors.append("Missing required field: context")

    if "files" not in data:
        errors.append("Missing required field: files")
    elif not isinstance(data["files"], dict):
        errors.append("Field 'files' must be a dict")

    return errors
