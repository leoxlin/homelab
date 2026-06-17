---
name: homelab-design
description: Use when the user asks to investigate, audit, design, or plan a change to the Hydra homelab repo (Ansible + FluxCD on k3s) — questions like "how does X work / can I make X faster / how do I add Y / should I change Z". Produces a grounded investigation, a prioritized strategy, and a concise dated memory doc under .agents/memory/design/. Not for routine one-line edits.
---

Design and planning workflow for the homelab repo (`~/Source/homelab`: Ansible roles +
FluxCD/k3s GitOps). Use it for investigation, audit, strategy, and "should I / how would
I" questions — not for trivial edits. The output is a clear recommendation **plus** a
dated memory doc so the analysis persists.

## When to use

- "Investigate / audit / look into <subsystem>" (registry, backups, networking, an app)
- "Can I make X faster / cheaper / more reliable?"
- "How would I add / migrate / restructure Y?"
- "Should I change Z?" — trade-off questions

For a known small fix, just make it; don't run this workflow.

## Step 1 — Investigate before advising

Read the actual repo; never answer the homelab from generic Kubernetes/CI assumptions
(per `AGENTS.md`). Trace the **full path** of whatever is asked about, across the layers
that touch it:

- **Ansible** — `ansible/roles/`, `ansible/inventory/` (`hosts.yaml`, `host_vars/`,
  `group_vars/`), `ansible/playbooks/`. Note which host runs what and on which subnet.
- **Flux** — `flux/{system,infrastructure,database,application,patches}/`. Note
  `dependsOn`, Kustomization layering, `prune`.
- **mise / entrypoints** — `mise.toml` (`mise lint`, `lint-flux`, `lint-ansible`,
  `ansible`).
- **Secrets** — 1Password (`op://...`, `OnePasswordItem`), External Secrets. Never invent
  credentials or commit secrets.

Follow data end-to-end (e.g. container → exposure → how the cluster consumes it →
firewall → storage). Verify tool/config specifics with Context7 rather than memory when a
library/CLI's behavior is load-bearing. Use parallel Grep/Read/Bash to map it quickly.
Note network topology (subnets in `hosts.yaml`) when latency or reachability is in play.

## Step 2 — Form strategy

Turn findings into a prioritized recommendation:

- Order options **biggest win / highest priority first**; give a clear recommendation, not
  an exhaustive survey.
- Call out **gaps** explicitly (missing config, disabled features, growth-without-cleanup).
- Flag **stateful / risky** operations — Flux pruning, namespace moves, PVCs, DB
  operators, router/registry storage, k3s args — as needing a migration/rollback plan and
  a reviewed change with the relevant `mise lint-*` run.
- End with a concrete **change bundle**: the specific files to touch and what each change
  is, so it's actionable. Offer to implement (all or a subset); don't start editing during
  an investigation unless asked.
- If the prompt is genuinely ambiguous, ask one focused question before broad changes.

## Step 3 — Write the memory doc

Persist the analysis to `.agents/memory/design/` so it survives the session. Match the
existing format in that directory (read a neighbor file first). These docs record
investigations and recommendations; treat them as design notes, not as authoritative
implementation guidance unless the corresponding changes were shipped and are referenced in
`AGENTS.md`:

- Filename: `YYYY-MM-DD-<kebab-slug>.md` (use the real current date).
- Header: `# <Title>`, then `Date:` and `Scope:` lines. State plainly if it's
  investigation/recommendations only with nothing shipped.
- Body: the architecture as found (with `file_path` references), numbered sections per
  question/area, fenced config snippets, and a final **Recommendation** with the change
  bundle.
- Reference concrete paths and host/IP/port facts — the value is that it's grounded in
  this repo, not generic.

### Keep it concise — these get re-read into context

A memory doc is reference material a future session loads, so optimize for fast scanning
and low token cost, not completeness:

- **Target ~150 lines / one screen.** If it's longer, you're including too much.
- **One fact per line.** Cut filler, hedging, and restated reasoning. Prefer terse
  bullets over paragraphs; a `path:line` reference beats re-describing what the file says.
- **Only the load-bearing config.** Snippets show the *delta* or the key knobs, not whole
  files — link to the path for the rest.
- **Don't duplicate the repo.** If the answer is "read this file", say that; record only
  what isn't obvious from the code itself (gaps, trade-offs, the decision and its why).
- **Conclusions over transcript.** Capture what you concluded, not the steps you took to
  get there. Drop dead-ends unless the dead-end itself is the useful finding.

Write it once, tightly. Don't pad to look thorough.

Always do Step 3 when the user wants the analysis kept; for a quick verbal answer they
didn't ask to save, Steps 1–2 may be enough — but offer to write the memory.

## Guidelines

- Ground every claim in a file you actually read; cite `path:line` where useful.
- Prefer the repo's own entrypoints (`mise lint-flux`, `mise lint-ansible`, `mise
  ansible`) for any validation you suggest.
- Keep small fixes moving; reserve this heavier workflow for design-level work.
- Memory docs are re-read into context later — write them tight (see Step 3). Brevity is a
  feature, not a shortcut.
