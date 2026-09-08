--- Tests for constants/model_tiers.lua's get_tier() tag-stripped lookup.
--- Confirmed bug: any model name containing ":" fell through to the
--- final `model:match(":")` heuristic and was force-classified "basic",
--- even when the tagged model's stripped base name is a known chat/agent
--- model (e.g. the plugin's own default "gemma4:26b"). This must be fixed
--- so the static_tiers/model_caps lookup runs against the stripped name
--- BEFORE any default, and "basic" is never assigned purely because of ":".

local model_tiers = require("codetyper.constants.model_tiers")

describe("model_tiers.get_tier — tag-stripped lookup", function()
  it("resolves a tagged model via static_tiers using the stripped base name", function()
    -- static_tiers["llama3"] = "chat" (see constants/model_tiers.lua)
    assert.are.equal("chat", model_tiers.get_tier("llama3:8b"))
  end)

  it("does not default an unknown tagged model to basic purely because of the colon", function()
    -- "gemma4:26b" matches no entry in api_tiers/model_caps/static_tiers,
    -- stripped or raw — it must fall through to the same default an
    -- unknown untagged model gets ("chat"), never the old ":"-> "basic" heuristic.
    assert.are.equal("chat", model_tiers.get_tier("gemma4:26b"))
    -- Same unknown model, untagged, must produce the identical default —
    -- proving the tag itself has no special-cased effect on the result.
    assert.are.equal(model_tiers.get_tier("gemma4"), model_tiers.get_tier("gemma4:26b"))
  end)

  it("still classifies a known deepseek-coder tag as basic via static_tiers (not the colon heuristic)", function()
    -- static_tiers["deepseek-coder"] = "basic" — this must still return "basic",
    -- but because the STRIPPED NAME matched static_tiers, not because of ":".
    assert.are.equal("basic", model_tiers.get_tier("deepseek-coder:6.7b"))
  end)

  it("keeps model_caps-derived tier priority for a tagged model whose stripped base matches model_caps", function()
    -- model_caps has "gpt-4o" with tools = true -> "agent". The raw name's
    -- hyphen defeats normalize_model()'s own partial-match stripping (Lua
    -- pattern quirk: "-" is a magic lazy-quantifier char, not a literal),
    -- so BEFORE this fix "gpt-4o:latest" fell through to the colon
    -- heuristic and returned "basic" instead of "agent". This confirms the
    -- stripped-name lookup inside get_tier() itself is what fixes it, not
    -- normalize_model()'s own (unrelated, unfixed) stripping.
    assert.are.equal("agent", model_tiers.get_tier("gpt-4o:latest"))
  end)

  it("still returns basic for an untagged unknown model matching no tier data (regression guard)", function()
    assert.are.equal("chat", model_tiers.get_tier("totally-unknown-model"))
  end)
end)
