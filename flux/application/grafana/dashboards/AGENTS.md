# Grafana dashboard conventions

## Dashboard tags

Every dashboard must have a non-empty top-level `tags` array.

- Use exactly one tag per dashboard.
- The tag must be lowercase and match the app or system the dashboard covers.
- Keep the multi-line Grafana export format:

  ```json
  "tags": [
    "example"
  ],
  ```

- When adding a new dashboard, pick a single lowercase tag that identifies the
  component it monitors. Do not add datasource or vendor tags (e.g. avoid
  `prometheus`, `storage`, `k8s`).
