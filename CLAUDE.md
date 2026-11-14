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

# Waiting for a pull request

`WaitForMerge` polls the pull request of a branch until the provider merged
it. The polls start quickly and slow down (`pollDelay`): 2 s, 4 s, 8 s, then
every poll interval (15 s). A pull request nothing holds back — no required
checks — merges within seconds, and a fixed interval made every such merge
cost a full interval. A transient network error still waits a full interval
before the lookup is repeated.

# Creating a pull request

`MergeGit` creates the pull request (`gh pr create`, `az repos pr create`)
and sets auto-merge (`gh pr merge --auto`) through gg_git's `GitRetry`. A
provider counts the requests that create something per client and turns a
client away for a while when it sends too many (HTTP 429, GitHub's
»secondary rate limit«); the request is right, so it is repeated after a
wait of a minute, doubled with every retry. Any other failure is reported
at once, as before.

So that it does not come to that, `MergeGit` counts the pull requests it
creates: `RequestLimit` (`lib/src/util/request_limit.dart`) lets a request
start only while fewer than so many started within a length of time —
`RequestLimit.gitHubContentLimits`, what GitHub documents for requests that
create content: **80 within a minute, 500 within an hour**. What a provider
counts is how many requests start, not how many run at the same moment, so
callers may create as many pull requests at once as they like:
`start()` completes right away while the count allows one more and
otherwise once enough earlier requests are older than the time counted,
callers served in the order they asked, a waiting one told so once
(»80 new pull requests started within a minute, and a provider takes no
more. Waiting 23s.«). Every attempt counts, a retry too; a pull request
that is reused does not. `RequestLimit.pullRequests` is **one limit for the
whole process** and the default of every `MergeGit`, because the provider
counts all of them together; other processes and other tools of the same
user are not counted, the retry above covers them. `pullRequestLimit:`
takes another limit, `now:` and `wait:` of `RequestLimit` make it testable
without waiting. Azure DevOps gets the same numbers.
