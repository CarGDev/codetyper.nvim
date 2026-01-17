# Intention

The migration should be approached as a controlled extraction of responsibility rather than a rewrite, and the guiding rule is that only *reasoning* moves while *reaction* stays. The agent is the primary migration target: everything in the current system that decides what to do, whether enough context exists, which files should change, or how to interpret ambiguous intent must be pulled out of Lua and rehomed into the agent process. This does not mean recreating the whole system elsewhere; it means collapsing scattered logic—intent classification, prompt shaping, plan construction, ambiguity detection, and output formatting—into a single, externally callable unit that accepts plain context and emits a structured plan or a structured request for more context. Lua’s role during this migration becomes thinner and more disciplined: it gathers the minimum context, forwards it, validates the response schema, and executes exactly what it is told. No heuristics survive on the Lua side. Any Lua code that currently “tries to help” by guessing intent or massaging patches should be deleted or turned into strict validation.

The chat system does not migrate in the sense of changing languages, but it must be conceptually downgraded. Today it likely participates in decision-making by shaping prompts and sometimes implicitly triggering execution. After migration, chat becomes a pure conversational adapter whose only job is to turn user dialogue into agent requests and display agent responses. It must never decide whether something is actionable, never choose tools, and never influence execution paths. In practice, this means stripping chat-related Lua code of any logic that branches into execution or patching and instead routing everything through the agent interface. The migration here is mostly subtractive: removing power, not adding complexity.

The tag detector remains entirely in Lua and should not be migrated at all, but it must be simplified and hardened. Its only responsibility post-migration is to detect syntactic triggers such as ``, extract the raw region, and provide precise buffer metadata. Any logic that tries to interpret what the tag “means” or whether it is valid must be removed. During migration, the detector becomes dumber but more reliable, acting as a sensor rather than a thinker. This is important because the agent can only be cleanly migrated if the detector never pre-filters or reshapes intent; otherwise, you end up duplicating logic across boundaries.

Autocompletion also stays in Lua, but migration here is about isolation rather than extraction. Autocompletion must be explicitly cut off from the agent path so it never blocks, never reasons, and never mutates state. If any current completion logic depends on agent internals, memory graphs, or intent inference, that dependency should be severed and replaced with cached, local, or heuristic-only data. The migration goal is to make autocompletion entirely reactive and disposable: fast suggestions in, no consequences out. This protects editor responsiveness and prevents the agent from being dragged into latency-sensitive paths.

Taken together, the migration is not language-driven but gravity-driven. The agent becomes heavier, slower, and more deliberate, and therefore moves out of Lua. Everything else becomes lighter, faster, and more mechanical, and therefore stays. If you execute this migration correctly, you will notice that large parts of the Lua codebase simply disappear or collapse into thin adapters, while the agent becomes easier to reason about, easier to test, and harder to misuse. That is how you know the split worked.

# New file structure

```
codetyper.nvim
├── doc
│   └── codetyper.txt
├── lua
│   └── codetyper
│       ├── adapters
│       │   ├── cli
│       │   └── nvim
│       │       ├── cmp
│       │       │   └── init.lua
│       │       ├── ui
│       │       │   ├── chat.lua
│       │       │   ├── context_modal.lua
│       │       │   ├── diff_review.lua
│       │       │   ├── logs.lua
│       │       │   ├── logs_panel.lua
│       │       │   └── switcher.lua
│       │       ├── autocmds.lua
│       │       ├── commands.lua
│       │       └── windows.lua
│       ├── completion
│       │   ├── inject.lua
│       │   ├── inline.lua
│       │   └── suggestion.lua
│       ├── detector
│       │   ├── inline_tags.lua
│       │   ├── ranges.lua
│       │   └── triggers.lua
│       ├── executor
│       │   ├── apply_plan.lua
│       │   ├── file_ops.lua
│       │   ├── write.lua
│       │   └── validate.lua
│       ├── scheduler
│       │   ├── queue.lua
│       │   ├── worker.lua
│       │   └── loop.lua
│       ├── transport
│       │   ├── agent_client.lua
│       │   └── protocol.lua
│       ├── support
│       │   ├── imports.lua
│       │   ├── tree.lua
│       │   └── utils.lua
│       ├── init.lua
│       └── types.lua
├── agent
│   ├── __init__.py
│   ├── main.py
│   ├── protocol.py
│   ├── schemas.py
│   ├── intent.py
│   ├── planner.py
│   ├── context.py
│   ├── validator.py
│   ├── formatter.py
│   ├── memory
│   │   ├── __init__.py
│   │   ├── graph.py
│   │   ├── learners.py
│   │   └── storage.py
│   └── prompts
│       ├── __init__.py
│       ├── edit.py
│       ├── intent.py
│       └── system.py
├── plugin
│   └── codetyper.lua
├── tests
│   ├── lua
│   └── agent
│       ├── test_intent.py
│       ├── test_planner.py
│       ├── test_validator.py
│       └── test_protocol.py
├── AGENT_SYSTEM.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── Makefile
├── README.md
└── llms.txt
```
