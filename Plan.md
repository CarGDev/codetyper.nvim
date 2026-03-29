Refactor Plan — core/cost
=================================

Purpose
-------
- Move pure, testable cost logic out of `lua/codetyper/core/cost/init.lua` into small modules under `lua/codetyper/core/cost/`.
- Keep Neovim/UI code (buffers, windows, keymaps, highlights) in `init.lua`.
- Ensure all constants live under `lua/codetyper/constants/` and are consumed via `require` or passed into pure functions.

New modules to add
------------------
- `lua/codetyper/core/cost/calc.lua`
  - Pure functions: `calculate_cost(model, input_tokens, output_tokens, cached_tokens, normalize_model_fn, pricing_table)` and
    `calculate_savings(input_tokens, output_tokens, cached_tokens, comparison_model, normalize_model_fn, pricing_table)`.
  - No `vim` or `state` usage.

- `lua/codetyper/core/cost/aggregate.lua`
  - Pure function: `aggregate_usage(usage_list, is_free_fn, calculate_savings_fn)`.
  - Produces `stats` table with same shape as current implementation.

- `lua/codetyper/core/cost/format.lua`
  - Pure formatters: `format_cost(cost)`, `format_tokens(tokens)`, `format_duration(seconds)`.

- `lua/codetyper/core/cost/view.lua`
  - Pure renderer: `generate_model_breakdown(stats, pricing, normalize_model_fn, is_free_fn, formatters)`
  - Returns an array of string lines for a given `stats.by_model`.

Fixes required
--------------
- `lua/codetyper/core/cost/is_free_model.lua` currently references `normalize_model` and `free_models` but does not `require` them. Update it to either:
  - `local normalize_model = require("codetyper.handler.normalize_model")`
  - `local free_models = require("codetyper.constants.models").free_models`
  - Keep `pricing` from `require("codetyper.constants.prices")`.

Wiring (changes to `init.lua`)
-----------------------------
- Add requires at top of `init.lua`:
  - `local calc = require("codetyper.core.cost.calc")`
  - `local aggregate = require("codetyper.core.cost.aggregate")`
  - `local fmt = require("codetyper.core.cost.format")`
  - `local view = require("codetyper.core.cost.view")`

- Replace internal pure functions with adapters that call the new modules and pass in `normalize_model`, `M.pricing`, `comparison_model`, and `M.is_free_model`.
- Keep UI functions (window open/close, keymaps, highlights) in `init.lua`.
- Use `view.generate_model_breakdown(all_time_stats, M.pricing, normalize_model, M.is_free_model, fmt)` from `generate_content` to assemble per-model lines.

Constants rule
--------------
- All constants (models, prices, defaults) must remain under `lua/codetyper/constants/` and be referenced via `require("codetyper.constants.<name>")` or passed into pure modules from `init.lua`.

API shape / examples
--------------------
- `calc.calculate_cost(model, in_t, out_t, cached, normalize_model, pricing)` -> number
- `aggregate.aggregate_usage(usage_list, is_free_fn, calculate_savings_fn)` -> stats table
- `fmt.format_cost(number)` -> string
- `view.generate_model_breakdown(stats, pricing, normalize_model_fn, is_free_fn, formatters)` -> string[]

Migration steps
---------------
1. Fix `is_free_model.lua` `require`s (small, non-breaking change).
2. Add new modules: `calc.lua`, `aggregate.lua`, `format.lua`, `view.lua`.
3. Update `init.lua` to require the new modules and delegate pure logic to them.
4. Run quick manual verification in Neovim:
   - `:lua require("codetyper.core.cost").open()` — window should render and keymaps should work.

Notes
-----
- Keep the UI in `init.lua`; the new modules must not call `vim.*` or reference `state` directly.
- When formatting strings for display prefer using `fmt.format_*` inside `init.lua` so `view.lua` can either return raw numbers or formatted lines depending on the chosen contract. The README assumes `view.generate_model_breakdown` receives `formatters` and returns formatted strings.

