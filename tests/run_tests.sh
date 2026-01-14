#!/bin/bash
# Run codetyper.nvim tests using plenary.nvim

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Running codetyper.nvim tests...${NC}"
echo "Project root: $PROJECT_ROOT"
echo ""

# Check if plenary is installed
PLENARY_PATH=""
POSSIBLE_PATHS=(
    "$HOME/.local/share/nvim/lazy/plenary.nvim"
    "$HOME/.local/share/nvim/site/pack/packer/start/plenary.nvim"
    "$HOME/.config/nvim/plugged/plenary.nvim"
    "/opt/homebrew/share/nvim/site/pack/packer/start/plenary.nvim"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -d "$path" ]; then
        PLENARY_PATH="$path"
        break
    fi
done

if [ -z "$PLENARY_PATH" ]; then
    echo -e "${RED}Error: plenary.nvim not found!${NC}"
    echo "Please install plenary.nvim first:"
    echo "  - With lazy.nvim: { 'nvim-lua/plenary.nvim' }"
    echo "  - With packer: use 'nvim-lua/plenary.nvim'"
    exit 1
fi

echo "Found plenary at: $PLENARY_PATH"
echo ""

# Run tests
if [ "$1" == "--file" ] && [ -n "$2" ]; then
    # Run specific test file
    echo -e "${YELLOW}Running: $2${NC}"
    nvim --headless \
        -u "$SCRIPT_DIR/minimal_init.lua" \
        -c "PlenaryBustedFile $SCRIPT_DIR/spec/$2"
else
    # Run all tests
    echo -e "${YELLOW}Running all tests in spec/ directory${NC}"
    nvim --headless \
        -u "$SCRIPT_DIR/minimal_init.lua" \
        -c "PlenaryBustedDirectory $SCRIPT_DIR/spec/ {minimal_init = '$SCRIPT_DIR/minimal_init.lua'}"
fi

echo ""
echo -e "${GREEN}Tests completed!${NC}"
