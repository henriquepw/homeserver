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
update: down
	@for dir in servers/*; do \
		[ "$${dir}" = "servers/adguard" ] && continue; \
		echo ">>> Updating $$dir"; \
		docker compose -f "$${dir}/docker-compose.yml" \
		             --env-file .env \
		             pull; \
	done
	@$(MAKE) up
