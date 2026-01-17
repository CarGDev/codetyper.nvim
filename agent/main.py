"""
Agent main entry point - JSON-RPC server over stdin/stdout.

This module implements the main loop that:
1. Reads JSON-RPC requests from stdin
2. Dispatches to appropriate handlers based on method name
3. Writes JSON-RPC responses to stdout
4. Handles graceful shutdown on SIGTERM/SIGINT

Usage:
    python -m agent.main

The agent is spawned as a subprocess by Lua and communicates
via stdin/stdout. Each request is processed synchronously.

Methods:
    - classify_intent: Classify user intent from context
    - build_plan: Construct execution plan from intent
    - validate_plan: Validate plan before execution
    - format_output: Format agent output for display
    - ping: Health check
"""

import sys
import signal
import logging
from typing import NoReturn

from .protocol import (
    parse_request,
    handle_request,
    format_response,
    make_error_response,
    RPCError,
    RPCErrorCodes,
)


# Configure logging to stderr (stdout is for protocol)
logging.basicConfig(
    level=logging.INFO,
    format="[agent] %(levelname)s: %(message)s",
    stream=sys.stderr,
)
logger = logging.getLogger(__name__)


# Flag for graceful shutdown
_running = True


def signal_handler(signum: int, frame) -> None:
    """Handle shutdown signals."""
    global _running
    logger.info(f"Received signal {signum}, shutting down...")
    _running = False


def read_request() -> str | None:
    """
    Read a single request from stdin.

    Returns:
        The raw request string, or None if EOF
    """
    try:
        line = sys.stdin.readline()
        if not line:
            return None
        return line.strip()
    except Exception as e:
        logger.error(f"Error reading from stdin: {e}")
        return None


def write_response(response: str) -> None:
    """
    Write a response to stdout.

    Args:
        response: JSON-encoded response string
    """
    try:
        sys.stdout.write(response + "\n")
        sys.stdout.flush()
    except Exception as e:
        logger.error(f"Error writing to stdout: {e}")


def process_request(raw: str) -> str:
    """
    Process a single request and return the response.

    Args:
        raw: Raw JSON request string

    Returns:
        JSON response string
    """
    try:
        # Parse the request
        request = parse_request(raw)

        # Handle the request
        response = handle_request(request)

        # Format and return
        return format_response(response)

    except RPCError as e:
        # Protocol-level error
        return format_response(make_error_response(e))
    except Exception as e:
        # Unexpected error
        logger.exception("Unexpected error processing request")
        return format_response(make_error_response(
            RPCError(RPCErrorCodes.INTERNAL_ERROR, str(e))
        ))


def main_loop() -> None:
    """
    Main server loop.

    Reads requests from stdin, processes them, and writes responses to stdout.
    Continues until EOF or shutdown signal.
    """
    global _running

    logger.info("Agent started, waiting for requests...")

    while _running:
        # Read next request
        raw = read_request()

        # Check for EOF
        if raw is None:
            logger.info("EOF received, shutting down...")
            break

        # Skip empty lines
        if not raw:
            continue

        # Process and respond
        logger.debug(f"Processing request: {raw[:100]}...")
        response = process_request(raw)
        write_response(response)

    logger.info("Agent stopped")


def main() -> NoReturn:
    """Main entry point."""
    # Set up signal handlers
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    try:
        main_loop()
        sys.exit(0)
    except KeyboardInterrupt:
        logger.info("Interrupted")
        sys.exit(0)
    except Exception as e:
        logger.exception("Fatal error")
        sys.exit(1)


if __name__ == "__main__":
    main()
