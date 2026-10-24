<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Update the DNA to dna_ggsuite 1.0

## Motivation

- gg_merge holds the tools and checks for merging Dart packages. Its
  guides, skills and the managed block of `CLAUDE.md` are generated from
  the dna_ggsuite DNA and tell developers and Claude how to work here
- With dna_ggsuite 0.4 they had fallen behind: blog posts went to `blog/`,
  no `gg-` skill covered the review, and the code guide still asked for a
  package prefix on every type
- This change is small: it brings the generated files to dna_ggsuite 1.0
  and leaves the code of gg_merge untouched

## Strategy

- Raise the dev dependencies `dna_ggsuite` to ^1.0.0 and `helix` to ^1.13.0
- Let helix regenerate the DNA files, committed as `#gg: generated DNA`
- Change nothing in `lib/`, `bin/` and `test/`

## Implementation 1: Ticket workflow

- New skill `/gg-review`: checks the diff of every repo against its scope,
  writes the blog posts, updates README.md and `index.jsonc`, then opens
  the pull requests and runs `/review-light`
- `/gg` and the `CLAUDE.md` block name `/gg-review` as the step between
  push and publish; `/gg-publish` checks that the blog post exists
- `/gg-commit` proposes one message per repo, in the repo's own terms;
  repos that depend on each other are committed one by one
- `ai-dev-guide.md` gains three sections: keep every repo in its scope,
  keep the `index.jsonc` up to date, describe every repo in its own terms
- New hooks in `.claude/settings.json` keep the prompts, never the
  answers, in the project management repo, with tokens redacted

## Implementation 2: Blog, README and code guides

- The blog guide puts one post per repo into `doc/blog/<yyyy>/`, about this
  repo only; the template gains a "Dependency updates" section
- The README guide is rewritten around Motivation, Installation, Usage,
  Limitations and License, in `README.md` and a German `README.de.md`
- New `scripts/check-readme.js`, run by `/readme`, reports what a script
  can find: missing sections, placeholders, broken links and badges
- The translate guide looks for German posts in `doc/de/blog/<yyyy>`;
  `setup-github-guide.md` moves from `guides/` to `doc/guides/`
- The code guide no longer asks for the package prefix on types and file
  names; its examples read `User` instead of `GgUser`

## Dependency updates

- `dna_ggsuite` 1.0.0 brings `dna_gg` 1.0.0 (workflow skills, AI guide,
  hooks), `dna_clean_code` 0.2.2 (code and test guides), `dna_blog` 0.3.0,
  `dna_readme` 0.3.1, `dna_translate` 0.3.0 and `dna_github` 0.1.1
- `helix` 1.13.0 joins the `CLAUDE.md` parts of all layers instead of
  letting the last layer win
- No runtime dependency constraint changed

## Open Points

- `.claude/hooks/pm-prompts.json` names no project management repo yet, so
  the hooks keep no prompts; they need Node.js to run at all
- README.md does not follow the new guide: `check-readme.js` misses
  Motivation, Installation, Usage, License and `README.de.md`, and the
  first sentence says "merging" where `pubspec.yaml` says "publishing"
- The repo has no `index.jsonc` yet, although the new guides ask for one
- `pubspec_overrides.yaml` points the dependencies at the sibling
  checkouts while the ticket is open; it goes when the references return
  to pub.dev
