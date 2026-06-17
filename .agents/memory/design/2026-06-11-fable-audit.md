# Homelab Audit & Suggestions

Audit of the Hydra homelab repo (Ansible + FluxCD on k3s), 2026-06-11.

## What's already good

- Clean GitOps layering (`system` → `crds` → `infrastructure` → `database` → per-app
  Kustomizations with `dependsOn`), with `prune: true` everywhere.
- Renovate on a self-hosted Forgejo runner with `config:best-practices`, digest pinning,
  and a custom regex manager for the k3s version in Ansible inventory.
- Solid node baseline via the `core` role: SSH hardening, UFW default-deny, fail2ban,
  chrony with drift detection, unattended-upgrades, sysctl hardening.
- HA control plane (3 marmot servers, embedded etcd), MetalLB over BGP to the EdgeRouter,
  Istio ambient-profile gateways with wildcard cert via cert-manager/Cloudflare DNS-01.
- Secrets never in git: 1Password operator (`OnePasswordItem`) everywhere.

The suggestions below are ordered by priority within each section.

---

## 1. Data safety (highest priority)

### 1.1 CNPG Postgres clusters have no backups

`immich-pg`, and the other CNPG clusters (grafana, authentik, nextcloud, commafeed,
paperless) have no `backup:` stanza and no `ScheduledBackup`. K8up's restic file
backups don't cover them: the Postgres PVCs aren't labeled `k8up.io/backup-target`,
and file-level copies of a live Postgres data directory aren't crash-consistent anyway.
A Longhorn disk failure beyond replica tolerance, or a bad migration, loses Immich
metadata, Paperless's index, Authentik's config, etc.

Add a `barmanObjectStore` backup to the existing Backblaze B2 bucket plus a
`ScheduledBackup` per cluster, e.g. for `flux/application/immich/postgres.yaml`:

```yaml
spec:
  backup:
    barmanObjectStore:
      destinationPath: s3://hydra-ecd4ffd5fcf8/backups/immich-pg
      endpointURL: https://s3.eu-central-003.backblazeb2.com
      s3Credentials:
        accessKeyId:
          name: k8up-secrets
          key: AWS_ACCESS_KEY_ID
        secretAccessKey:
          name: k8up-secrets
          key: AWS_SECRET_ACCESS_KEY
    retentionPolicy: "30d"
---
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: immich-pg-backup
spec:
  schedule: "0 0 3 * * *"   # CNPG uses 6-field cron
  cluster:
    name: immich-pg
  backupOwnerReference: self
```

Note: in-tree `barmanObjectStore` is deprecated in newer CNPG in favor of the
`plugin-barman-cloud` CNPG-I plugin — check which your operator version expects.
This also gives you WAL archiving, i.e. point-in-time recovery, not just nightly dumps.

### 1.2 Several stateful apps are not in any k8up backup

Only `immich`, `nextcloud`, `karakeep`, and `calibre` volumes carry the
`k8up.io/backup-target` label, and only immich/nextcloud/karakeep have `Schedule`s
(`scripts/backup.sh` also only knows those three). Unprotected state includes at
least: **paperless** (your documents!), matrix, tubearchivist, openwebui, plex
config, tdarr, kiwix data, and the obsidian vault on junco. Decide per app whether
it's re-downloadable (kiwix, tubearchivist media — maybe skip) or irreplaceable
(paperless, matrix — back up), and add labels + `Schedule`s accordingly.

### 1.3 K8up schedules never prune or check the restic repos

The `Schedule` objects define only `backup:`. Without `prune:` the B2 repos grow
forever (and you pay for it); without `check:` you won't notice silent corruption
until restore day. Add to each schedule:

```yaml
  prune:
    schedule: "0 4 * * 0"
    retention:
      keepDaily: 7
      keepWeekly: 4
      keepMonthly: 6
  check:
    schedule: "0 6 1 * *"
```

While there: the S3 backend block is copy-pasted across every `Schedule` and
`scripts/backup.sh`. K8up supports global defaults via operator env vars
(`BACKUP_GLOBAL*` in the HelmRelease values), which would collapse all of that.

