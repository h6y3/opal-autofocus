PREFIX ?= $(HOME)/.local
BIN := $(PREFIX)/bin/opal-autofocus
LABEL := com.opal-autofocus.agent
PLIST := $(HOME)/Library/LaunchAgents/$(LABEL).plist
LOGDIR := $(HOME)/Library/Logs/opal-autofocus
USERID := $(shell id -u)

.PHONY: build test install uninstall smoke clean

build:
	swift build -c release

test:
	scripts/swift-test

install: build
	install -d "$(PREFIX)/bin" "$(HOME)/Library/LaunchAgents" "$(LOGDIR)"
	install -m 755 .build/release/opal-autofocus "$(BIN)"
	sed -e 's|@BIN@|$(BIN)|g' -e 's|@HOME@|$(HOME)|g' packaging/$(LABEL).plist > "$(PLIST)"
	@launchctl bootout gui/$(USERID)/$(LABEL) 2>/dev/null || true
	launchctl bootstrap gui/$(USERID) "$(PLIST)"
	@echo "installed $(BIN) and loaded $(LABEL); logs in $(LOGDIR)/agent.log"

uninstall:
	@launchctl bootout gui/$(USERID)/$(LABEL) 2>/dev/null || true
	rm -f "$(PLIST)" "$(BIN)"
	@echo "removed $(LABEL) and $(BIN)"

smoke: build
	BIN=.build/release/opal-autofocus scripts/smoke.sh

clean:
	rm -rf .build
