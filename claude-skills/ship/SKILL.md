---
name: ship
description: Stage, commit, and push all changes with an auto-generated concise commit message.
disable-model-invocation: true
allowed-tools: Bash
---

Ship the current changes in this git repository:

1. Run `git diff` and `git diff --cached` and `git status` to understand all staged and unstaged changes
2. Stage all relevant changes (prefer `git add` with specific files over `git add -A` — never stage secrets like .env files)
3. Write a commit message that summarizes the changes as concisely as possible — a few words or one short sentence for small changes, more detail only when warranted. Do not use conventional commit prefixes. End the message with a Co-Authored-By line
4. Commit using a HEREDOC for the message
5. Push to the current remote tracking branch
