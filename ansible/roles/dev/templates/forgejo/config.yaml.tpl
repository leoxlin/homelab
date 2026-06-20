log:
  level: info
  job_level: info

runner:
  file: .runner
  capacity: 1
  envs: {}
  env_file: .env
  timeout: 3h
  shutdown_timeout: 3h
  insecure: false
  fetch_timeout: 30s
  fetch_interval: 2s
  report_interval: 1s
  # report_retry:
  labels:
    - docker:docker://node:22-trixie

cache:
  enabled: true
  port: 0
  dir: ""
  external_server: ""
  secret: ""
  secret_url: ""
  host: ""
  proxy_port: 0
  actions_cache_url_override: ""

container:
  network: ""
  enable_ipv6: false
  privileged: false
  options:
  workdir_parent:
  valid_volumes: []
  docker_host: "unix:///var/run/docker.sock"
  force_pull: false
  force_rebuild: false

host:
  workdir_parent:

server:
  connections:
    forgejo:
      url: https://git.hydrahmlb.dev/
      uuid: "{{ op://Hydra/dev.forgejo-actions/uuid }}"
      token: "{{ op://Hydra/dev.forgejo-actions/token }}"
