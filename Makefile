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
