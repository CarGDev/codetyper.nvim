---@mod codetyper.params.agent.confidence Parameters for confidence scoring
local M = {}

--- Heuristic weights (must sum to 1.0)
M.weights = {
	length = 0.15, -- Response length relative to prompt
	uncertainty = 0.30, -- Uncertainty phrases
	syntax = 0.25, -- Syntax completeness
	repetition = 0.15, -- Duplicate lines
	truncation = 0.15, -- Incomplete ending
}

--- Uncertainty phrases that indicate low confidence
M.uncertainty_phrases = {
	-- English
	"i'm not sure",
	"i am not sure",
	"maybe",
	"perhaps",
	"might work",
	"could work",
	"not certain",
	"uncertain",
	"i think",
	"possibly",
	"TODO",
	"FIXME",
	"XXX",
	"placeholder",
	"implement this",
	"fill in",
	"your code here",
	"...", -- Ellipsis as placeholder
	"# TODO",
	"// TODO",
	"-- TODO",
	"/* TODO",
}

return M
