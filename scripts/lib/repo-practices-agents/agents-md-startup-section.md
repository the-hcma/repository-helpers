<!--
Snippet for the "session startup" section of a consumer's AGENTS.md. The
agent-bootstrap check requires AGENTS.md to instruct the agent to ALSO load the
`.agents/rules/*.md` guidance — otherwise an agent that reads AGENTS.md (Cursor,
Copilot, or Claude Code via the CLAUDE.md @-import) still misses the rules.

Add this to the repo's existing startup section (or create a `## Session startup`
section near the top of AGENTS.md). Keep the wording; the validator accepts
equivalent phrasing but requires a positive "read/load .agents/rules" instruction
tied to session start. `.cursor/rules/*.mdc` are Cursor injection shims only.
-->

## Session startup

At the **start of every agent session**, before acting from assumed conventions:

1. Read this `AGENTS.md` in full.
2. Read every rule under `.agents/rules/*.md` whose front matter has
   `alwaysApply: true`, plus any rule whose `globs` match files you will touch.
   `AGENTS.md` and the `.agents/rules/` files together are the contract — neither
   alone is complete. `.cursor/rules/*.mdc` files are Cursor injection shims only
   (frontmatter + pointer); do not treat the shim body as the rule.

`CLAUDE.md` (a `@AGENTS.md` import) and `.github/copilot-instructions.md` exist so
Claude Code and Copilot reach this same guidance; do not put rules in them.
