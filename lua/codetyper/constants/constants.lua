local M = {}

M.throb_time = 1200
M.cooldown_time = 100
M.tick_time = 100
M.Throbber = {}
M.AUGROUP = "Codetyper"
M.tree_update_timer = nil
M.TREE_UPDATE_DEBOUNCE_MS = 1000 -- 1 second debounce
M.processed_prompts = {}
M.asking_preference = false
M.is_processing = false
M.previous_mode = "n"
M.prompt_process_timer = nil
M.PROMPT_PROCESS_DEBOUNCE_MS = 200 -- Wait 200ms after mode change before processing
M.hl_group = "CmpGhostText"
M.throb_icons = {
  { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  { "◐", "◓", "◑", "◒" },
  { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
}
M.save_timer = nil

return M
