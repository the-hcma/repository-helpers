---
description: Format agent-authored GitHub issue/PR bodies, comments and committed Markdown files so they render correctly (blank lines + no hand-wrapped paragraphs)
alwaysApply: true
---

# GitHub content formatting (agent-authored)

Agent-authored issue bodies, PR descriptions, and PR/review comments must render
correctly on GitHub.

Three failure modes show up here:

1. **Missing blank lines / literal `\n` escapes** — assembling bodies as inline
   `--body "line one\nline two"` (or joining with a single `\n` instead of `\n\n`)
   collapses lists and paragraphs in CommonMark-ish ways, and embeds literal
   backslash-n text when the shell does not expand escapes.
2. **Hand-wrapped paragraphs** — wrapping a paragraph across several short
   physical lines with a lone newline between them. GitHub’s **issue/PR/comment**
   renderer treats that lone `\n` as a **visible hard break** (unlike the
   file/blob renderer’s soft-break-as-space). The body looks like a column of
   disconnected short lines. Prefer one long line per paragraph, or separate
   paragraphs with a blank line.
3. **Unlinked closing keywords** — writing a closing intent as natural prose
   (`"This closes that gap (#651's remaining scope…)"`) instead of GitHub's
   required adjacent form. GitHub only auto-links/closes an issue when a
   keyword (`close(s|d)`, `fix(es|ed)`, `resolve(s|d)`) sits **immediately**
   next to the reference — `Fixes #651.` — with nothing else in between,
   including a stray word like "in" (`Fixed in #651` does **not** link).
   GitHub also requires its own keyword before **each** reference: `Fixes
   #651, #652.` only closes #651 — write `Fixes #651, fixes #652.` to close
   both. This only closes an issue from a **PR description targeting the
   default branch, or a commit message** — the same phrasing in an issue body
   is just a reference, not a closing action. When a PR description is meant
   to close another issue, write it as its own sentence: `Fixes #651.` /
   `Closes #651.` (repository-helpers#660).

## Authoring

1. **Multi-paragraph or multi-line-list bodies:** write the body to a temp file,
   then post with `--body-file <path>`. Never assemble multi-line content as an
   inline `--body "..."` string with embedded `\n` escapes.
2. **Inline `--body` is only OK** for a genuinely single-line body (no lists,
   no headings, no code fences, no paragraph breaks, no hand-wraps).
3. **Blank lines:** separate paragraphs and list items with a blank line (`\n\n`).
   Put a blank line before and after fenced code blocks. Put a blank line before
   headings (except at the start of the file).
4. **Paragraphs:** do not hard-wrap prose for column width. One physical line per
   paragraph (or blank-line-separated paragraphs).

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
# Issues: prefer the linting wrapper
scripts/gh-issue create --title 'feat: example' --body-file "$body"
# Or PR body:
# scripts/gh-api pr edit <n> --body-file "$body"
rm -f "$body"
```

## Pre-flight

Before posting (or after drafting a body file), run:

```bash
scripts/lint-github-markdown <path>
```

For **issues**, use `scripts/gh-issue create|edit …` so the lint runs before the
API call. For PR bodies / review replies, lint then `scripts/gh-api pr edit`
or `reply-thread` / `reply-comment`.

The linter flags mid-line list markers, headings lacking a preceding blank line,
fence markers that are not alone on their line, literal `\n` escapes outside
fences, consecutive prose lines (hand-wrapped paragraphs), and a closing
keyword that is near an issue reference but not immediately adjacent to it.
Fix findings before posting.

## Committed Markdown files

The no-hand-wrap rule also covers every `.md` file committed to a repository: `AGENTS.md`, `README.md`, `docs/`, `.agents/rules/`, skills and templates. GitHub's file renderer turns a lone newline into a space, so wrapped source looks fine there, but it makes diffs noisy, and templates copied from repository-helpers carry the wraps into every consumer repo (repository-helpers#671).

1. **No hard line breaks:** write one physical line per paragraph, list item and blockquote, however long it gets.
2. **Blank lines:** put a blank line between paragraphs, and before and after headings, lists, fenced code blocks and tables.
3. **Leave structure alone:** YAML front matter, code blocks, tables, headings and HTML keep their own lines. So do breadcrumb comments and bare canonical URL lines, which repo-practices checks look for line by line.

Check a file, or unwrap it in place, before committing:

```bash
scripts/lint-github-markdown --repo-files <file.md>…
scripts/lint-github-markdown --repo-files --fix <file.md>…
```

`--repo-files` flags only hard line breaks inside a paragraph, list item or blockquote. It skips front matter, code, tables, headings and HTML, and the body-only checks above do not apply.

## Scope

Applies to issue bodies, PR descriptions, and PR/review comments or replies
posted by an agent — same “validate before it ships” principle as Conventional
Commits PR titles (see `.agents/rules/pr-ship-and-review.md`) — and to Markdown files committed to a repository (see above).

<!-- github-content-formatting-canonical: https://github.com/the-hcma/repository-helpers/blob/main/.agents/rules/github-content-formatting.md -->
Canonical rule: https://github.com/the-hcma/repository-helpers/blob/main/.agents/rules/github-content-formatting.md
