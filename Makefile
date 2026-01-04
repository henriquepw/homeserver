# Makefile
.PHONY: up down

up:
	@for dir in servers/*; do \
		echo ">>> Starting $$dir"; \
		docker compose -f "$${dir}/docker-compose.yml" --env-file .env up -d; \
	done

down:
	@for dir in servers/*; do \
		echo ">>> Stopping $$dir"; \
		docker compose -f "$${dir}/docker-compose.yml" --env-file .env down; \
	done
