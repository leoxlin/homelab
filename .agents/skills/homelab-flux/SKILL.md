---
name: homelab-flux
description: Use when the user wants to add a new application/stack to the Hydra homelab repo (FluxCD on k3s) — "deploy X", "add an app for Y", "set up <service> in the cluster". Scaffolds the per-app Flux Kustomization, manifests (Deployment/Service/PVC/VirtualService), optional Postgres/Redis/secrets, wires it into flux/kustomization.yaml, and validates with mise lint-flux. Not for editing an existing app or non-app infra.
---

Scaffold a new application stack in the homelab repo (`~/Source/homelab`: FluxCD GitOps on
k3s, Istio ingress). This skill encodes the repo's conventions so you can build a working
stack without re-discovering them. **Read a close neighbor app before writing** — copy its
shape rather than inventing one. Ground every choice in `AGENTS.md` (project rules).

## What "a stack" is here

Every app lives in `flux/application/<app>/` and is one Flux **Kustomization** registered in
`flux/kustomization.yaml`. Apps deploy into the **`default`** namespace by convention
(set on the inner kustomize `namespace:` field). Two shapes exist:

- **Raw manifests** (most apps) — Deployment + Service + VirtualService (+ PVC, ConfigMap,
  Secret, DB). Models: `napdog` (simplest, single Deployment + PVC + VS), `commafeed`
  (+Postgres), `paperless` (+Postgres +Redis +ConfigMap +Secret, the full template).
- **HelmRelease** (when a good chart exists) — `release.yaml` with a `HelmRelease`. Models:
  `authentik`, `litellm` is raw. Needs a `HelmRepository` in `flux/system/sources.yaml`.

## Step 0 — Decide the shape (ask only if unclear)

Before scaffolding, settle these. Pick sensible defaults; ask **one** focused question only
if a choice is load-bearing and unguessable (per `AGENTS.md`).

- **Image**: upstream image + tag. Check Context7 / the project's docs for the canonical
  image, required env, ports, and volume paths — don't guess env var names.
- **Hostname**: `<name>.hydrahmlb.cc` (internal) — needs **no DNS or cert work** (see
  "Ingress" below). Public exposure adds the public gateway.
- **Storage**: does it need a PVC? `longhorn` storageClass, `ReadWriteOnce` unless multiple
  pods mount it (then `ReadWriteMany`, as `paperless`).
- **Database**: Postgres → CloudNativePG `Cluster`; Redis/valkey → opstree `Redis`. Each
  adds a `dependsOn` (below) and a generated secret.
- **Secrets**: any? → 1Password `OnePasswordItem` (never inline secrets — `AGENTS.md`).
- **Helm vs raw**: prefer raw manifests unless the upstream chart is the supported path.

## Step 1 — Scaffold the files