### 1.4 No restore documentation or drills

`scripts/backup.sh` exists but there's no restore counterpart. Write down (in
`docs/`) the restore path for one k8up app and one CNPG cluster, and run it once.
A backup that has never been restored is a hope, not a backup.

### 1.5 Offsite etcd snapshots

k3s takes local etcd snapshots by default, but they live on the marmots. k3s can
ship them to S3 natively — add to `k3s_extra_server_args` (or a
`k3s_server_config_yaml`):

```
--etcd-snapshot-schedule-cron "0 */12 * * *" --etcd-s3 --etcd-s3-endpoint ... --etcd-s3-bucket ...
```

This makes "rebuild the cluster from nothing" much cheaper, since Flux re-creates
everything else.

### 1.6 Longhorn has no backup target

Longhorn replication protects against single-disk loss only. Setting
`defaultSettings.backupTarget` to the B2 bucket plus a `RecurringJob` for
snapshots/backups gives volume-level recovery for everything k8up/CNPG doesn't
cover, and makes volume migration between nodes trivial.

---

## 2. Security

### 2.1 openshell is unauthenticated on the LAN gateway

`flux/application/openshell/release.yaml` sets `disableTls: true` and
`allowUnauthenticatedUsers: true`, and the VirtualService exposes it at
`openshell.hydrahmlb.cc` on the internal gateway. That's an agent-execution
sandbox anyone on the LAN can drive. You already run Authentik — put it in front
(Authentik proxy provider / forward-auth via an Istio `ext_authz`
EnvoyFilter or oauth2-proxy sidecar, the `oauth2-proxy` HelmRepository is already
in `sources.yaml`), or at minimum restrict with an Istio `AuthorizationPolicy`.

### 2.2 Ambient mesh is installed but nothing is enrolled

istio-cni and ztunnel run cluster-wide (ambient profile), but no namespace carries
`istio.io/dataplane-mode: ambient` — so you pay the DaemonSet cost and get no mTLS
and no L4 policy. Either enroll namespaces (`kubectl label ns <ns>
istio.io/dataplane-mode=ambient` via the namespace manifests) and start using
`AuthorizationPolicy`, or drop the cni/ztunnel charts and keep Istio purely as an
ingress gateway. Both are reasonable; the current state is the worst of both.

### 2.3 No NetworkPolicies / AuthorizationPolicies at all

Everything in `default` can talk to everything, including to the Postgres
clusters and the 1Password Connect API in `onepass-system`. Even a couple of
coarse policies (deny ingress to `onepass-system` except from the operator;
restrict DB access to the owning app) would meaningfully contain a compromised
app pod. Ambient enrollment (2.2) is the natural way to get there with identity-
based policy instead of IP-based.

### 2.4 Almost everything runs in `default`

All but hermes/obsidian/openshell deploy to `namespace: default` (and k8up's
operator too). Per-app namespaces give you policy boundaries, per-namespace
ambient enrollment, cleaner `kubectl` ergonomics, and safer Flux pruning. The
kustomizations already set `namespace:` in one place each, so the migration is
mostly mechanical (plus moving Secrets/PVCs — do it app by app; note PVC contents
can't move namespaces, so pair it with a backup/restore or accept it for new apps
only).

### 2.5 Ansible `host_key_checking = False`

Convenient, but it disables the one defense SSH has against MITM on your own
LAN. Since the inventory is static, collect keys once
(`ssh-keyscan -H <hosts> >> ~/.ssh/known_hosts`) — could even be a small playbook —
and re-enable checking.

### 2.6 Pod security baseline

Most app deployments run with no `securityContext`. For the low-hanging fruit, add
`runAsNonRoot`, `readOnlyRootFilesystem` where images tolerate it, and
`allowPrivilegeEscalation: false`; consider labeling namespaces with Pod Security
Standards (`pod-security.kubernetes.io/warn: restricted`) to see what would break
before enforcing anything.

---

## 3. Reliability & observability

