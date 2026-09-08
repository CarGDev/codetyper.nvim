.PHONY: test test-file lint format clean help docs check-deps

help:
	@echo "Codetyper.nvim — Available targets:"
	@echo ""
	@echo "  make test           Run functional test suite (plenary.busted)"
	@echo "  make test-file FILE=tests/spec/foo_spec.lua   Run a single spec file"
	@echo "  make lint           Run luacheck linter"
	@echo "  make format         Format code with stylua"
	@echo "  make docs           Generate help tags"
	@echo "  make clean          Clean generated files"
	@echo "  make check-deps     Check development dependencies"

test:
	@nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/spec/ {minimal_init = 'tests/minimal_init.lua'}"

test-file:
	@nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedFile $(FILE)"

lint:
	@if command -v luacheck &> /dev/null; then \
		luacheck lua/ plugin/; \
	else \
		echo "luacheck not installed. Install with: luarocks install luacheck"; \
		exit 1; \
	fi

format:
	@if command -v stylua &> /dev/null; then \
		stylua lua/ plugin/; \
	else \
		echo "stylua not installed. Install from: https://github.com/JohnnyMorganz/StyLua"; \
		exit 1; \
	fi

format-check:
	@if command -v stylua &> /dev/null; then \
		stylua --check lua/ plugin/; \
	else \
		echo "stylua not installed."; \
		exit 1; \
	fi

docs:
	@nvim --headless -c "helptags doc/" -c "qa" 2>/dev/null && \
		echo "Help tags generated." || \
		echo "Failed to generate help tags."

clean:
	@rm -rf .luacache/
	@find . -name "*.orig" -delete
	@echo "Cleaned generated files."

check-deps:
	@echo "Checking development dependencies..."
	@echo ""
	@if nvim --version &> /dev/null; then \
		echo "  [ok] Neovim $$(nvim --version | head -1)"; \
	else \
		echo "  [!!] Neovim not found"; \
	fi
	@if command -v luacheck &> /dev/null; then \
		echo "  [ok] luacheck"; \
	else \
		echo "  [--] luacheck (optional: luarocks install luacheck)"; \
	fi
	@if command -v stylua &> /dev/null; then \
		echo "  [ok] stylua"; \
	else \
		echo "  [--] stylua (optional: cargo install stylua)"; \
	fi
	@if command -v curl &> /dev/null; then \
		echo "  [ok] curl"; \
	else \
		echo "  [!!] curl not found (required for API calls)"; \
	fi
