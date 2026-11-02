# Runbooks

Each alert links here through its `runbook_url` annotation. The goal is the first
ten minutes: confirm the problem, limit impact, and know where to look next.

## InstanceDown

**Meaning:** Prometheus could not scrape a target for 2 minutes.

**First checks**
1. Is it one target or many? Many at once usually means Prometheus itself or the network.
2. `docker compose ps` — is the container running and healthy?
3. Open `http://localhost:9090/targets` and read the scrape error (timeout, connection refused, 404).

**Likely fixes**
- Container crashed: `docker compose logs <service>` and restart it.
- Wrong port or path after an upgrade: fix `prometheus/prometheus.yml` and `make reload`.

## EndpointDown

**Meaning:** A blackbox HTTP probe has failed for 3 minutes. Users are probably affected.

**First checks**
1. Query `probe_http_status_code{instance="<url>"}` and `probe_duration_seconds` in Prometheus.
2. Curl the URL from your machine and from inside the network:
   `docker compose exec blackbox-exporter wget -qO- "localhost:9115/probe?module=http_2xx&target=<url>&debug=true"`
3. Check DNS and TLS: a failing handshake shows up in the debug output.

**Likely fixes**
- Application down or failing health checks: see the service's own dashboards and logs.
- Upstream dependency (DNS, load balancer, certificate) broken: escalate to its owner.

## TLSCertificateExpiringSoon

**Meaning:** The certificate served at the endpoint expires in under 14 days.

**First checks**
1. Confirm the expiry date: `openssl s_client -connect host:443 -servername host </dev/null | openssl x509 -noout -enddate`.
2. Is the certificate managed automatically (cert-manager, ACME)? If yes, why did renewal not happen?

**Likely fixes**
- Fix the renewal job (rate limits, DNS challenge failures, expired credentials) and force a renewal.
- Manually issued certificates: start the renewal process now; it often needs other teams.

## HighCPUUsage

**Meaning:** Host CPU above 90% for 10 minutes.

**First checks**
1. Host overview dashboard → *Container CPU (top 10)* to find the consumer.
2. Is it expected load (batch job, traffic spike) or a runaway process?

**Likely fixes**
- Scale out or move the noisy workload; set CPU limits so one container can't starve the rest.

## HighMemoryUsage

**Meaning:** Host memory above 90% for 5 minutes. Next stop is the OOM killer.

**First checks**
1. Host overview → *Container memory (top 10)*. Look for steady growth (leak) vs a step change (deploy).
2. Check for recent `ContainerOOMKilled` alerts.

**Likely fixes**
- Restart a leaking service as mitigation, then open a bug with the memory graph attached.
- Add memory limits so the kernel kills the offender instead of something important.

## DiskWillFillIn4Hours

**Meaning:** At the current rate, the filesystem will be full within 4 hours, and it is already under 25% free.

**First checks**
1. `df -h` and `du -xh --max-depth=1 <mountpoint> | sort -h | tail` on the host.
2. Usual suspects: container logs, Docker images and build cache, application logs, database WAL.

**Likely fixes**
- `docker system df` then prune unused images and build cache.
- Rotate or compress logs; cap Docker log size (this stack uses `max-size: 10m`).
- If growth is legitimate data, extend the volume.

## ContainerOOMKilled

**Meaning:** A container hit its memory limit and the kernel killed it.

**First checks**
1. `docker inspect <container> --format '{{.State.OOMKilled}} {{.HostConfig.Memory}}'`
2. Compare the memory graph before the kill with the limit.

**Likely fixes**
- Limit too tight for normal load: raise it.
- Memory grows until killed: treat as a leak; restarts only buy time.

## HighHTTP5xxRate

**Meaning:** More than 5% of requests to a service return 5xx for 5 minutes.

**First checks**
1. Service RED dashboard → *Requests by status* and *Requests by route*: one route or all?
2. Logs panel on the same dashboard, filter for `error`.
3. Did a deploy just happen? Check the image tag and its CI run.

**Likely fixes**
- Bad deploy: roll back first, debug second.
- Dependency failure: check the dependency's health; fail fast and shed load if needed.

## HighLatencyP95

**Meaning:** p95 latency above 500ms for 10 minutes.

**First checks**
1. Is traffic higher than usual (*Request rate*)? Is CPU saturated?
2. Is p50 also up (everything slow) or only p95/p99 (a slow subset, often one route or dependency)?

**Likely fixes**
- Scale out if saturated.
- Find the slow route and its dependency; add timeouts so slowness doesn't cascade.
