<!-- helix:claude_md:start -->

# gg workflow

This repo is developed ticket by ticket with the `gg` CLI. Follow the
development guide, it tells you when to ask the user and which command
comes next:

@doc/guides/for-ai/ai-dev-guide.md

The steps are also available as skills: `/gg-ticket`, `/gg-commit`,
`/gg-push`, `/gg-publish`, `/gg-cleanup`. `/gg` lists them and says which
one comes next.

<!-- helix:claude_md:end -->

# Merge preconditions

`CanMerge` (`lib/src/commands/can_merge.dart`) first runs `UpdateProjectGit`
(`git fetch --all -p`, then `git pull`), then checks for local package
references and whether the branch is behind or ahead of the default branch.
The pull is skipped when the current branch has no upstream left: a pull
request that was auto-completed by the provider deletes the remote feature
branch, the fetch prunes it, and `git pull` would otherwise die on the
configured but missing ref. Fetch and pull are retried on transient network
errors via gg_git's `GitRetry`.
