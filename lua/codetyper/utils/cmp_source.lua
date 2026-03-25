local source = {}

--- Create new cmp source instance
function source.new()
  return setmetatable({}, { __index = source })
end

--- Get source name
function source:get_keyword_pattern()
  return [[\k\+]]
end

--- Check if source is available
function source:is_available()
  return true
end

--- Get debug name
function source:get_debug_name()
  return "codetyper"
end

--- Get trigger characters
function source:get_trigger_characters()
  return { ".", ":", "_" }
end

return source
