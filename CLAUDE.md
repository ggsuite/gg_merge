<!-- helix:claude_md:start -->

@.claude/CLAUDE_dna_gg.md

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
