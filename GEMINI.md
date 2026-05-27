# GEMINI.md

Foundational technical and architectural mandates for this user.

## Technical Mandates

- **Test-Driven Fixes**: Always include a regression test when fixing a bug.
- **Explicit over Implicit**: Favor explicit code structures and clear naming over "clever" or implicit patterns.
- **Structural Integrity**: When refactoring, prioritize maintaining the existing architectural patterns of the project.
- **Type Safety**: In typed languages (e.g., TypeScript, Go, Rust), maintain strict type safety and avoid `any` or similar escapes unless absolutely necessary.
- **Documentation**: All new architectural decisions must be documented in a relevant `README.md` or a dedicated architecture log.
- **Project Manuals**:
    - Vibe-Trading: `/home/kmaths/Manual-Vibe-Trading.md`

## Shared Memory (agentmemory)

- **Cross-Agent Persistence**: This workspace uses `agentmemory` to share context, facts, and patterns across different agents (Gemini CLI, Hermes).
- **Tool Usage**: Use the `agentmemory` MCP tools (e.g., `memory_save`, `memory_recall`, `memory_smart_search`) to persist and retrieve important insights.
- **Note**: In Hermes, these tools are prefixed as `mcp_agentmemory_*`.
- **Privacy**: The memory server automatically filters secrets and API keys.
- **Observability**: The memory viewer is available at `http://localhost:3113`.

## Architectural Mandates

- **Composition over Inheritance**: Prefer composition and delegation to build complex behavior.
- **Clean Layers**: Maintain clear separation between business logic, data access, and presentation layers.
- **Minimal Dependencies**: Be cautious when adding new external dependencies; evaluate if the functionality can be implemented simply within the project.

---

## Superpowers Skill Framework (Default Active)

The Superpowers skill framework is **always active** for all software design and coding tasks. It provides disciplined workflows for brainstorming, planning, implementation, debugging, and verification.

**Source**: `/home/kmaths/.gemini/extensions/superpowers/skills/`

### Instruction Priority

1. **User's explicit instructions** (this GEMINI.md, AGENTS.md, direct requests) — highest priority
2. **Superpowers skills** — override default system behavior where they conflict
3. **Default system prompt** — lowest priority

### Antigravity IDE Tool Mapping

Skills use Claude Code tool names. In Antigravity IDE, use these equivalents:

| Skill references | Antigravity IDE equivalent |
|-----------------|----------------------|
| `Read` (file reading) | `view_file` |
| `Write` (file creation) | `write_to_file` |
| `Edit` (file editing) | `replace_file_content` / `multi_replace_file_content` |
| `Bash` (run commands) | `run_command` |
| `Grep` (search file content) | `grep_search` |
| `Glob` (search files by name) | `list_dir` |
| `TodoWrite` (task tracking) | Create/update `task.md` artifact |
| `Skill` tool (invoke a skill) | `view_file` with `IsSkillFile=true` on the skill's `SKILL.md` |
| `WebSearch` | `search_web` |
| `WebFetch` | `read_url_content` |
| `Task` tool (dispatch subagent) | `browser_subagent` (for browser tasks) |

### The Rule: Check Skills Before Any Action

**Before responding to ANY coding or design task, check if a superpowers skill applies.** Even a 1% chance means you should load and follow the skill.

### Skill Catalog

Load the relevant SKILL.md file (using `view_file` with `IsSkillFile=true`) when the trigger condition matches:

| Skill | Trigger | Path |
|-------|---------|------|
| **Brainstorming** | Creating features, building components, adding functionality, modifying behavior | `~/.gemini/extensions/superpowers/skills/brainstorming/SKILL.md` |
| **Writing Plans** | Have a spec/requirements for a multi-step task, before writing code | `~/.gemini/extensions/superpowers/skills/writing-plans/SKILL.md` |
| **Executing Plans** | Have a written implementation plan to execute | `~/.gemini/extensions/superpowers/skills/executing-plans/SKILL.md` |
| **Test-Driven Development** | Implementing any feature or bugfix, before writing implementation code | `~/.gemini/extensions/superpowers/skills/test-driven-development/SKILL.md` |
| **Systematic Debugging** | Any bug, test failure, unexpected behavior — before proposing fixes | `~/.gemini/extensions/superpowers/skills/systematic-debugging/SKILL.md` |
| **Verification Before Completion** | About to claim work is complete, fixed, or passing | `~/.gemini/extensions/superpowers/skills/verification-before-completion/SKILL.md` |
| **Receiving Code Review** | Receiving code review feedback, before implementing suggestions | `~/.gemini/extensions/superpowers/skills/receiving-code-review/SKILL.md` |
| **Finishing a Branch** | Implementation complete, deciding how to integrate work | `~/.gemini/extensions/superpowers/skills/finishing-a-development-branch/SKILL.md` |
| **Writing Skills** | Creating new reusable skills | `~/.gemini/extensions/superpowers/skills/writing-skills/SKILL.md` |

### Skill Priority Order

When multiple skills could apply:
1. **Process skills first** (brainstorming, debugging) — determine HOW to approach
2. **Implementation skills second** (TDD, executing-plans) — guide execution

- "Let's build X" → brainstorming first, then writing-plans, then implementation
- "Fix this bug" → systematic-debugging first, then TDD for the fix

### Core Principles (Always Active)

These principles from the superpowers framework apply to ALL coding work, even when not explicitly loading a skill file:

#### No Fixes Without Root Cause
- Random fixes waste time. Always trace to root cause before attempting fixes.
- If 3+ fixes fail, question the architecture — don't attempt fix #4.

#### No Production Code Without Failing Test First
- Write the test. Watch it fail. Write minimal code to pass. Refactor.
- Tests written after code pass immediately and prove nothing.

#### No Completion Claims Without Fresh Verification
- Run the command. Read the output. THEN claim the result.
- Never use "should work", "probably passes", or "seems correct".

#### Design Before Implementation
- Every feature gets a design, even "simple" ones. The design can be short, but it must exist.
- Propose 2-3 approaches with trade-offs before settling.

#### YAGNI Ruthlessly
- Remove unnecessary features from all designs.
- Don't add options, configurability, or abstractions that aren't needed now.

### Red Flags — STOP and Follow Process

If you catch yourself thinking any of these, STOP:

| Thought | Reality |
|---------|---------|
| "This is too simple to need a design" | Simple projects have unexamined assumptions |
| "Quick fix for now, investigate later" | You're skipping root cause analysis |
| "I'll write tests after" | Tests-after prove nothing |
| "Should work now" | Run the verification command |
| "Just try changing X and see" | Form a hypothesis first |
| "One more fix attempt" (after 2+ failures) | Question the architecture |

---

## Project Status (2026-05-18)

- **Hermes Agent**: Setup complete. Lali persona active.
- **NVIDIA Integration**: Configured with native `nvidia` provider using DeepSeek-V4-Pro. API key stored in `~/.hermes/.env`.
- **Enterprise Time Logger**: Production-stable. All 17/17 tests passing. Pushed to GitHub.
- **Vibe-Trading**: Active with rate-limit retry logic in `chat.py`.
