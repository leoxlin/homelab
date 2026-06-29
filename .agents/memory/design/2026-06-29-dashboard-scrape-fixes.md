# Grafana dashboard and VictoriaMetrics scrape fixes

Date: 2026-06-29
Scope: Fixes shipped for failing Grafana dashboards in `flux/application/grafana` and their underlying scrape configs in `flux/application/victoria-metrics/scrapes.yaml`. Changes are applied to the live cluster but not yet committed to Git.

## Root causes found

1. **MetalLB metrics unreachable** (`scrape.yaml:93-166`)
   - MetalLB 0.16.1 controller/speaker expose secure metrics on container port `9120` (`metricshttps`), but the Services targeted `7472`.
   - The `VMServiceScrape` used plain HTTP, no bearer token, and no TLS config.

2. **Flux controllers not scraped** (`scrape.yaml:213-229`)
   - Flux pods expose metrics on port `8080` named `http-prom`, but no Service exposes that port.
   - The `VMServiceScrape` selected Services and asked for port `http-prom`, so it matched nothing.

3. **prometheus-annotations scoped to monitoring only** (`scrape.yaml:186-211`)
   - `namespaceSelector: {}` was interpreted as "own namespace" (`monitoring`), missing annotated pods in `istio-system`, `cert-manager`, etc.

4. **kubernetes-cluster dashboard obsolete** (`dashboards/kubernetes-cluster.json`)
   - Grafana 5.2 / `schemaVersion: 16` with deprecated `singlestat`/`graph` panels.
   - Queries used pre-1.16 cAdvisor labels (`pod_name`, `container_name`) and expected `nginx_connections_total` which is not scraped.

5. **Flux cluster dashboard used old metric names** (`dashboards/flux-cluster.json`)
   - Queried `gotk_resource_info` and `gotk_reconcile_duration_seconds_*`.
   - Flux operator v0.38.1 exposes `flux_resource_info` and `flux_reconcile_duration_seconds_*`; `customresource_kind` is now `kind`.

6. **Istio mesh/service/workload dashboards need sidecars/waypoints**
   - Cluster runs Istio ambient mode (`ztunnel`, `istiod`, CNI). No application pods have `istio-proxy` sidecars, so `istio_requests_total` and sidecar CPU/memory metrics do not exist.
   - `istio-control-plane` already worked; `istio-ztunnel` works once ztunnel is scraped.

## Changes made

- `flux/application/victoria-metrics/scrapes.yaml`
  - MetalLB Services: `port`/`targetPort` `7472` → `9120`.
  - MetalLB `VMServiceScrapes`: add `scheme: https`, `tlsConfig.insecureSkipVerify: true`, `bearerTokenFile`.
  - `flux-system` `VMServiceScrape` → `VMPodScrape` selecting pods with `app.kubernetes.io/part-of: flux` in `flux-system` namespace.
  - `prometheus-annotations` `VMPodScrape`: `namespaceSelector: {}` → `namespaceSelector: { any: true }`.

- `flux/application/grafana/dashboards/kubernetes-cluster.json`
  - Replaced with dotdc `k8s-views-global.json` (Grafana.com ID 15757), `schemaVersion: 39`.
  - Retained old UID `os6Bh8Omk` and title `Kubernetes Cluster` so existing links/URLs stay valid.
  - Datasource pinned to `vm-prom`.

- `flux/application/grafana/dashboards/flux-cluster.json`
  - Renamed metrics: `gotk_resource_info` → `flux_resource_info`, `gotk_reconcile_duration_seconds_*` → `flux_reconcile_duration_seconds_*`.
  - Renamed labels/columns: `customresource_kind` → `kind`, `gotk_type` → `kind`.

## Verification (live cluster)

- `mise lint` and `mise lint-flux` pass.
- Applied manifests with `kubectl kustomize` + `kubectl apply --server-side` (required for the large dashboard ConfigMap).
- Confirmed healthy targets via `up`:
  - `metallb-controller-metrics`: 1/1 up on `10.42.1.116:9120`
  - `metallb-speaker-metrics`: 8/8 up
  - `monitoring/flux-system`: 6/6 Flux controllers up
  - `ztunnel`: 8/8 up
  - `cert-manager`, `cainjector`, `webhook`, `istio-cni`, `flux-operator` up via `prometheus-annotations`
- Dashboard queries return data for Kubernetes Cluster, MetalLB, Flux Control Plane, Flux Cluster Stats, and Istio Ztunnel.

## Remaining gaps

- `istio-mesh`, `istio-service`, `istio-workload`, and `istio-performance` dashboards remain mostly empty because the cluster uses ambient mode without L7 waypoints or sidecars. Fixing them requires deploying Istio waypoint proxies or enabling sidecar injection for workloads.

## Next step

Commit and push the three modified files so Flux reconciliation makes the fixes persistent. Without a commit, the manually applied Service changes and dashboard ConfigMap will be reverted on the next Flux reconcile.
