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

# --- Tdarr native node (macOS, VideoToolbox HW encode) ---
# The Tdarr *server* runs in Docker (servers/watcher). This node runs natively on
# macOS so it can use VideoToolbox hardware encoding, which Docker/Linux can't reach.
# The standalone node is configured via env vars (the JSON config file is ignored).
# nodeType=mapped because the container mounts media at the same host path
# (${MEDIA_DIR}:${MEDIA_DIR}), so node and server see identical paths.
# Keep TDARR_VERSION in sync with the server image (grep AppVersion in its logs).
TDARR_VERSION     ?= 2.82.02
TDARR_NODE_DIR    ?= /Volumes/server/apps/tdarr-node
TDARR_SERVER_URL  ?= http://127.0.0.1:9961
TDARR_NODE_NAME   ?= mac-m4-hw
TDARR_NODE_URL     = https://storage.tdarr.io/versions/$(TDARR_VERSION)/darwin_arm64/Tdarr_Node.zip

.PHONY: tdarr-node-install
tdarr-node-install:
	@mkdir -p "$(TDARR_NODE_DIR)"
	@echo ">>> Downloading Tdarr_Node $(TDARR_VERSION) (macOS arm64)"
	@curl -fL "$(TDARR_NODE_URL)" -o "$(TDARR_NODE_DIR)/Tdarr_Node.zip"
	@echo ">>> Extracting"
	@cd "$(TDARR_NODE_DIR)" && unzip -oq Tdarr_Node.zip && rm -f Tdarr_Node.zip
	@xattr -dr com.apple.quarantine "$(TDARR_NODE_DIR)" 2>/dev/null || true
	@chmod +x "$(TDARR_NODE_DIR)/Tdarr_Node" 2>/dev/null || true
	@echo ">>> Done. Start with: make tdarr-node-up"

.PHONY: tdarr-node-up
tdarr-node-up:
	@if [ -f "$(TDARR_NODE_DIR)/node.pid" ] && kill -0 "$$(cat $(TDARR_NODE_DIR)/node.pid)" 2>/dev/null; then \
		echo ">>> Tdarr node already running (pid $$(cat $(TDARR_NODE_DIR)/node.pid))"; \
	else \
		echo ">>> Starting Tdarr node -> $(TDARR_SERVER_URL)"; \
		nohup sh -c 'cd "$(TDARR_NODE_DIR)" && exec env serverURL="$(TDARR_SERVER_URL)" nodeName="$(TDARR_NODE_NAME)" nodeType=mapped ./Tdarr_Node' > "$(TDARR_NODE_DIR)/node.log" 2>&1 & \
		echo $$! > "$(TDARR_NODE_DIR)/node.pid"; \
		echo ">>> Started (pid $$(cat $(TDARR_NODE_DIR)/node.pid)). Logs: make tdarr-node-logs"; \
	fi

.PHONY: tdarr-node-down
tdarr-node-down:
	@if [ -f "$(TDARR_NODE_DIR)/node.pid" ] && kill "$$(cat $(TDARR_NODE_DIR)/node.pid)" 2>/dev/null; then \
		echo ">>> Stopped"; \
	else \
		echo ">>> Node not running (no valid node.pid)"; \
	fi
	@rm -f "$(TDARR_NODE_DIR)/node.pid"

.PHONY: tdarr-node-status
tdarr-node-status:
	@if [ -f "$(TDARR_NODE_DIR)/node.pid" ] && kill -0 "$$(cat $(TDARR_NODE_DIR)/node.pid)" 2>/dev/null; then \
		echo ">>> Tdarr node running (pid $$(cat $(TDARR_NODE_DIR)/node.pid))"; \
	else \
		echo ">>> Tdarr node not running"; \
	fi

.PHONY: tdarr-node-logs
tdarr-node-logs:
	@tail -f "$(TDARR_NODE_DIR)/node.log"

.PHONY: tdarr-node-restart
tdarr-node-restart:
	@$(MAKE) tdarr-node-down
	@$(MAKE) tdarr-node-up

# Optional: run the node as a launchd service (starts at login, auto-restarts on crash).
# Use EITHER the manual targets above (up/down/restart) OR the service targets below,
# not both at once. service-install stops any manual instance first.
#
# IMPORTANT (macOS): a LaunchAgent is denied access to external volumes by default,
# so the node will crashloop with EX_CONFIG (78) until you grant Full Disk Access to
# the binary: System Settings > Privacy & Security > Full Disk Access > add
# $(TDARR_NODE_DIR)/Tdarr_Node. Terminal-launched targets (up/down) work without this
# because they inherit Terminal's granted access.
TDARR_PLIST_LABEL ?= io.tdarr.node
TDARR_PLIST       ?= $(HOME)/Library/LaunchAgents/$(TDARR_PLIST_LABEL).plist

.PHONY: tdarr-node-service-install
tdarr-node-service-install:
	@$(MAKE) tdarr-node-down >/dev/null 2>&1 || true
	@mkdir -p "$(HOME)/Library/LaunchAgents"
	@echo ">>> Writing LaunchAgent $(TDARR_PLIST)"
	@printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'  <key>Label</key><string>$(TDARR_PLIST_LABEL)</string>' \
		'  <key>ProgramArguments</key>' \
		'  <array><string>$(TDARR_NODE_DIR)/Tdarr_Node</string></array>' \
		'  <key>WorkingDirectory</key><string>$(TDARR_NODE_DIR)</string>' \
		'  <key>EnvironmentVariables</key>' \
		'  <dict>' \
		'    <key>serverURL</key><string>$(TDARR_SERVER_URL)</string>' \
		'    <key>nodeName</key><string>$(TDARR_NODE_NAME)</string>' \
		'    <key>nodeType</key><string>mapped</string>' \
		'  </dict>' \
		'  <key>RunAtLoad</key><true/>' \
		'  <key>KeepAlive</key><true/>' \
		'  <key>StandardOutPath</key><string>$(TDARR_NODE_DIR)/node.log</string>' \
		'  <key>StandardErrorPath</key><string>$(TDARR_NODE_DIR)/node.log</string>' \
		'</dict>' \
		'</plist>' > "$(TDARR_PLIST)"
	@launchctl unload "$(TDARR_PLIST)" 2>/dev/null || true
	@launchctl load -w "$(TDARR_PLIST)"
	@echo ">>> Service loaded (RunAtLoad + KeepAlive). Check: launchctl list | grep tdarr"

.PHONY: tdarr-node-service-uninstall
tdarr-node-service-uninstall:
	@launchctl unload "$(TDARR_PLIST)" 2>/dev/null || true
	@rm -f "$(TDARR_PLIST)"
	@echo ">>> Service removed"
