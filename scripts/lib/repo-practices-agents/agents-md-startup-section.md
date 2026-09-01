<!--
Snippet for the "session startup" section of a consumer's AGENTS.md. The
agent-bootstrap check requires AGENTS.md to instruct the agent to ALSO load the
`.cursor/rules/*.mdc` guidance — otherwise an agent that reads AGENTS.md (Cursor,
Copilot, or Claude Code via the CLAUDE.md @-import) still misses the rules,
because "load the rules" currently lives only inside a Cursor rule.

Add this to the repo's existing startup section (or create a `## Session startup`
section near the top of AGENTS.md). Keep the wording; the validator accepts
reasonable phrasing but requires a positive "read/load .cursor/rules" instruction
tied to session start.
-->

## Session startup

At the **start of every agent session**, before acting from assumed conventions:

1. Read this `AGENTS.md` in full.
2. Read every rule under `.cursor/rules/*.mdc` whose front matter has
   `alwaysApply: true`, plus any rule whose `globs` match files you will touch.
   `AGENTS.md` and the `.cursor/rules/` files together are the contract — neither
   alone is complete.

`CLAUDE.md` (a `@AGENTS.md` import) and `.github/copilot-instructions.md` exist so
Claude Code and Copilot reach this same guidance; do not put rules in them.