### 3.1 No alerting path exists

VMCluster + VMAgent + Grafana collect metrics, but there's no VMAlert, no
Alertmanager, and no notification target — so a dead node, full Longhorn volume,
failed backup, or CrashLooping pod is only discovered by looking. Suggested
minimal stack, all via the existing vm-operator:

- `VMAlert` + `VMAlertmanager` CRs in `flux/infrastructure/victoria-metrics/`.
- Route to ntfy/Pushover/email — or to your own **Matrix** server via a webhook
  bridge, which is pleasingly self-hosted.
- Start with a few rules: node down, PVC >85%, k8up backup failed
  (`k8up_jobs_failed_counter`), CNPG cluster unhealthy, cert expiring.

### 3.2 Flux has no notifications either

A failed HelmRelease upgrade currently fails silently until you run `flux get`.
Add a `notification.toolkit.fluxcd.io` `Provider` + `Alert` (matrix/webhook/ntfy)
for `Kustomization` and `HelmRelease` failures. Pairs well with Renovate: you
merge a bump, and you hear about it if it breaks.

### 3.3 kube-state-metrics is missing

VMAgent scrapes node-exporter and k8up, but without kube-state-metrics you have no
deployment/pod/PVC-level metrics, which is exactly what most useful alerts (3.1)
key on. The vm-operator converts Prometheus CRs, so the upstream
kube-state-metrics chart + a `VMServiceScrape` drops straight in.

### 3.4 Agents join the cluster through marmot-01 only

`api_endpoint` resolves to the first host in `k3s_servers` (192.168.2.111), and
every agent's systemd unit hardcodes `--server https://192.168.2.111:6443`. The
control plane is HA but its front door isn't: with marmot-01 down, agents can't
(re)register and `kubectl` from your kubeconfig fails. Fix options, in increasing
effort: a DNS record with all three IPs + `--tls-san`, a kube-vip/keepalived VIP
on the marmots, or the EdgeRouter load-balancing 6443.

### 3.5 Grafana is over-provisioned

3 replicas × 500m CPU requests = 1.5 cores reserved on a cluster of Elitedesks and
Pis, for a dashboard you look at occasionally. Postgres-backed Grafana is
stateless, so HA works — but 1–2 replicas at `cpu: 100m` is plenty here, and frees
real capacity for scheduling.

### 3.6 Single-instance CNPG clusters

`instances: 1` on Longhorn-replicated storage is a defensible trade-off, but note
CNPG's own guidance prefers `instances: 2-3` on non-replicated storage (Postgres
streaming replication beats block replication for failover time and avoids
double-replication overhead). Worth revisiting for the DBs you care most about
(immich, paperless) once backups (1.1) exist.

---

## 4. GitOps & repo hygiene

### 4.1 `mise lint-flux` is broken

The task runs `flux build kustomization application --kustomization-file
application.yaml`, but `flux/application.yaml` doesn't exist — apps are listed
individually in `flux/kustomization.yaml`. So the lint either fails or has been
failing silently. Either fix the task (loop over `flux/application/*/<app>.yaml`)
or restructure: a single `application.yaml` Flux Kustomization pointing at
`./flux/application` with a kustomization that includes each app would also shrink
the root `kustomization.yaml`.

### 4.2 No CI validates the manifests — but Renovate auto-opens PRs

The only Forgejo workflow is Renovate. Nothing runs `yamllint`, `ansible-lint`,
`flux build`, or `kubeconform` (which is in `mise.toml` but unused) on PRs, so a
bad Renovate bump or a typo merges straight to `main` and fails first inside the
cluster. A small `.forgejo/workflows/lint.yaml` running `mise lint` on
pull_request would catch most of it. This multiplies the value of every other
suggestion in this section.

### 4.3 A dozen images use `:latest`

