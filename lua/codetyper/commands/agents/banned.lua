--- Banned commands for safety
M.BANNED_COMMANDS = {
	"rm -rf /",
	"rm -rf /*",
	"dd if=/dev/zero",
	"mkfs",
	":(){ :|:& };:",
	"> /dev/sda",
}

--- Banned patterns
M.BANNED_PATTERNS = {
	"curl.*|.*sh",
	"wget.*|.*sh",
	"rm%s+%-rf%s+/",
}

return M
