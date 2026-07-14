---
name: agent-fleet-control
description: Coordinate multiple coding agents with isolated Git worktrees, explicit path territory, verification evidence, and human-reviewed merge receipts. Trigger on "fleet new", "spin up a second agent", or multi-agent work.
---

# Agent Fleet Control

Use this skill when the user says `fleet new`, asks to "spin up a second agent," or requests multi-agent work with writing agents.

## Invariants

1. One writing agent per worktree. Read-only reviewers may inspect, but must not edit, a writer's checkout.
2. Every writer gets explicit repository-relative path territory before work begins.
3. Verification must pass for the exact current commit before a receipt is created.
4. Never merge unattended. This skill and `bin/agent-fleet` never push or merge.

## Workflow

1. Confirm the repository has an initial commit and the intended task is bounded.
2. Convert the assignment into a task contract: agent name, task, allowed paths, observable acceptance criteria, and one verification command.
3. Run:

   ```sh
   bin/agent-fleet new <agent> "<task>" \
     --path <repository-relative-path> \
     --acceptance "<criterion>" \
     --verify "<command>"
   ```

4. Give the writer only the created worktree and its recorded contract. Do not let another writer edit that worktree.
5. If territory collides, change the scope. Use `--override` only after explicit human approval and call out the recorded exception.
6. When the writer stops, inspect the diff and run `bin/agent-fleet verify <agent>`.
7. After independent review, record the reviewer and every known risk:

   ```sh
   bin/agent-fleet receipt <agent> \
     --reviewer "<identity>" \
     --risk "<risk or None reported>"
   ```

8. Hand the receipt, diff, and commit to a human merge owner. The human chooses whether and how to merge.

## Boundaries

- Treat allowed paths as coordination metadata, not an operating-system sandbox.
- Treat reviewer identity as an assertion, not authentication.
- Treat verification commands as trusted repository code; they execute with the caller's local permissions.
- Do not place credentials in task text, criteria, commands, or logs.
