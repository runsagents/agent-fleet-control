# Attribution and provenance

`agent-fleet-control` is an original implementation prepared for [runsagents](https://github.com/runsagents), with project direction attributed to Shakhzod. The CLI, tests, fixture, schemas, templates, policy, and prose in this repository were written for this project from its behavioral specification.

## Conceptual prior art

### Superpowers

- Project: [obra/superpowers](https://github.com/obra/superpowers)
- Specific reference: [`using-git-worktrees`](https://github.com/obra/superpowers/blob/main/skills/using-git-worktrees/SKILL.md)
- Author/licensor: Jesse Vincent and contributors
- License observed on 2026-07-14: [MIT](https://github.com/obra/superpowers/blob/main/LICENSE)
- Influence: the workflow concept that isolated Git worktrees are a useful boundary for parallel coding-agent work, plus the practice of verifying work before integration.

No Superpowers source code or prose was copied into this project. Its worktree workflow is credited as conceptual prior art.

### agent-scripts

- Project: [steipete/agent-scripts](https://github.com/steipete/agent-scripts)
- Author/licensor: Peter Steinberger and contributors
- License observed on 2026-07-14: [MIT](https://github.com/steipete/agent-scripts/blob/main/LICENSE)
- Influence: the script-ecosystem preference for small, portable, repository-local agent guardrails.

No `agent-scripts` source code or prose was copied into this project. The implementation here does not vendor, translate, or derive from its scripts.

## Clean-room statement

The implementation was produced from the public behavior described in the project specification. Prior-art repositories were consulted to identify and accurately credit concepts and ecosystem influence; they were not used as implementation sources. All executable scripts in this repository are original.

## License source

The project is dedicated under [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/). `LICENSE` is the full plain-text legal code fetched from Creative Commons at <https://creativecommons.org/publicdomain/zero/1.0/legalcode.txt> on 2026-07-14.
