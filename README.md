**Production stakes:** use `agent-fleet-control` as a coordination guardrail, not as a substitute for code review, CI, access control, or a human merge owner.
For experiments, the same workflow is intentionally lightweight; for production changes, require independent review and trusted verification in addition to the local receipt.

# agent-fleet-control

Multiple coding agents need separate worktrees, explicit territory, and receipts. This dependency-free CLI turns those constraints into local, inspectable artifacts without ever pushing or merging.

## The two-agent overwrite incident

The incident pattern is ordinary: one agent edits payment validation while a second agent refactors the same service in the same checkout. The first agent verifies against files that the second agent has already changed. Then one of them rewrites or discards the other's edits while trying to get back to a clean tree. Both agents can honestly report that their own task passed, yet the final diff no longer represents either verified state.

This is a generic failure scenario, not a claim about a named company or a single documented outage. The lesson is concrete: a shared conversation does not isolate writes, path ownership must be declared before work starts, and verification evidence must name the exact commit it covers.

## Fleet invariants

1. **One writer per worktree.** A writing agent gets its own branch and checkout.
2. **Explicit territory.** Every task contract lists repository-relative paths. Equal, parent, and child scopes collide.
3. **Verification before receipt.** A receipt requires exit-zero evidence for the worktree's current commit.
4. **Never merge unattended.** `agent-fleet` creates branches, worktrees, contracts, evidence, and receipts. It never commits, pushes, or merges.

Path ownership is coordination metadata. It does not prevent a process from writing outside its territory; the agent host or OS sandbox must enforce that separately.

## Quickstart: two agents

Requirements are Bash, Git, and a repository with at least one commit. From the repository's primary worktree:

```sh
git clone https://github.com/runsagents/agent-fleet-control.git /tmp/agent-fleet-control
install -m 0755 /tmp/agent-fleet-control/bin/agent-fleet "$HOME/.local/bin/agent-fleet"

agent-fleet new api-agent "Harden payment validation" \
  --path services/payments/api \
  --acceptance "API tests cover rejected signatures" \
  --verify "./scripts/test-payments-api.sh"
```

Output:

```text
Created writer api-agent
Branch: fleet/api-agent
Worktree: /repo/.agent-fleet/worktrees/api-agent
Contract: /repo/.agent-fleet/contracts/api-agent/contract.md
```

Create the second writer with disjoint territory:

```sh
agent-fleet new ledger-agent "Reconcile ledger rounding" \
  --path services/payments/ledger \
  --acceptance "Ledger reconciliation tests pass" \
  --verify "./scripts/test-payments-ledger.sh"
```

Output:

```text
Created writer ledger-agent
Branch: fleet/ledger-agent
Worktree: /repo/.agent-fleet/worktrees/ledger-agent
Contract: /repo/.agent-fleet/contracts/ledger-agent/contract.md
```

Point each writing agent at only its printed worktree and contract. The `.agent-fleet/` directory is added to the repository's local Git exclude file, so contracts, logs, linked checkouts, and receipts remain local by default.

## Task contracts and path ownership

`new <agent> <task>` requires one or more of each `--path` and `--acceptance`, plus exactly one `--verify` command. Repeat flags instead of comma-separating values:

```sh
agent-fleet new checkout-agent "Split checkout validation" \
  --path services/checkout \
  --path tests/checkout \
  --acceptance "Invalid carts return a typed error" \
  --acceptance "Checkout tests pass" \
  --verify "./scripts/test-checkout.sh"
```

The CLI records both `contract.md` and schema-compatible `contract.json` under `.agent-fleet/contracts/<agent>/`. The JSON shape is defined by [`schemas/task-contract.schema.json`](schemas/task-contract.schema.json); the human form follows [`templates/task-contract.md`](templates/task-contract.md).

Territory is lexical and repository-relative. `services/payments`, `services/payments/api`, and an identical `services/payments` scope all overlap. Sibling scopes such as `services/payments/api` and `services/payments/ledger` do not. Absolute paths, the repository root, empty components, `.` components, and `..` traversal are rejected.

Use `--override` only after a human explicitly accepts the collision. The exception appears in command output and both contract formats; it does not make concurrent writes safe.

## Verification and merge receipts

Run the contract's exact command inside its worktree:

```sh
agent-fleet verify api-agent
```

Example output:

```text
Running verification for api-agent at 4a7c2d5...
Command: ./scripts/test-payments-api.sh
18 tests passed
Verification passed (exit 0). Evidence: /repo/.agent-fleet/contracts/api-agent/verification.log
```

The evidence bundle captures the command's combined stdout/stderr, exit code, start and finish timestamps, branch, commit SHA, and a Git object digest of the output. Each attempt gets a distinct read-only evidence directory. Verification refuses a dirty or untracked worktree and fails with exit 125 if the command changes `HEAD`, switches branches, or leaves the tree dirty. A command that fails without violating those integrity checks returns its own non-zero exit code and remains available for diagnosis.

After an independent reviewer has inspected the diff and evidence:

```sh
agent-fleet receipt api-agent \
  --reviewer "Alex Reviewer <alex@example.com>" \
  --risk "Load behavior is covered by CI, not the local command"
```

Output:

```text
Receipt: /repo/.agent-fleet/receipts/api-agent-4a7c2d5....md
Machine receipt: /repo/.agent-fleet/receipts/api-agent-4a7c2d5....json
No merge or push was performed.
```

