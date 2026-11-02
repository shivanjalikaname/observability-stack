PROMETHEUS_IMAGE := prom/prometheus:v3.5.0
ALERTMANAGER_IMAGE := prom/alertmanager:v0.28.1

.PHONY: up demo down logs ps reload validate test-rules clean

up:            ## Start the core stack
	docker compose up -d

demo:          ## Start the stack plus the demo service and traffic generator
	docker compose --profile demo up -d

down:          ## Stop everything (keeps data volumes)
	docker compose --profile demo down

logs:          ## Follow logs for all services
	docker compose logs -f --tail=50

ps:
	docker compose ps

reload:        ## Hot-reload Prometheus and Alertmanager after editing config
	curl -fsS -X POST http://localhost:9090/-/reload && echo "prometheus reloaded"
	curl -fsS -X POST http://localhost:9093/-/reload && echo "alertmanager reloaded"

validate: test-rules  ## Run the same checks as CI
	docker run --rm -v "$(CURDIR)/prometheus:/etc/prometheus:ro" --entrypoint promtool $(PROMETHEUS_IMAGE) \
		check config /etc/prometheus/prometheus.yml
	docker run --rm -v "$(CURDIR)/alertmanager:/etc/alertmanager:ro" --entrypoint amtool $(ALERTMANAGER_IMAGE) \
		check-config /etc/alertmanager/alertmanager.yml
	GRAFANA_ADMIN_PASSWORD=validate docker compose --profile demo config -q && echo "compose ok"

test-rules:    ## Unit-test alert rules with promtool
	docker run --rm -v "$(CURDIR):/repo:ro" -w /repo/tests --entrypoint promtool $(PROMETHEUS_IMAGE) \
		test rules alerts_test.yml

clean:         ## Stop everything and delete all stored metrics, logs and dashboards state
	docker compose --profile demo down -v
