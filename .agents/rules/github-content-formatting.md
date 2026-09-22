---
description: Format agent-authored GitHub issue/PR bodies and comments so CommonMark soft breaks do not collapse paragraphs and lists
alwaysApply: true
---

# GitHub content formatting (agent-authored)

Agent-authored issue bodies, PR descriptions, and PR/review comments must render
correctly on GitHub. CommonMark / GFM treats a **single** `\n` inside a block as a
soft break (no visible paragraph break). Assembling bodies as inline
`--body "line one\nline two"` (or joining strings with `\n` instead of `\n\n`)
produces run-on paragraphs and collapsed lists.

## Authoring

1. **Multi-paragraph or multi-line-list bodies:** write the body to a temp file,
   then post with `--body-file <path>`. Never assemble multi-line content as an
   inline `--body "..."` string with embedded `\n` escapes.
2. **Inline `--body` is only OK** for a genuinely single-line body (no lists,
   no headings, no code fences, no paragraph breaks).
3. **Blank lines:** separate paragraphs and list items with a blank line (`\n\n`).
   Put a blank line before and after fenced code blocks. Put a blank line before
   headings (except at the start of the file).

```bash
body="$(mktemp)"
cat >"$body" <<'EOF'
## Summary

- First item

- Second item

## Test plan

- [ ] Check rendering on GitHub
EOF
scripts/lint-github-markdown "$body"
gh pr edit <n> --body-file "$body"
rm -f "$body"
```

## Pre-flight

Before posting (or after drafting a body file), run:

```bash
scripts/lint-github-markdown <path>
```

The linter flags mid-line list markers, headings lacking a preceding blank line,
and fence markers that are not alone on their line. Fix findings before
`gh issue` / `gh pr` / `reply-thread` / `reply-comment`.

## Scope

Applies to issue bodies, PR descriptions, and PR/review comments or replies
posted by an agent — same “validate before it ships” principle as Conventional
Commits PR titles (see `.agents/rules/pr-ship-and-review.md`).