The uniquely named receipt includes the full commit SHA, asserted reviewer identity, verification command, immutable attempt-specific evidence path and digest, timestamps, and every supplied unresolved risk. If the commit or branch changed, the tree is dirty, or the evidence digest no longer matches after verification, receipt creation stops. The machine form follows [`schemas/merge-receipt.schema.json`](schemas/merge-receipt.schema.json); the human form follows [`templates/handoff-receipt.md`](templates/handoff-receipt.md).

Reviewer identity is recorded text, not cryptographic authentication. A human merge owner must validate the reviewer and choose whether and how to integrate the branch.

## Collision demo on the synthetic repository

The fixture is explicitly synthetic: it contains three fake payment modules and no real payment logic, customer data, or credentials.

```sh
repo=$(fixtures/setup-synthetic-repo.sh /tmp/synthetic-payments)
cd "$repo"

/path/to/agent-fleet new api-agent "Synthetic API change" \
  --path services/payments/api \
  --acceptance "Synthetic checks pass" \
  --verify "./test.sh"

/path/to/agent-fleet new service-agent "Synthetic service change" \
  --path services/payments \
  --acceptance "Synthetic checks pass" \
  --verify "./test.sh"
```

The second command refuses the parent/child collision:

```text
error: territory collision: 'services/payments' overlaps 'services/payments/api' owned by 'api-agent'; use --override only with explicit human approval
```

For a deliberate collision exercise, repeat the second command with `--override`. The worktree is created and the contract records `collision_override: true`.

## Failure recovery

**Verification failed.** Read `.agent-fleet/contracts/<agent>/verification.log`, fix the branch in its recorded worktree, commit the change, and rerun `agent-fleet verify <agent>`. A failed gate cannot produce a receipt.

**Verification became stale.** The worktree's `HEAD` changed after the last successful run. Rerun verification; receipts are deliberately commit-bound.

**A process was interrupted while holding the state lock.** First confirm no `agent-fleet` process owns the recorded PID:

```sh
cat .agent-fleet/.lock/pid
ps -p "$(cat .agent-fleet/.lock/pid)"
```

Only after confirming it is stale, remove `.agent-fleet/.lock` and retry.

**A writer must be abandoned.** Preserve anything worth reviewing, then have the human operator remove its worktree and branch and finally delete its local contract:

```sh
git worktree remove .agent-fleet/worktrees/<agent>
git branch -d fleet/<agent>
rm -rf .agent-fleet/contracts/<agent>
```

Use Git's force options only when the human operator has deliberately decided to discard unmerged work. Run `git worktree prune` after recovering from an externally deleted checkout.

## Supported runtimes

| Environment | Status | Notes |
| --- | --- | --- |
| Bash 3.2.57 + Git 2.50.1 on macOS | **Tested** | Full CLI and `npm test` suite. The tests use Node 22's built-in JSON parser but install no packages. |
| Other Bash 3.2+ and Git installations | **Untested** | The CLI uses portable Bash, Git, `sed`, and `grep`, but this matrix has not been exercised. |
| GNU/Linux distributions | **Untested** | Expected to work with Bash and Git; no v1 test claim is made. |
| WSL | **Untested** | Worktree paths and permissions need platform verification. |
| Git Bash on Windows | **Untested** | Native path translation needs platform verification. |
| POSIX `sh`, zsh-only, fish-only | **Unsupported** | Invoke the executable with Bash; it uses Bash arrays and pattern matching. |

Run the complete suite with `npm test`, or run `bash tests/writer-isolation.sh` and `bash tests/merge-gates.sh` directly.

## Security and credential boundaries

- `agent-fleet` never contacts a remote, pushes, merges, commits, or changes the primary branch. Git hooks invoked by local Git remain under the repository owner's control.
- The recorded verification command executes as trusted local code with the caller's permissions. Review it before running; path territory is not a sandbox.
- Contract text, command output, repository files, and receipts can contain secrets. The CLI creates local state with a restrictive process umask and excludes `.agent-fleet/` from local Git tracking, but operators must still scrub logs and enforce filesystem permissions and retention.
- Do not pass tokens, passwords, private keys, or customer data in task text, acceptance criteria, reviewer identity, risks, or command arguments. Prefer the host's credential broker and short-lived environment injection.
- A receipt proves only what its local evidence records. It does not authenticate the reviewer, attest the machine, validate remote CI, scan dependencies, or authorize deployment.
- `--override` is an auditable bypass, not an access-control decision. Require explicit human approval outside the tool.

## Prior art and clean-room implementation

[Superpowers](https://github.com/obra/superpowers), particularly its [`using-git-worktrees` workflow](https://github.com/obra/superpowers/blob/main/skills/using-git-worktrees/SKILL.md), receives concept credit for treating worktrees as isolated agent workspaces and verifying before integration. [Peter Steinberger's `agent-scripts`](https://github.com/steipete/agent-scripts) influenced the preference for small, portable, repository-local script ecosystems and operational guardrails.

This project is a clean-room implementation from its behavior specification. All scripts, schemas, tests, templates, and prose are original; no source code or prose was copied from either prior-art project. See [`ATTRIBUTION.md`](ATTRIBUTION.md) for authors, licenses, exact references, and provenance.

Multiple agents do not need a group chat. They need separate worktrees, explicit territory and a receipt before anything merges.
