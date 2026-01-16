---@mod codetyper.params.agent.permissions Dangerous and safe command patterns
local M = {}

--- Dangerous command patterns that should never be auto-allowed
M.dangerous_patterns = {
	"^rm%s+%-rf",
	"^rm%s+%-r%s+/",
	"^rm%s+/",
	"^sudo%s+rm",
	"^chmod%s+777",
	"^chmod%s+%-R",
	"^chown%s+%-R",
	"^dd%s+",
	"^mkfs",
	"^fdisk",
	"^format",
	":.*>%s*/dev/",
	"^curl.*|.*sh",
	"^wget.*|.*sh",
	"^eval%s+",
	"`;.*`",
	"%$%(.*%)",
	"fork%s*bomb",
}

--- Safe command patterns that can be auto-allowed
M.safe_patterns = {
	"^ls%s",
	"^ls$",
	"^cat%s",
	"^head%s",
	"^tail%s",
	"^grep%s",
	"^find%s",
	"^pwd$",
	"^echo%s",
	"^wc%s",
	"^git%s+status",
	"^git%s+diff",
	"^git%s+log",
	"^git%s+show",
	"^git%s+branch",
	"^git%s+checkout",
	"^git%s+add", -- Generally safe if reviewing changes
}

return M
