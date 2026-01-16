---@meta
--- Brain Learning System Type Definitions
--- Optimized for LLM consumption with compact field names

local M = {}

---@alias NodeType "pat"|"cor"|"dec"|"con"|"fbk"|"ses"
-- pat = pattern, cor = correction, dec = decision
-- con = convention, fbk = feedback, ses = session

---@alias EdgeType "sem"|"file"|"temp"|"caus"|"sup"
-- sem = semantic, file = file-based, temp = temporal
-- caus = causal, sup = supersedes

---@alias DeltaOp "add"|"mod"|"del"

---@class NodeContent
---@field s string Summary (max 200 chars)
---@field d string Detail (full description)
---@field code? string Optional code snippet
---@field lang? string Language identifier

---@class NodeContext
---@field f? string File path (relative)
---@field fn? string Function name
---@field ln? number[] Line range [start, end]
---@field sym? string[] Symbol references

---@class NodeScores
---@field w number Weight (0-1)
---@field u number Usage count
---@field sr number Success rate (0-1)

---@class NodeTimestamps
---@field cr number Created (unix timestamp)
---@field up number Updated (unix timestamp)
---@field lu? number Last used (unix timestamp)

---@class NodeMeta
---@field src "auto"|"user"|"llm" Source of learning
---@field v number Version number
---@field dr? string[] Delta references

---@class Node
---@field id string Unique identifier (n_<timestamp>_<hash>)
---@field t NodeType Node type
---@field h string Content hash (8 chars)
---@field c NodeContent Content
---@field ctx NodeContext Context
---@field sc NodeScores Scores
---@field ts NodeTimestamps Timestamps
---@field m? NodeMeta Metadata

---@class EdgeProps
---@field w number Weight (0-1)
---@field dir "bi"|"fwd"|"bwd" Direction
---@field r? string Reason/description

---@class Edge
---@field id string Unique identifier (e_<source>_<target>)
---@field s string Source node ID
---@field t string Target node ID
---@field ty EdgeType Edge type
---@field p EdgeProps Properties
---@field ts number Created timestamp

---@class DeltaChange
---@field op DeltaOp Operation type
---@field path string JSON path (e.g., "nodes.pat.n_123")
---@field bh? string Before hash
---@field ah? string After hash
---@field diff? table Field-level diff

---@class DeltaMeta
---@field msg string Commit message
---@field trig string Trigger source
---@field sid? string Session ID

---@class Delta
---@field h string Hash (8 chars)
---@field p? string Parent hash
---@field ts number Timestamp
---@field ch DeltaChange[] Changes
---@field m DeltaMeta Metadata

---@class GraphMeta
---@field v number Schema version
---@field head? string Current HEAD delta hash
---@field nc number Node count
---@field ec number Edge count
---@field dc number Delta count

---@class AdjacencyEntry
---@field sem? string[] Semantic edges
---@field file? string[] File edges
---@field temp? string[] Temporal edges
---@field caus? string[] Causal edges
---@field sup? string[] Supersedes edges

---@class Graph
---@field meta GraphMeta Metadata
---@field adj table<string, AdjacencyEntry> Adjacency list
---@field radj table<string, AdjacencyEntry> Reverse adjacency

---@class QueryOpts
---@field query? string Text query
---@field file? string File path filter
---@field types? NodeType[] Node types to include
---@field since? number Timestamp filter
---@field limit? number Max results
---@field depth? number Traversal depth
---@field max_tokens? number Token budget

---@class QueryResult
---@field nodes Node[] Matched nodes
---@field edges Edge[] Related edges
---@field stats table Query statistics
---@field truncated boolean Whether results were truncated

---@class LLMContext
---@field schema string Schema version
---@field query string Original query
---@field learnings table[] Compact learning entries
---@field connections table[] Connection summaries
---@field tokens number Estimated token count

---@class LearnEvent
---@field type string Event type
---@field data table Event data
---@field file? string Related file
---@field timestamp number Event timestamp

---@class BrainConfig
---@field enabled boolean Enable brain system
---@field auto_learn boolean Auto-learn from events
---@field auto_commit boolean Auto-commit after threshold
---@field commit_threshold number Changes before auto-commit
---@field max_nodes number Max nodes before pruning
---@field max_deltas number Max delta history
---@field prune table Pruning config
---@field output table Output config

-- Type constants for runtime use
M.NODE_TYPES = {
  PATTERN = "pat",
  CORRECTION = "cor",
  DECISION = "dec",
  CONVENTION = "con",
  FEEDBACK = "fbk",
  SESSION = "ses",
}

M.EDGE_TYPES = {
  SEMANTIC = "sem",
  FILE = "file",
  TEMPORAL = "temp",
  CAUSAL = "caus",
  SUPERSEDES = "sup",
}

M.DELTA_OPS = {
  ADD = "add",
  MODIFY = "mod",
  DELETE = "del",
}

M.SOURCES = {
  AUTO = "auto",
  USER = "user",
  LLM = "llm",
}

M.SCHEMA_VERSION = 1

return M
