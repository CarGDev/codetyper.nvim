local state = {
  buf = nil,
  win = nil,
  original_event = nil,
  callback = nil,
  llm_response = nil,
  attached_files = nil,
  entries = {},
  current_index = 1,
  list_buf = nil,
  list_win = nil,
  diff_buf = nil,
  diff_win = nil,
  is_open = false,
}

return state
