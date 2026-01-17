local M = {}

M.description = [[Makes a targeted edit to a file by replacing a specific text block with new content.

CRITICAL: This tool replaces `old_string` with `new_string` in the file.

## How to use correctly:

1. **First READ the file** with the view tool to see exact content
2. **Copy the EXACT text** you want to replace into old_string (including whitespace/indentation)
3. **Provide the replacement** in new_string

## Examples:

### Example 1: Modify a function
If the file contains:
```
function greet() {
  return "Hello";
}
```

To change the return value, use:
- old_string: `function greet() {\n  return "Hello";\n}`
- new_string: `function greet() {\n  return "Hello World";\n}`

### Example 2: Add a class to an element
If the file contains:
```
<div>Hello World!</div>
```

To add a class, use:
- old_string: `<div>Hello World!</div>`
- new_string: `<div className="body">Hello World!</div>`

### Example 3: Add an import at top of file
If the file starts with:
```
import React from 'react';

function App() {
```

To add a new import, use:
- old_string: `import React from 'react';`
- new_string: `import React from 'react';\nimport './styles/global.css';`

## WARNINGS:
- NEVER use empty old_string unless creating a NEW file
- ALWAYS include enough context to make the match unique
- If old_string is not found, the edit FAILS (no changes made)
- The tool uses fuzzy matching for whitespace, but exact content matching

## Matching strategies (in order):
1. Exact match
2. Whitespace-normalized match
3. Indentation-flexible match
4. Line-trimmed match
5. Fuzzy anchor-based match (using first/last lines)]]

return M
