local M = {}

M.description = [[Reads the content of a file.

Usage notes:
- Provide the file path relative to the project root
- Use start_line and end_line to read specific sections
- If content is truncated, use line ranges to read in chunks
- Returns JSON with content, total_line_count, and is_truncated]]

return M