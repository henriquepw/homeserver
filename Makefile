# Makefile

ENV_FILE = .env
DC       = docker compose --env-file $(ENV_FILE)
NGINX    = servers/nginx/compose.yml

# Reads one var out of .env. Targeted on purpose: `include .env` would let make
# interpret $ and # inside secrets.
env-var = $(shell grep -E '^$(1)=' $(ENV_FILE) | tail -1 | cut -d= -f2- | tr -d '\42\47')

APPS_DIR   = $(call env-var,APPS_DIR)
DOMAIN     = $(call env-var,DOMAIN)
ACME_EMAIL = $(call env-var,ACME_EMAIL)
WILDCARD   = *.$(DOMAIN)

# Shared exposure network, declared `external: true` by every stack. Backends
# stay on their own stack's internal network.
.PHONY: network
network:
	@docker network inspect dnet >/dev/null 2>&1 || docker network create dnet

# nginx goes up last, down first. Order is cosmetic — the real robustness comes
# from the resolver + variable proxy_pass in nginx.conf.
.PHONY: up
up: network
	@for dir in servers/*; do \
		[ "$$dir" = "servers/nginx" ] && continue; \
		echo ">>> Starting $$dir"; \
		$(DC) -f "$${dir}/compose.yml" up -d; \
	done
	@echo ">>> Starting servers/nginx"
	@$(DC) -f $(NGINX) up -d

.PHONY: down
down:
	@echo ">>> Stopping servers/nginx"
	@$(DC) -f $(NGINX) down --remove-orphans
	@for dir in servers/*; do \
		[ "$$dir" = "servers/nginx" ] && continue; \
		echo ">>> Stopping $$dir"; \
		$(DC) -f "$${dir}/compose.yml" down --remove-orphans; \
	done

.PHONY: update
update: network
	@for dir in servers/*; do \
		[ "$$dir" = "servers/nginx" ] && continue; \
		echo ">>> Updating $$dir"; \
		$(DC) -f "$${dir}/compose.yml" pull; \
		$(DC) -f "$${dir}/compose.yml" up -d; \
	done
	@echo ">>> Updating servers/nginx"
	@$(DC) -f $(NGINX) pull
	@$(DC) -f $(NGINX) up -d

# --- Wildcard cert (acme.sh + Cloudflare DNS-01) ---
# Idempotent and deliberately not a dependency of `up`: issuing hits the
# Cloudflare API. On a fresh machine: `make certs && make up`. Needs CF_Token.
.PHONY: check-acme-env
check-acme-env:
	@[ -n "$(DOMAIN)" ]     || { echo "DOMAIN missing from $(ENV_FILE)"; exit 1; }
	@[ -n "$(ACME_EMAIL)" ] || { echo "ACME_EMAIL missing from $(ENV_FILE)"; exit 1; }
	@[ -n "$(APPS_DIR)" ]   || { echo "APPS_DIR missing from $(ENV_FILE)"; exit 1; }

.PHONY: certs
certs: network check-acme-env
	@echo ">>> Registering ACME account ($(ACME_EMAIL)) if needed"
	@$(DC) -f $(NGINX) run --rm acme \
		--register-account --server letsencrypt -m $(ACME_EMAIL) || true
	@echo ">>> Issuing $(WILDCARD) via Cloudflare DNS-01"
	@$(DC) -f $(NGINX) run --rm acme \
		--issue --server letsencrypt --dns dns_cf -d '$(WILDCARD)' --keylength ec-256; \
		rc=$$?; if [ $$rc -ne 0 ] && [ $$rc -ne 2 ]; then exit $$rc; fi
	@$(MAKE) certs-install

.PHONY: certs-force
certs-force: network check-acme-env
	@$(DC) -f $(NGINX) run --rm acme \
		--issue --force --server letsencrypt --dns dns_cf -d '$(WILDCARD)' --keylength ec-256
	@$(MAKE) certs-install

.PHONY: certs-install
certs-install:
	@echo ">>> Installing cert into $(APPS_DIR)/nginx/certs"
	@$(DC) -f $(NGINX) run --rm acme \
		--install-cert -d '$(WILDCARD)' --ecc \
		--key-file /certs/privkey.pem \
		--fullchain-file /certs/fullchain.pem

.PHONY: certs-info
certs-info:
	@openssl x509 -in "$(APPS_DIR)/nginx/certs/fullchain.pem" \
		-noout -subject -ext subjectAltName -dates

# --- FileFlows native node (macOS, VideoToolbox HW encode) ---
# The FileFlows *server* runs in Docker (servers/watcher). This node runs natively
# on macOS so it can use VideoToolbox hardware encoding, which Docker/Linux can't
# reach. It's installed from the official Homebrew tap, which pulls in dotnet@10 and
# registers a launchd service via `brew services` (runs as your user, RunAtLoad +
# KeepAlive). The container mounts media at the same host path (${MEDIA_DIR}:${MEDIA_DIR}),
# so node and server see identical paths and no per-node path mapping is needed.
FF_NODE_NAME    ?= mac-m4-hw
FF_SERVER_URL   ?= http://127.0.0.1:9960
FF_NODE_BASE    ?= $(HOME)/Library/Application Support/FileFlowsNode
FF_NODE_CONFIG   = $(FF_NODE_BASE)/Data/node.config

.PHONY: fileflows-node-install
fileflows-node-install:
	@echo ">>> Tapping fileflows/tap and installing fileflows-node (+ dotnet@10)"
	@brew tap fileflows/tap
	@brew install fileflows-node
	@$(MAKE) fileflows-node-configure
	@echo ">>> Done. Start with: make fileflows-node-up"

# Writes node.config non-interactively (same JSON the `fileflows-node --configure`
# prompt produces). HostName is the node name shown in the FileFlows UI.
.PHONY: fileflows-node-configure
fileflows-node-configure:
	@mkdir -p "$(FF_NODE_BASE)/Data"
	@echo ">>> Writing $(FF_NODE_CONFIG) (server $(FF_SERVER_URL), node $(FF_NODE_NAME))"
	@printf '%s\n' \
		'{' \
		'  "ServerUrl": "$(FF_SERVER_URL)",' \
		'  "AccessToken": "",' \
		'  "HostName": "$(FF_NODE_NAME)"' \
		'}' > "$(FF_NODE_CONFIG)"

# IMPORTANT (macOS): a launchd agent is denied access to external volumes by default,
# so if media lives on an external volume (e.g. /Volumes/server) the node will fail to
# read files until you grant Full Disk Access to the dotnet runtime it runs:
# System Settings > Privacy & Security > Full Disk Access > add
# /opt/homebrew/opt/dotnet@10/bin/dotnet (or run `fileflows-node` from Terminal, which
# inherits Terminal's granted access, to test first).
.PHONY: fileflows-node-up
fileflows-node-up:
	@echo ">>> Starting fileflows-node service -> $(FF_SERVER_URL)"
	@brew services start fileflows-node

.PHONY: fileflows-node-down
fileflows-node-down:
	@brew services stop fileflows-node

.PHONY: fileflows-node-restart
fileflows-node-restart:
	@brew services restart fileflows-node

.PHONY: fileflows-node-status
fileflows-node-status:
	@brew services info fileflows-node

.PHONY: fileflows-node-logs
fileflows-node-logs:
	@tail -f "$(FF_NODE_BASE)/Logs/"*.log 2>/dev/null || echo ">>> No logs yet at $(FF_NODE_BASE)/Logs"

.PHONY: fileflows-node-uninstall
fileflows-node-uninstall:
	@brew services stop fileflows-node 2>/dev/null || true
	@brew uninstall fileflows-node 2>/dev/null || true
	@echo ">>> fileflows-node removed. Data kept at $(FF_NODE_BASE) (delete manually if desired)."
