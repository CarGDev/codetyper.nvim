M.description = [[Makes a targeted edit to a file by replacing text.

The old_string should match the content you want to replace. The tool uses multiple
matching strategies with fallbacks:
1. Exact match
2. Whitespace-normalized match
3. Indentation-flexible match
4. Line-trimmed match
5. Fuzzy anchor-based match

For creating new files, use old_string="" and provide the full content in new_string.
For large changes, consider using 'write' tool instead.]]

return M
