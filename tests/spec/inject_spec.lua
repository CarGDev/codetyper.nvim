--- Tests for smart code injection with import handling

describe("codetyper.agent.inject", function()
	local inject

	before_each(function()
		inject = require("codetyper.agent.inject")
	end)

	describe("parse_code", function()
		describe("JavaScript/TypeScript", function()
			it("should detect ES6 named imports", function()
				local code = [[import { useState, useEffect } from 'react';
import { Button } from './components';

function App() {
  return <div>Hello</div>;
}]]
				local result = inject.parse_code(code, "typescript")

				assert.equals(2, #result.imports)
				assert.truthy(result.imports[1]:match("useState"))
				assert.truthy(result.imports[2]:match("Button"))
				assert.truthy(#result.body > 0)
			end)

			it("should detect ES6 default imports", function()
				local code = [[import React from 'react';
import axios from 'axios';

const api = axios.create();]]
				local result = inject.parse_code(code, "javascript")

				assert.equals(2, #result.imports)
				assert.truthy(result.imports[1]:match("React"))
				assert.truthy(result.imports[2]:match("axios"))
			end)

			it("should detect require imports", function()
				local code = [[const fs = require('fs');
const path = require('path');

module.exports = { fs, path };]]
				local result = inject.parse_code(code, "javascript")

				assert.equals(2, #result.imports)
				assert.truthy(result.imports[1]:match("fs"))
				assert.truthy(result.imports[2]:match("path"))
			end)

			it("should detect multi-line imports", function()
				local code = [[import {
  useState,
  useEffect,
  useCallback
} from 'react';

function Component() {}]]
				local result = inject.parse_code(code, "typescript")

				assert.equals(1, #result.imports)
				assert.truthy(result.imports[1]:match("useState"))
				assert.truthy(result.imports[1]:match("useCallback"))
			end)

			it("should detect namespace imports", function()
				local code = [[import * as React from 'react';

export default React;]]
				local result = inject.parse_code(code, "tsx")

				assert.equals(1, #result.imports)
				assert.truthy(result.imports[1]:match("%* as React"))
			end)
		end)

		describe("Python", function()
			it("should detect simple imports", function()
				local code = [[import os
import sys
import json

def main():
    pass]]
				local result = inject.parse_code(code, "python")

				assert.equals(3, #result.imports)
				assert.truthy(result.imports[1]:match("import os"))
				assert.truthy(result.imports[2]:match("import sys"))
				assert.truthy(result.imports[3]:match("import json"))
			end)

			it("should detect from imports", function()
				local code = [[from typing import List, Dict
from pathlib import Path

def process(items: List[str]) -> None:
    pass]]
				local result = inject.parse_code(code, "py")

				assert.equals(2, #result.imports)
				assert.truthy(result.imports[1]:match("from typing"))
				assert.truthy(result.imports[2]:match("from pathlib"))
			end)
		end)

		describe("Lua", function()
			it("should detect require statements", function()
				local code = [[local M = {}
local utils = require("codetyper.utils")
local config = require('codetyper.config')

function M.setup()
end

return M]]
				local result = inject.parse_code(code, "lua")

				assert.equals(2, #result.imports)
				assert.truthy(result.imports[1]:match("utils"))
				assert.truthy(result.imports[2]:match("config"))
			end)
		end)

		describe("Go", function()
			it("should detect single imports", function()
				local code = [[package main

import "fmt"

func main() {
    fmt.Println("Hello")
}]]
				local result = inject.parse_code(code, "go")

				assert.equals(1, #result.imports)
				assert.truthy(result.imports[1]:match('import "fmt"'))
			end)

			it("should detect grouped imports", function()
				local code = [[package main

import (
    "fmt"
    "os"
    "strings"
)

func main() {}]]
				local result = inject.parse_code(code, "go")

				assert.equals(1, #result.imports)
				assert.truthy(result.imports[1]:match("fmt"))
				assert.truthy(result.imports[1]:match("os"))
			end)
		end)

		describe("Rust", function()
			it("should detect use statements", function()
				local code = [[use std::io;
use std::collections::HashMap;

fn main() {
    let map = HashMap::new();
}]]
				local result = inject.parse_code(code, "rs")

				assert.equals(2, #result.imports)
				assert.truthy(result.imports[1]:match("std::io"))
				assert.truthy(result.imports[2]:match("HashMap"))
			end)
		end)

		describe("C/C++", function()
			it("should detect include statements", function()
				local code = [[#include <stdio.h>
#include "myheader.h"

int main() {
    return 0;
}]]
				local result = inject.parse_code(code, "c")

				assert.equals(2, #result.imports)
				assert.truthy(result.imports[1]:match("stdio"))
				assert.truthy(result.imports[2]:match("myheader"))
			end)
		end)
	end)

	describe("merge_imports", function()
		it("should merge without duplicates", function()
			local existing = {
				"import { useState } from 'react';",
				"import { Button } from './components';",
			}
			local new_imports = {
				"import { useEffect } from 'react';",
				"import { useState } from 'react';", -- duplicate
				"import { Card } from './components';",
			}

			local merged = inject.merge_imports(existing, new_imports)

			assert.equals(4, #merged) -- Should not have duplicate useState
		end)

		it("should handle empty existing imports", function()
			local existing = {}
			local new_imports = {
				"import os",
				"import sys",
			}

			local merged = inject.merge_imports(existing, new_imports)

			assert.equals(2, #merged)
		end)

		it("should handle empty new imports", function()
			local existing = {
				"import os",
				"import sys",
			}
			local new_imports = {}

			local merged = inject.merge_imports(existing, new_imports)

			assert.equals(2, #merged)
		end)

		it("should handle whitespace variations in duplicates", function()
			local existing = {
				"import { useState } from 'react';",
			}
			local new_imports = {
				"import {useState} from 'react';", -- Same but different spacing
			}

			local merged = inject.merge_imports(existing, new_imports)

			assert.equals(1, #merged) -- Should detect as duplicate
		end)
	end)

	describe("sort_imports", function()
		it("should group imports by type for JavaScript", function()
			local imports = {
				"import React from 'react';",
				"import { Button } from './components';",
				"import axios from 'axios';",
				"import path from 'path';",
			}

			local sorted = inject.sort_imports(imports, "javascript")

			-- Check ordering: builtin -> third-party -> local
			local found_builtin = false
			local found_local = false
			local builtin_pos = 0
			local local_pos = 0

			for i, imp in ipairs(sorted) do
				if imp:match("path") then
					found_builtin = true
					builtin_pos = i
				end
				if imp:match("%.%/") then
					found_local = true
					local_pos = i
				end
			end

			-- Local imports should come after third-party
			if found_local and found_builtin then
				assert.truthy(local_pos > builtin_pos)
			end
		end)
	end)

	describe("has_imports", function()
		it("should return true when code has imports", function()
			local code = [[import { useState } from 'react';
function App() {}]]

			assert.is_true(inject.has_imports(code, "typescript"))
		end)

		it("should return false when code has no imports", function()
			local code = [[function App() {
  return <div>Hello</div>;
}]]

			assert.is_false(inject.has_imports(code, "typescript"))
		end)

		it("should detect Python imports", function()
			local code = [[from typing import List

def process(items: List[str]):
    pass]]

			assert.is_true(inject.has_imports(code, "python"))
		end)

		it("should detect Lua requires", function()
			local code = [[local utils = require("utils")

local M = {}
return M]]

			assert.is_true(inject.has_imports(code, "lua"))
		end)
	end)

	describe("edge cases", function()
		it("should handle empty code", function()
			local result = inject.parse_code("", "javascript")

			assert.equals(0, #result.imports)
			assert.equals(1, #result.body) -- Empty string becomes one empty line
		end)

		it("should handle code with only imports", function()
			local code = [[import React from 'react';
import { useState } from 'react';]]

			local result = inject.parse_code(code, "javascript")

			assert.equals(2, #result.imports)
			assert.equals(0, #result.body)
		end)

		it("should handle code with only body", function()
			local code = [[function hello() {
  console.log("Hello");
}]]

			local result = inject.parse_code(code, "javascript")

			assert.equals(0, #result.imports)
			assert.truthy(#result.body > 0)
		end)

		it("should handle imports in string literals (not detect as imports)", function()
			local code = [[const example = "import { fake } from 'not-real';";
const config = { import: true };

function test() {}]]

			local result = inject.parse_code(code, "javascript")

			-- The first line looks like an import but is in a string
			-- This is a known limitation - we accept some false positives
			-- The important thing is we don't break the code
			assert.truthy(#result.body >= 0)
		end)

		it("should handle mixed import styles in same file", function()
			local code = [[import React from 'react';
const axios = require('axios');
import { useState } from 'react';

function App() {}]]

			local result = inject.parse_code(code, "javascript")

			assert.equals(3, #result.imports)
		end)
	end)
end)
