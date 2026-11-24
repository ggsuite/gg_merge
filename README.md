# gg_merge

Various tools and checks for merging dart packages

## Pull requests

`MergeGit` creates the pull request on GitHub (`gh`) or Azure DevOps (`az`)
and sets auto-merge. It starts at most 80 new pull requests a minute and
500 an hour, counted for the whole process (`RequestLimit.pullRequests`;
`pullRequestLimit:` takes another limit), and repeats a request the
provider turns away with a rate limit after a wait. `WaitForMerge` polls
after 2 s, 4 s and 8 s, then every 15 s.

`WaitForMerge` waits without a time limit for a pull request that only
waits — for running checks or a review. It fails with an error naming the
pull request as soon as it cannot merge without help:

- a merge conflict (GitHub `mergeable: CONFLICTING`, Azure `mergeStatus:
  conflicts`)
- a failed required check (GitHub: `gh pr checks --required`; Azure: a
  rejected or broken blocking build or status policy)
- a branch the branch protection wants up to date (GitHub `BEHIND`)
- a merge the provider refused (Azure `mergeStatus: failure` or
  `rejectedByPolicy`)

The reason has to show in three polls in a row, so a state left over from
the commit before a push does not end the wait.
