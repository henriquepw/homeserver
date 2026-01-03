# Makefile
.PHONY: up down

up:
	@set -e; for dir in servers/*; do \
		echo ">>> Starting $$dir"; \
		docker compose -f "$${dir}/docker-compose.yml" \
		             --env-file .env \
		             up -d --quiet-pull --remove-orphans; \
	done

down:
	@set -e; for dir in servers/*; do \
		echo ">>> Stopping $$dir"; \
		docker compose -f "$${dir}/docker-compose.yml" \
		             --env-file .env.prod \
		             down --remove-orphans; \
	done
