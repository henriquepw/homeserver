# Makefile

.PHONY: up
up:
	@for dir in servers/*; do \
		echo ">>> Starting $$dir"; \
		docker compose -f "$${dir}/compose.yml" --env-file .env up -d; \
	done

.PHONY: down
down:
	@for dir in servers/*; do \
		echo ">>> Stopping $$dir"; \
		docker compose -f "$${dir}/compose.yml" \
		             --env-file .env \
		             down --remove-orphans; \
	done

.PHONY: update
update:
	@for dir in servers/*; do \
		echo ">>> Updating $$dir"; \
		docker compose -f "$${dir}/compose.yml" --env-file .env pull; \
		docker compose -f "$${dir}/compose.yml" --env-file .env up -d; \
	done
