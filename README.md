# gg_merge

Various tools and checks for merging dart packages

## Pull requests

`MergeGit` creates the pull request on GitHub (`gh`) or Azure DevOps (`az`)
and sets auto-merge. It starts at most 80 new pull requests a minute and
500 an hour, counted for the whole process (`RequestLimit.pullRequests`;
`pullRequestLimit:` takes another limit), and repeats a request the
provider turns away with a rate limit after a wait. `WaitForMerge` polls
after 2 s, 4 s and 8 s, then every 15 s.
