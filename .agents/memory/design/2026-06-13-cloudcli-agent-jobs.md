# cloudcli — running agent sessions as Jobs & persisting context

Date: 2026-06-13
Scope: investigation/design only (no manifests shipped for this part). The deployed
cloudcli app (`flux/application/cloudcli/`) runs sessions in-process today; this doc
captures how to move them to per-session Kubernetes Jobs and keep them resumable.

## How cloudcli persists context today

cloudcli (`@cloudcli-ai/cloudcli`, upstream `siteboon/claudecodeui`) keeps state in two
places, both under `$HOME` (we set `HOME=/data` on a PVC):

- `~/.cloudcli/auth.db` — SQLite (`better-sqlite3`). Tables include `users`, `api_keys`,
  `projects`, and **`sessions`** (`session_id`, `project_path`, `provider`). This is a
  pointer/index — it does **not** store transcript bodies.
- `~/.claude/` — Claude Code's own state: per-project transcripts at
  `projects/<encoded-cwd>/<session_id>.jsonl`, plus OAuth creds after `claude login`.

Claude sessions are launched **in-process** through `@anthropic-ai/claude-agent-sdk`:
`query({ prompt, options })`, and resumed with `options.resume = <session_id>`. The
server tracks live runs in an in-memory `activeSessions` Map and streams output to the
browser over WebSocket. (Gemini/cursor/codex/opencode providers shell out to their CLIs
instead — not relevant for our Claude-only setup.)

**Consequence:** "retrigger a session later" already works on a long-lived Deployment,
because `auth.db` + `~/.claude/...jsonl` are on the PVC and `resume` replays them. The
only thing lost on a pod restart is the in-memory `activeSessions` map of *currently
streaming* runs.

## Why move to Jobs

- Resource isolation & limits per run (CPU/mem/timeout), crash isolation.
- Concurrency beyond a single pod; runs that outlive the UI pod.
- A clean handle (`session_id`) to stop/retrigger an individual agent run.

## Proposed design

1. **Shared storage must become RWX.** Today the PVC is `ReadWriteOnce`, fine for one
   pod. Jobs + the UI pod must both see the same `~/.claude` (and the project
   workspace), so switch to `ReadWriteMany` — either Longhorn RWX or an NFS export off
   `marten` (the repo already mounts marten NFS via `flux/infrastructure/storage-marten`).
   This is the single biggest stateful change vs. the shipped RWO design.

2. **Per-session Job launcher.** The UI server (given a Role/RoleBinding to create Jobs
   in its namespace) creates one `batch/v1` Job per run instead of calling the SDK
   in-process. Job spec:
   - image: the same `git.hydrahmlb.dev/leoxlin/cloudcli` image (claude CLI already on PATH);
   - command: headless Claude Code, e.g.
     `claude -p --resume <session_id> --output-format stream-json --input-format stream-json`;
   - mounts: the RWX `~/.claude` PVC + the project workspace PVC;
   - `ttlSecondsAfterFinished` so finished Jobs self-reap (or a reaper CronJob);
   - `activeDeadlineSeconds` for a hard timeout; `backoffLimit: 0`.

3. **Streaming back to the UI.** Tail Job stdout (`stream-json`) to the browser over the
   existing WS path — either the launcher proxies `kubectl logs -f` equivalent via the
   k8s API, or the Job writes NDJSON to a known file on the RWX volume that the UI
   follows. `session_id` stays the stable key the `sessions` table already stores, so
   "retrigger" == create a new Job with `--resume <session_id>`.

4. **State ownership.** Transcripts in `~/.claude` (written by the Job's claude process)
   and the `sessions` index in `auth.db` (written by the UI). Track Job lifecycle keyed
   by `session_id` (a small table or just label Jobs `cloudcli.session=<id>`).

## Open questions / risks

- **SQLite single-writer.** `better-sqlite3`/`auth.db` is not safe for many concurrent
  writers. Keep the **UI pod as the sole `auth.db` writer**; Jobs should only touch
  `~/.claude` transcript files, not the DB. If Jobs ever need DB writes, move metadata to
  the existing Postgres operator (CNPG) instead of SQLite.
- **RWX choice.** Longhorn RWX (NFS-backed share-manager) vs. marten NFS — validate
  write performance and concurrent-access semantics for many `.jsonl` appends before
  committing.
- **RBAC blast radius.** Job-creation RBAC for the UI server is a privilege; scope the
  Role to a dedicated namespace and to `jobs`/`pods/log` only. This app already executes
  arbitrary code, so keep it internal + behind Authentik (as deployed).
- **Workspace identity.** `project_path` in `sessions` must match the workspace mount
  path inside the Job, or `--resume` won't find the right `~/.claude/projects/<cwd>/`
  directory (the encoded-cwd is path-derived). Mount workspaces at a stable path.

## Pointers

- Deployed app: `flux/application/cloudcli/` (Deployment + oauth2-proxy sidecar + RWO PVC).
- Image: `docker/cloudcli/Dockerfile`, built by `.forgejo/workflows/build-cloudcli.yaml`.
- RWX prior art in-repo: `flux/infrastructure/storage-marten/` (NFS), Longhorn at
  `flux/infrastructure/longhorn/`.
