---
name: homelab-design
description: Use when investigating, auditing, or designing changes to the Hydra homelab repo (Ansible + FluxCD on k3s) — questions like "how does X work / can I make X faster / how would I add Y / should I change Z". Requires the Superpowers plugin.
---

# Homelab design brief

Domain-specific investigation layer for the Hydra homelab repo (`~/Source/homelab`).
This skill does **not** replace the Superpowers design workflow — it only supplies the homelab-specific context that Superpowers needs.

## How to use

1. **Start with Superpowers.** For any design question, invoke `superpowers:brainstorming` first and let it drive the design process.
2. **Apply this brief during investigation.** Ground the analysis in the repo rather than generic Kubernetes patterns.

## Homelab investigation checklist

- **Ansible**: `ansible/roles/`, `ansible/inventory/hosts.yaml`, `host_vars/`, `group_vars/`, `ansible/playbooks/`. Note hosts, subnets, and which role runs where.
- **Flux**: `flux/{system,infrastructure,database,application,patches}/`. Note Kustomization layering, `dependsOn`, and `prune`.
- **Entrypoints**: prefer `mise lint`, `mise lint-flux`, `mise lint-ansible`, and `mise ansible` for validation.
- **Secrets**: use only 1Password (`op://...`, `OnePasswordItem`) and External Secrets. Never invent or commit credentials.
- **Stateful / risky changes**: Flux pruning, namespace moves, PVCs, database operators, router/registry/storage changes need an explicit migration or rollback plan.

## Outputs

- Write the approved design/spec to `docs/homelab/specs/YYYY-MM-DD-<topic>-design.md`.
- Use `superpowers:writing-plans` to produce the implementation plan.
- Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` to implement.

## When not to use

For one-line fixes or known small changes, just make them.