`paperless-ngx`, `adguardhome`, `cloudflared`, `rsshub`, `browserless/chrome`,
`overseerr`, `sonarr`, `radarr`, `tubearchivist-es`, `pangolin-cli`, `alpine`
(storage-marten), etc. Consequences: Renovate can't manage them (your whole
update strategy is Renovate-shaped), pod restarts silently change versions, nodes
can run different versions simultaneously, and rollback is impossible. Pin each
to the current tag once; Renovate handles them forever after. Paperless and
AdGuard (schema-migrating apps on persistent data) are the riskiest ones today.

### 4.4 external-secrets is deployed but completely unused

Every secret in the repo is a 1Password-operator `OnePasswordItem`; there isn't a
single `ExternalSecret` or `ClusterSecretStore`. Meanwhile the 1Password
operator itself is installed imperatively (`bootstrap/onepass.sh`) outside GitOps.
Pick one:

- **Keep the 1Password operator**: delete the external-secrets HelmRelease (one
  less controller on the Pis), and move the connect/operator Helm install into a
  HelmRelease (token + credentials secret stay as the only bootstrap-time step).
- **Or migrate to ESO** with its 1Password Connect provider and drop the operator.

Either way the README's "External Secrets, 1Password Connect" row currently
overstates what's in use.

### 4.5 Dead weight

- `woodpecker` namespace + `woodpecker` and `langflow` HelmRepositories have no
  consumers — remove until needed (HelmRepositories poll hourly for nothing).
- `.stash/` k3s roles are superseded by `ansible/roles/k3s`.
- README hardware table is stale: missing `ocelot`, `falcon`, `junco`, and the
  k3s table doesn't reflect marten/numbat as agents; typos "Harware"/"debain".

### 4.6 HTTP→HTTPS redirect is inconsistent per-VirtualService

Some VS redirect port 80 (hermes, longhorn), some route port 80 to the backend
(marten-fallback), most don't mention it. Since the gRPC case made a blanket
`httpsRedirect: true` on the Gateway unsuitable (commit `0fe1ced`), consider the
inverse: enable `httpsRedirect` on the port-80 server of the Gateway and carve out
only the gRPC host on a separate server block — one rule plus one exception
instead of N copies.

### 4.7 Flux Kustomization health checks

App Kustomizations don't set `wait`/`healthChecks`/`timeout`, so Flux reports
`Ready` once manifests apply, even if the Deployment never becomes available.
Adding `wait: true` + `timeout: 5m` to app Kustomizations makes `flux get ks` (and
the notifications from 3.2) actually reflect app health.

---

## 5. Smaller ideas

- **Immich data on `hostPath` + `nodeSelector: marten`** is fine but invisible to
  k8s scheduling/capacity. Since storage-marten already defines NFS-ish PVs, a PV
  with `nodeAffinity` would document the constraint in one place instead of two.
- **`scripts/backup.sh`** could read app names dynamically (`kubectl get schedules`)
  instead of a hardcoded case list that's already missing calibre.
- **Renovate `packageRules`**: group the Istio charts (base/istiod/cni/ztunnel/
  gateway must move in lockstep) and the VM operator+CRDs so a partial merge can't
  skew versions. The CRDs in `flux/crds/vmoperator-crds.yaml` are a plain URL
  import — pin/automate that alongside the operator chart version.
- **Adguard as LAN DNS**: 2 replicas behind one Service is good; consider
  `externalTrafficPolicy: Local` + topology hints to keep DNS latency down, and
  pin the image (4.3) since DNS is the blast radius of the whole network.
- **Cloudflared replicas: 3** with `:latest` — pin it; also QUIC tunnels mean 2
  replicas is already fully redundant.
- **Document the network** (VLANs 192.168.2/3/4, BGP ASNs, what falcon/junco are)
  in the README or `docs/` — the inventory implies a topology only you currently
  hold in your head.

## Suggested order of attack

1. CNPG backups + k8up prune/check + paperless backup (1.1–1.3) — data loss is the
   only unrecoverable failure mode here.
2. Lock down openshell (2.1).
3. CI lint workflow + fix `mise lint-flux` (4.1, 4.2).
4. Alerting + Flux notifications + kube-state-metrics (3.1–3.3).
5. Pin `:latest` images (4.3).
6. Everything else as it itches.
