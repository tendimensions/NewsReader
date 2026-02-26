# Skill: Git Workflow

Guidelines for all git operations in this repository.

## Branch Conventions

- Feature/fix branches must follow the pattern `claude/<description>-<sessionId>`
- **CRITICAL**: Pushing to a branch that doesn't start with `claude/` will fail with HTTP 403
- Never push directly to `main` or `master`
- Always confirm the target branch before pushing

## Daily Workflow

```bash
# Start a session — make sure you're on the right branch
git branch                          # verify current branch
git fetch origin <branch>           # fetch latest without merging
git pull origin <branch>            # pull and merge

# Stage and commit
git add <specific-files>            # prefer named files over git add -A
git commit -m "descriptive message"

# Push
git push -u origin <branch-name>
```

## Commit Practices

- Write concise commit messages that describe **why**, not just what
- Stage specific files by name — avoid `git add -A` or `git add .` (risk of committing secrets or binaries)
- Never skip pre-commit hooks (`--no-verify`)
- Never amend a published commit; create a new one instead
- Never force-push unless the user explicitly requests it

## Retry Logic for Network Failures

If `git push` or `git fetch` fails due to a network error, retry with exponential backoff:

| Attempt | Wait before retry |
|---------|------------------|
| 1st fail | 2 s |
| 2nd fail | 4 s |
| 3rd fail | 8 s |
| 4th fail | 16 s |

Do **not** retry on HTTP 403 (permission/branch-name issue) — fix the root cause first.

## Session Wrap-Up ("Landing the Plane")

Complete **all** steps before ending a session. Work is not done until `git push` succeeds.

1. **File issues** for any remaining work
2. **Run quality gates** (if code changed):
   ```bash
   flutter analyze
   flutter test
   ```
3. **Update issue status** via beads (`bd close <id>` / `bd update <id> --status in_progress`)
4. **Push to remote** — MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push -u origin <branch-name>
   git status   # must show "up to date with origin"
   ```
5. **Clean up** — clear stashes, prune remote branches if needed
6. **Verify** — all changes committed AND pushed
7. **Hand off** — provide context for the next session

**NEVER** stop before pushing. Unpushed commits leave work stranded locally.

## Risky Operations — Confirm Before Running

The following commands require explicit user confirmation:

- `git reset --hard` / `git checkout -- .` / `git restore .`
- `git push --force` / `git push --force-with-lease`
- `git branch -D` (delete branch)
- `git clean -f` / `rm -rf`
- Amending or rebasing published commits

## Secrets & Sensitive Files

- Never commit `.env`, `google-services.json`, `GoogleService-Info.plist`, or any file containing API keys
- `NEWS_API_KEY` must stay in CodeMagic secure env vars only
- Firebase config files are already gitignored — do not force-add them

## Beads Integration

```bash
bd ready               # find available work items
bd show <id>           # view issue details
bd update <id> --status in_progress   # claim work
bd close <id>          # mark complete
bd sync                # sync beads state with git
```

See [AGENTS.md](../../AGENTS.md) for the full beads quick reference.
