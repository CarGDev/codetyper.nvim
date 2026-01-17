"""
Tests for JSON-RPC protocol.

Tests the protocol layer for request/response handling.
"""

import pytest
import sys
import os

# Add agent to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from agent.protocol import (
    handle_request,
    parse_request,
    format_response,
    make_response,
    make_error_response,
    RPCError,
    RPCErrorCodes,
    RPCRequest,
    get_registered_methods,
)
from agent.schemas import serialize, deserialize, IntentRequest, IntentResponse, IntentType


class TestProtocol:
    """Tests for JSON-RPC protocol."""

    def test_valid_ping_request(self):
        """Test that a valid ping request returns ok."""
        request = {
            "jsonrpc": "2.0",
            "method": "ping",
            "params": {},
            "id": 1,
        }
        response = handle_request(request)

        assert response["jsonrpc"] == "2.0"
        assert response["id"] == 1
        assert "result" in response
        assert response["result"]["status"] == "ok"

    def test_invalid_jsonrpc_version(self):
        """Test that invalid version returns error."""
        request = {
            "jsonrpc": "1.0",
            "method": "ping",
            "params": {},
            "id": 1,
        }
        response = handle_request(request)

        assert "error" in response
        assert response["error"]["code"] == RPCErrorCodes.INVALID_REQUEST

    def test_missing_method_returns_invalid_request(self):
        """Test that missing method field returns invalid request error."""
        request = {
            "jsonrpc": "2.0",
            "params": {},
            "id": 1,
        }
        response = handle_request(request)

        assert "error" in response
        assert response["error"]["code"] == RPCErrorCodes.INVALID_REQUEST

    def test_unknown_method_returns_method_not_found(self):
        """Test that unknown method returns method not found error."""
        request = {
            "jsonrpc": "2.0",
            "method": "nonexistent_method",
            "params": {},
            "id": 1,
        }
        response = handle_request(request)

        assert "error" in response
        assert response["error"]["code"] == RPCErrorCodes.METHOD_NOT_FOUND

    def test_response_includes_request_id(self):
        """Test that response includes the request ID."""
        request = {
            "jsonrpc": "2.0",
            "method": "ping",
            "params": {},
            "id": 42,
        }
        response = handle_request(request)

        assert response["id"] == 42

    def test_parse_request_valid_json(self):
        """Test parsing valid JSON."""
        raw = '{"jsonrpc": "2.0", "method": "ping", "params": {}, "id": 1}'
        parsed = parse_request(raw)

        assert parsed["method"] == "ping"
        assert parsed["id"] == 1

    def test_parse_request_invalid_json(self):
        """Test parsing invalid JSON raises RPCError."""
        with pytest.raises(RPCError) as exc_info:
            parse_request("not valid json")

        assert exc_info.value.code == RPCErrorCodes.PARSE_ERROR

    def test_format_response(self):
        """Test response formatting to JSON string."""
        response = {"jsonrpc": "2.0", "result": {"status": "ok"}, "id": 1}
        formatted = format_response(response)

        assert '"jsonrpc": "2.0"' in formatted
        assert '"status": "ok"' in formatted

    def test_make_response(self):
        """Test creating success response."""
        response = make_response({"data": "test"}, 1)

        assert response["jsonrpc"] == "2.0"
        assert response["result"] == {"data": "test"}
        assert response["id"] == 1

    def test_make_error_response(self):
        """Test creating error response."""
        error = RPCError(RPCErrorCodes.INTERNAL_ERROR, "Something went wrong")
        response = make_error_response(error, 1)

        assert response["jsonrpc"] == "2.0"
        assert response["error"]["code"] == RPCErrorCodes.INTERNAL_ERROR
        assert response["error"]["message"] == "Something went wrong"
        assert response["id"] == 1

    def test_registered_methods(self):
        """Test that expected methods are registered."""
        methods = get_registered_methods()

        assert "ping" in methods
        assert "classify_intent" in methods
        assert "build_plan" in methods
        assert "validate_plan" in methods
        assert "format_output" in methods

    def test_rpc_request_validation(self):
        """Test RPCRequest validation."""
        valid_request = RPCRequest(
            jsonrpc="2.0",
            method="ping",
            params={},
            id=1,
        )
        # Should not raise
        valid_request.validate()

    def test_rpc_request_validation_bad_version(self):
        """Test RPCRequest validation with bad version."""
        bad_request = RPCRequest(
            jsonrpc="1.0",
            method="ping",
            params={},
            id=1,
        )
        with pytest.raises(RPCError):
            bad_request.validate()


class TestSchemas:
    """Tests for schema serialization/deserialization."""

    def test_serialize_intent_response(self):
        """Test serializing IntentResponse."""
        response = IntentResponse(
            intent=IntentType.CODE,
            confidence=0.95,
            reasoning="User wants to write code",
        )
        serialized = serialize(response)

        assert serialized["intent"] == "code"
        assert serialized["confidence"] == 0.95
        assert serialized["reasoning"] == "User wants to write code"

    def test_deserialize_intent_request(self):
        """Test deserializing IntentRequest."""
        data = {
            "context": "some context",
            "prompt": "write a function",
            "files": ["file1.py"],
        }
        request = deserialize(IntentRequest, data)

        assert request.context == "some context"
        assert request.prompt == "write a function"
        assert request.files == ["file1.py"]

    def test_roundtrip_serialization(self):
        """Test that serialization and deserialization are inverses."""
        original = IntentResponse(
            intent=IntentType.REFACTOR,
            confidence=0.8,
            reasoning="User wants to refactor",
            needs_clarification=True,
            clarification_questions=["Which function?"],
        )

        serialized = serialize(original)
        deserialized = deserialize(IntentResponse, serialized)

        assert deserialized.intent == original.intent
        assert deserialized.confidence == original.confidence
        assert deserialized.reasoning == original.reasoning
        assert deserialized.needs_clarification == original.needs_clarification
        assert deserialized.clarification_questions == original.clarification_questions
