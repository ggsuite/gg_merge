<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Count new pull requests and wait out a rate limit

## Motivation

- A git provider counts the requests that create something — a pull
  request, a comment — per client. A client that sends too many is turned
  away for a while: HTTP 429, on GitHub the »secondary rate limit«
- Such a request is right, it only comes at the wrong time. So far
  `MergeGit` reported it as a failure, and the pull request was missing
- Whoever creates many pull requests in a short time should not have to
  know these limits. The package keeps them itself
- Waiting for a merge had a second, smaller cost: `WaitForMerge` asked the
  provider every 15 s. A pull request nothing holds back merges within
  seconds, but every such merge cost a full interval

## Strategy

- Two lines of defence for creating pull requests:
  - count the new pull requests and let one start only while the provider
    takes one more
  - repeat a request the provider turns away all the same, after a wait
- Count what the provider counts: how many requests **start** within a
  time, not how many run at the same moment
- Keep one count for the whole process, because the provider counts all
  pull requests of a client together
- Poll for the merge quickly at first, then slow down to the old interval

## RequestLimit: count the requests that start

- New class `RequestLimit` in `lib/src/util/request_limit.dart`, exported
  by the package
- It takes a list of limits, each »so many requests within this time«.
  `RequestLimit.gitHubContentLimits` holds what GitHub documents for
  requests that create content: 80 within a minute, 500 within an hour
- `start()` completes right away while the count allows one more request.
  Otherwise it completes once enough earlier requests are older than the
  time counted
- Callers are served in the order they asked. A caller that has to wait is
  told so once: »80 new pull requests started within a minute, and a
  provider takes no more. Waiting 23s.«
- Callers may create as many pull requests at the same time as they like;
  the limit only spreads their starts
- `now:` and `wait:` put the limit on the clock of a test, so no test
  waits

## MergeGit asks the limit and repeats a refused request

- `MergeGit` asks `RequestLimit.pullRequests` before every `gh pr create`
  and `az repos pr create`. It is one limit for the whole process and the
  default of every `MergeGit`; `pullRequestLimit:` takes another one
- Every attempt counts, a retry too. A pull request that is reused creates
  nothing and is not counted
- Azure DevOps gets the same numbers as GitHub
- `gh pr create`, `az repos pr create` and `gh pr merge --auto` now run
  through gg_git's `GitRetry`: a request the provider turns away with a
  rate limit, or a connection it drops, is repeated after a wait
- Any other failure is reported at once, as before

## WaitForMerge polls quickly at first

- New method `pollDelay(polls)`: the polls follow after 2 s, 4 s and 8 s,
  then every poll interval (15 s by default)
- A pull request without required checks is found merged after a few
  seconds instead of after a full interval
- A pull request that is still open after these polls is waiting for the
  server; the usual interval is short enough from there on
- A poll that fails with a transient network error still waits a full
  interval before the lookup is repeated

## Dependency updates

- gg_git: `GitRetry` now recognizes a rate limit (HTTP 429, »secondary
  rate limit«). It waits a minute before the first retry and doubles the
  wait with every further one, four attempts at most

## Open Points

- The count covers this process only. Other processes and other tools of
  the same user are not counted; the retry after a refused request has to
  cover them
- The numbers are the ones GitHub documents. Azure DevOps gets the same
  numbers, not limits of its own
- `gh pr merge --auto` is repeated after a rate limit, but not counted:
  only the requests that create a pull request ask the limit
- The repo has an `index.jsonc` now. The README is still a single line and
  says nothing about `RequestLimit`
