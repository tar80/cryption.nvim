ifneq ($(wildcard .env),)
    include .env
    export
endif

STYLUA_PATH  ?= stylua
PLENARY_PATH ?= $(HOME)/.local/share/nvim/lazy/plenary.nvim
TEST_INIT    ?= tests/_min_init.lua
LEMMY_HELP   ?= lemmy-help
LUA_ENTRY    ?= lua/cryption/_meta/doc.lua
DOC_OUTPUT   ?= doc/cryption.txt

.PHONY: all lint test doc

all:
	@status=0; \
	$(MAKE) lint || status=1; \
	$(MAKE) test || status=1; \
	exit $$status

lint:
	@echo "--- Running StyLua Check ---"
	@if [ "$(CI)" != "true" ] && [ ! -x "$(STYLUA_PATH)" ]; then \
		echo "Error: stylua not found at $(STYLUA_PATH)"; \
		exit 1; \
	fi
	"$(STYLUA_PATH)" --check lua/

test:
	@echo "--- Running Tests ---"
	@if [ ! -d "$(PLENARY_PATH)" ]; then \
		echo "Error: plenary.nvim not found at $(PLENARY_PATH)"; \
		exit 1; \
	fi
	nvim --headless \
		--cmd "set rtp+=$(PLENARY_PATH)" \
		--cmd "lua vim.opt.rtp:append(vim.fn.getcwd())" \
		-u $(TEST_INIT) \
		-c "lua require('plenary.test_harness').test_directory('tests/', {timeout = 30000})" \
		-c "qa!"

doc:
	@echo "--- Generating vimdoc ---"
	@if [ "$(CI)" != "true" ] && ! command -v "$(LEMMY_HELP)" > /dev/null 2>&1; then \
		echo "Error: lemmy-help not found at $(LEMMY_HELP)"; \
		exit 1; \
	fi
	@mkdir -p $(dir $(DOC_OUTPUT))
	"$(LEMMY_HELP)" --layout=compact $(LUA_ENTRY) > $(DOC_OUTPUT)
	@echo "Generated: $(DOC_OUTPUT)"