Create `flux/application/<app>/` with this set (drop the ones you don't need). **Resource
order in `kustomization.yaml` matters**: DB → redis → volume → configmap → secrets →
deployment → service.

### `<app>.yaml` — the Flux Kustomization (the entrypoint)
```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <app>
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./flux/application/<app>
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: infrastructure          # always
    - name: postgres-operator       # only if it has a CNPG Cluster
    - name: redis-operator          # only if it has a Redis
```

### `kustomization.yaml` — the inner kustomize (note `namespace: default`)
```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: default
resources:
  - postgres.yaml      # if present, in this order
  - redis.yaml
  - volume.yaml
  - configmap.yaml
  - secrets.yaml
  - deployment.yaml
  - service.yaml
```

### `deployment.yaml`
- `metadata.labels.app: <app>`; matching `selector`/template labels.
- Pin the image with a Renovate hint: `# renovate: datasource=docker depName=<image>`
  above the `image:` line (see `paperless`, `commafeed`, `servarr`).
- `strategy.type: Recreate` for single-PVC apps (RWO can't be double-mounted on rollout).
- Add `k8s.hydrahmlb.cc/schedule: server|worker|storage` to `metadata.labels` to pin the pod
  to a node class — `flux/patches/prefer-*.yaml` injects nodeAffinity by that label.
- Wire DB/secret env via `valueFrom.secretKeyRef` (operator-generated secret, below);
  bulk config via `envFrom.configMapRef` / `secretRef`.
- Set `resources.requests.memory` (and `cpu` if known) + liveness/readiness probes.

### `service.yaml` — Service + Istio VirtualService
```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: <app>
spec:
  selector:
    app: <app>
  ports:
    - port: <port>
      targetPort: <port>
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: <app>
spec:
  hosts:
    - <app>.hydrahmlb.cc
  gateways:
    - istio-ingress/hydrahmlb-gateway              # internal
    # - istio-public-ingress/hydrahmlb-public-gateway   # add for public exposure
  http:
    - match:
        - port: 80
      redirect:                                    # force HTTPS — every app does this
        scheme: https
        redirectCode: 301
    - route:
        - destination:
            host: <app>.default.svc.cluster.local
            port:
              number: <port>
```

### `volume.yaml` (if stateful)
```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <app>-data
spec:
  accessModes: [ReadWriteOnce]      # ReadWriteMany only if multiple pods mount it
  storageClassName: longhorn
  resources:
    requests:
      storage: 5Gi
```

### `postgres.yaml` (CloudNativePG) — generates secret `<app>-pg-app` (keys: `password`, `uri`)
```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: <app>-pg
spec:
  instances: 1
  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ClusterImageCatalog
    name: postgresql-minimal-trixie
    major: 18
  storage:
    storageClass: longhorn
    size: 1Gi
```
Connect via host `<app>-pg-rw.default.svc.cluster.local:5432`, db/user `app`. Pull the
password from `secretKeyRef: {name: <app>-pg-app, key: password}` (or full `uri` key — see
`litellm`).

### `redis.yaml` (opstree operator) — see `paperless/redis.yaml`
Reach it at `redis://<app>-redis.default.svc.cluster.local:6379`.

### `secrets.yaml` (1Password) — never inline secrets
```yaml
---
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: <app>-secrets
  namespace: default
  annotations:
    operator.1password.io/auto-restart: "true"   # restart pods on secret change
spec:
  itemPath: "vaults/Hydra/items/main.<app>"        # create this item in 1Password first
```

### `configmap.yaml` (non-secret env) — see `paperless/configmap.yaml`.

## Step 2 — Register it

Add one line to `flux/kustomization.yaml` under `resources:`, alphabetically among the
`application/*` entries:
```yaml
  - application/<app>/<app>.yaml
```
(Note: the file is named `<app>.yaml`; `singularr` is the lone exception, `singularr-app.yaml`.)

For a **HelmRelease** app, also add a `HelmRepository` block to `flux/system/sources.yaml`
(model the existing entries; use `type: oci` for OCI registries).

## Ingress, DNS & TLS — already solved, do not reinvent

- **TLS**: a wildcard cert `hydrahmlb-tls` (`*.hydrahmlb.cc` + `hydrahmlb.cc`) is issued by
  cert-manager on **both** gateways (`flux/infrastructure/cert-manager/resources.yaml`).
  A new `*.hydrahmlb.cc` host needs **no Certificate** of its own.
- **DNS**: `*.hydrahmlb.cc` resolves to the cluster ingress already; external-dns only
  manages the `singularr.app` domain (`domainFilters`). So `<app>.hydrahmlb.cc` needs **no
  DNS record**. Only a brand-new external domain needs an external-dns/cert change.
- **Gateways**: `istio-ingress/hydrahmlb-gateway` (internal/LAN) and
  `istio-public-ingress/hydrahmlb-public-gateway` (internet). Reference one or both in the
  VirtualService `gateways` list — add the public one only when the app should be public.
- **SSO**: route auth through Authentik via OIDC (`authentik.hydrahmlb.cc/application/o/...`)
  when the app supports it — see `litellm` (generic OIDC env) and `paperless` (allauth).

## Backups (optional, for stateful apps with real data)

Add a k8up `Schedule` to back the PVC to Backblaze B2 (restic). Copy `immich/backup.yaml`
or `nextcloud/backup.yaml`: it references `k8up-secrets` and selects pods/PVCs by the
`k8up.io/backup-target` label. Requires `k8up` (already deployed). DB dumps: CNPG can also
back up directly — check the existing app pattern before choosing.

## Step 3 — Validate

```bash
mise lint-flux      # yamllint + flux build dry-run of every Kustomization (from repo root)
mise lint           # also runs ansible lint; use lint-flux for app-only changes
```
`flux build` will catch a missing registration, bad path, or schema error. Do **not**
hand-roll `kubectl`/`kustomize` invocations — `mise lint-flux` is the project entrypoint
(`AGENTS.md`). Flux applies on push to the tracked branch; mention that flux pruning of a
removed resource is stateful (it deletes the live object) per `AGENTS.md`.

## Local-build images

If the app is a custom image (not upstream), it's built under `docker/<name>/` and
published by `.forgejo/workflows/docker.yaml` to the `hydrahmlb/*` registry (e.g.
`napdog`, `lapdog`, `cloud-code`). Reference the image as `hydrahmlb/<name>:latest`.

## External references

Fetch current docs with **Context7** before relying on any chart/CRD field (`resolve-library-id`
→ `query-docs`); the versions below drift. Repo-pinned versions live in
`flux/system/sources.yaml` and the HelmReleases.

- FluxCD Kustomization / GitOps — https://fluxcd.io/flux/components/kustomize/kustomization/
- FluxCD HelmRelease — https://fluxcd.io/flux/components/helm/helmreleases/
- Kustomize reference — https://kubectl.docs.kubernetes.io/references/kustomize/
- Istio VirtualService — https://istio.io/latest/docs/reference/config/networking/virtual-service/
- Istio Gateway — https://istio.io/latest/docs/reference/config/networking/gateway/
- CloudNativePG (Postgres) — https://cloudnative-pg.io/documentation/current/
- Redis Operator (opstree) — https://ot-redis-operator.netlify.app/
- cert-manager — https://cert-manager.io/docs/
- external-dns — https://kubernetes-sigs.github.io/external-dns/
- k8up (restic backups) — https://k8up.io/
- Longhorn storage — https://longhorn.io/docs/
- 1Password Kubernetes Operator — https://developer.1password.com/docs/k8s/k8s-operator/
- Authentik (SSO) — https://docs.goauthentik.io/
- Renovate Docker datasource — https://docs.renovatebot.com/modules/datasource/docker/

## Guidelines

- Copy a neighbor app, don't invent structure; match its naming/ordering exactly.
- Internal `*.hydrahmlb.cc` hosts get TLS+DNS for free — never add a Certificate or DNS
  record for them.
- 1Password/External Secrets only; never inline or commit a secret (`AGENTS.md`).
- Pin images and add a `# renovate:` hint so updates are tracked.
- Treat PVCs, DB clusters, namespace choices, and flux pruning as stateful — flag a
  migration/rollback note when relevant (`AGENTS.md`).
- Always finish with `mise lint-flux`; report its output honestly.
- If the design is non-trivial (new infra dependency, public exposure, migration), consider
  `homelab-design` first to produce a grounded plan.
