# Docker pull-through cache on falcon — speed & cleanup

Date: 2026-06-14
Scope: investigation/recommendations only (no changes shipped). Covers the registry
pull-through cache on falcon, how the k3s cluster consumes it, and how to make pulls
faster and keep the S3 backing store from growing forever.

## Current architecture

- **falcon (`192.168.4.10`)** runs three `registry:3` containers as pull-through caches
  (`ansible/roles/dev/templates/docker-registry/compose.yaml`):
  - `5001` → `docker.io` (`REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io`)
  - `5002` → `ghcr.io`
  - `5003` → `quay.io`
- All three back onto **Backblaze B2 S3** (`eu-central-003`,
  `s3.eu-central-003.backblazeb2.com`), each in its own `rootdirectory`
  (`/registry-docker`, `/registry-ghcr`, `/registry-quay`). Bucket/keys come from
  1Password (`op://Hydra/dev.docker-registry/*`) via `.env.tpl`. htpasswd auth.
- Exposed publicly through **Cloudflare Tunnel** as `docker/ghcr/quay.hydrahmlb.dev`
  (`cloudflare-tunnel` stack).
- k3s containerd consumes them via `registries.yaml`
  (`flux/infrastructure/registry-mirrors/configmap.yaml` → rendered by the
  `registry-mirrors` DaemonSet into `/etc/rancher/k3s/registries.yaml`). Endpoints point
  at the **public Cloudflare hostnames first**, upstream second.
- Port `5001` is firewalled open for `192.168.0.0/16` in
  `ansible/roles/k3s/tasks/prereq.yaml` with comment `SPEGEL`, but `--embedded-registry`
  is **not** in `k3s_extra_server_args` (`ansible/roles/k3s/defaults/main.yaml`), so
  Spegel is not actually enabled.
- k3s nodes (marmot/pika) are on `192.168.2.x`; falcon is on `192.168.4.x` — different
  subnet, both private/routable.

### Two config gaps

- **No `REGISTRY_PROXY_TTL`** → cached content never expires.
- **No `REGISTRY_STORAGE_DELETE_ENABLED=true`** → deletion API is off, so neither TTL
  eviction nor garbage collection can remove anything from S3. Today the cache only
  grows.

## 1. Faster pulls

Ordered biggest win first.

### 1.1 Pull over LAN, not through Cloudflare

The k3s nodes resolve `docker.hydrahmlb.dev` and go out to the internet → Cloudflare edge
→ back through the tunnel to falcon, even though falcon is on the same network. Every
"cache hit" is a WAN round trip. Point the mirror endpoints at falcon directly (keep the
public hostname + upstream as fallbacks):

```yaml
mirrors:
  docker.io:
    endpoint:
      - "http://192.168.4.10:5001"      # LAN, direct
      - "https://docker.hydrahmlb.dev"  # fallback
      - "https://registry-1.docker.io"
```

Do the same for ghcr (5002) and quay (5003); open 5002/5003 in `prereq.yaml` like 5001.
The existing `from_ip: 192.168.0.0/16` rule shows direct reachability is intended. This
is the single biggest win.

### 1.2 Enable k3s embedded registry mirror (Spegel)

Add `--embedded-registry` to `k3s_extra_server_args` (firewall already prepped for it).
Once any node has an image, peers pull it over the LAN from that node instead of
re-fetching — the "best-effort cache after k8s has finished" behavior. P2P within the
cluster, complements the falcon cache.

### 1.3 S3 is the latency floor for cache misses

Because blobs live in Backblaze, even a cache "hit" streams from B2 over the internet.
For a *regenerable* pull-through cache, local disk (or a local-disk cache fronting S3) is
much faster; the only trade-off is durability across container rebuilds, which doesn't
matter for a disposable cache. Consider switching the cache rootdirectory to local disk
if pulls still feel slow after 1.1/1.2.

## 2. Automatic S3 cleanup (best-effort, no cron)

Built into the registry once deletes are enabled. Add to each registry's compose env:

```yaml
- REGISTRY_STORAGE_DELETE_ENABLED=true
- REGISTRY_PROXY_TTL=168h          # evict content not pulled in 7 days
```

The proxy scheduler purges manifests/blobs not *accessed* within the TTL — hands-off, no
cron. It tracks pulls, not "what k8s runs", but anything still deployed gets re-pulled
and stays warm. Enough on its own for most cases.

To actually reclaim blob storage in S3 (TTL expires manifest references; GC frees the
orphaned blobs), run periodically on falcon, with the registry read-only/stopped to avoid
races:

```console
registry garbage-collect --delete-untagged /etc/distribution/config.yml
```

Natural home: a **weekly systemd timer in the `dev` role on falcon** that stops the three
containers, runs GC against each config, and restarts them.

## 3. Cron to reconcile k8s-deployed images vs. cache

Heaviest option. GC must run on falcon (CLI against storage, not an HTTP API), so a
host-level timer on falcon is the natural home, not a k8s CronJob. Flow:

1. Query the k8s API (kubeconfig on falcon) for in-use images + digests:
   `kubectl get pods -A -o jsonpath` over `.spec.{containers,initContainers}[*].image`
   and `.status.containerStatuses[*].imageID`.
2. Enumerate each cache via HTTP API: `GET /v2/_catalog`, `/v2/<repo>/tags/list`, resolve
   digests.
3. `DELETE /v2/<repo>/manifests/<digest>` for anything not in the deployed set (needs
   `delete.enabled`).
4. Run `registry garbage-collect` to free the unreferenced blobs.

## Recommendation

Start with section 2 (TTL + delete + weekly GC) — ~4 lines of config + one timer, no
kubeconfig-on-falcon, no enumeration script to maintain; gets ~90% of the cleanup. Pair
with 1.1 and 1.2 for speed. Only build the full reconcile (section 3) if TTL leaves too
much or you want delete-on-undeploy precision.

Suggested change bundle (all touch stateful pieces — land as a reviewed change, run
`mise lint-flux` / `mise lint-ansible`):

- LAN mirror endpoints in `registry-mirrors/configmap.yaml` (+ open 5002/5003 in
  `prereq.yaml`)
- `--embedded-registry` in k3s server args
- `DELETE_ENABLED` + `PROXY_TTL` on the three registries in `compose.yaml`
- weekly GC systemd timer in the `dev` role on falcon
