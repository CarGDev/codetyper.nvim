---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/features/agents/inline.lua

describe("inline_agent", function()
	local inline_agent = require("codetyper.features.agents.inline")

	describe("should_use_agent", function()
		describe("file creation patterns", function()
			it("should detect 'create file' pattern", function()
				local result = inline_agent.should_use_agent("create a new file for utilities")
				assert.is_true(result)
			end)

			it("should detect 'add file' pattern", function()
				local result = inline_agent.should_use_agent("add a file for constants")
				assert.is_true(result)
			end)

			it("should detect 'new file' pattern", function()
				local result = inline_agent.should_use_agent("I need a new file for the API client")
				assert.is_true(result)
			end)
		end)

		describe("import patterns", function()
			it("should detect 'import from' pattern", function()
				local result = inline_agent.should_use_agent("import the utils from shared module")
				assert.is_true(result)
			end)

			it("should detect 'add import' pattern", function()
				local result = inline_agent.should_use_agent("add import for React hooks")
				assert.is_true(result)
			end)
		end)

		describe("style patterns", function()
			it("should detect 'create style' pattern", function()
				local result = inline_agent.should_use_agent("create a style for the button")
				assert.is_true(result)
			end)

			it("should detect 'add style' pattern", function()
				local result = inline_agent.should_use_agent("add style for dark mode")
				assert.is_true(result)
			end)

			it("should detect 'add css' pattern", function()
				local result = inline_agent.should_use_agent("add css for the header component")
				assert.is_true(result)
			end)
		end)

		describe("file reference patterns", function()
			it("should detect @path file references", function()
				local result = inline_agent.should_use_agent("update the component and also modify @src/styles/global.css")
				assert.is_true(result)
			end)

			it("should detect nested path references", function()
				local result = inline_agent.should_use_agent("add styling from @components/Button/styles.scss")
				assert.is_true(result)
			end)
		end)

		describe("multi-operation patterns", function()
			it("should detect 'update and create' pattern", function()
				local result = inline_agent.should_use_agent("update the component and create a new test file")
				assert.is_true(result)
			end)

			it("should detect 'modify and add' pattern", function()
				local result = inline_agent.should_use_agent("modify this function and add documentation")
				assert.is_true(result)
			end)

			it("should detect 'refactor completely' pattern", function()
				local result = inline_agent.should_use_agent("refactor this module completely")
				assert.is_true(result)
			end)
		end)

		describe("code with instructions", function()
			it("should detect code + add instruction", function()
				local prompt = [[
Add error handling to this function:
function fetchData() {
  return fetch(url)
}
]]
				local result = inline_agent.should_use_agent(prompt)
				assert.is_true(result)
			end)

			it("should detect code + create instruction", function()
				local prompt = [[
Create a new version with TypeScript:
const add = (a, b) => a + b
export default add
]]
				local result = inline_agent.should_use_agent(prompt)
				assert.is_true(result)
			end)

			it("should detect code + update instruction", function()
				local prompt = [[
Update this class to use async/await:
class Api {
  def fetch(self):
    return requests.get(url)
}
]]
				local result = inline_agent.should_use_agent(prompt)
				assert.is_true(result)
			end)
		end)

		describe("simple edits (should return false)", function()
			it("should return false for simple fix", function()
				local result = inline_agent.should_use_agent("fix the typo")
				assert.is_false(result)
			end)

			it("should return false for simple rename", function()
				local result = inline_agent.should_use_agent("rename this variable to count")
				assert.is_false(result)
			end)

			it("should return false for simple question", function()
				local result = inline_agent.should_use_agent("what does this function do?")
				assert.is_false(result)
			end)

			it("should return false for simple documentation", function()
				local result = inline_agent.should_use_agent("document this method")
				assert.is_false(result)
			end)
		end)

		describe("edge cases", function()
			it("should handle empty string", function()
				local result = inline_agent.should_use_agent("")
				assert.is_false(result)
			end)

			it("should handle case insensitivity", function()
				local result = inline_agent.should_use_agent("CREATE A NEW FILE for components")
				assert.is_true(result)
			end)

			it("should handle mixed case", function()
				local result = inline_agent.should_use_agent("Add Import for the logger module")
				assert.is_true(result)
			end)
		end)

		describe("real-world examples", function()
			it("should detect the CSS + import example", function()
				local prompt = [[
I need to create a class name body on the div element and then add also the style on @src/styles/global.css
and import it with red color text.
function App() {
  return <div>Hello World!</div>;
}
export default App;
]]
				local result = inline_agent.should_use_agent(prompt)
				assert.is_true(result)
			end)

			it("should detect boyd class example with file reference", function()
				local prompt = [[
I need to create a class name boyd on the div element and then add also the style on @src/styles/global.css
and import it
with red color text.
]]
				local result = inline_agent.should_use_agent(prompt)
				assert.is_true(result)
			end)

			it("should detect component extraction example", function()
				local prompt = [[
Extract this into a separate component file @src/components/Header.tsx
and import it here:
<header className="main-header">
  <nav>...</nav>
</header>
]]
				local result = inline_agent.should_use_agent(prompt)
				assert.is_true(result)
			end)

			it("should detect module creation example", function()
				local prompt = [[
Create a new utility module with these functions and export from @utils/index.ts:
- formatDate
- parseDate
- isValidDate
]]
				local result = inline_agent.should_use_agent(prompt)
				assert.is_true(result)
			end)
		end)
	end)
end)
