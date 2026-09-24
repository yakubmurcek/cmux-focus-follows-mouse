SHELL := /bin/bash
PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/share/cmux-focus-follows-mouse
LINKDIR ?= $(PREFIX)/bin
PLIST_DIR ?= $(HOME)/Library/LaunchAgents
PLIST_LABEL ?= com.yakub.cmux-focus-follows-mouse
PLIST_FILE ?= $(PLIST_DIR)/$(PLIST_LABEL).plist

SWIFTC ?= swiftc
SWIFTFLAGS ?= -O

.PHONY: all build install uninstall doctor clean reload

all: build

build: cmux-ffm

cmux-ffm: Sources/main.swift
	@echo "Compiling cmux-ffm..."
	$(SWIFTC) $(SWIFTFLAGS) -o $@ $<
	@echo "Build successful: ./cmux-ffm"

install: build
	@echo "Installing to $(BINDIR)..."
	@mkdir -p "$(BINDIR)" "$(LINKDIR)" "$(PLIST_DIR)"
	@cp cmux-ffm "$(BINDIR)/cmux-ffm"
	@ln -sf "$(BINDIR)/cmux-ffm" "$(LINKDIR)/cmux-ffm"
	@echo "Configuring LaunchAgent at $(PLIST_FILE)..."
	@sed "s|{{BINARY_PATH}}|$(BINDIR)/cmux-ffm|g; s|{{LABEL}}|$(PLIST_LABEL)|g" \
		launchd/$(PLIST_LABEL).plist.template > "$(PLIST_FILE)"
	@echo "Registering with launchd..."
	@launchctl bootout "gui/$$(id -u)/$(PLIST_LABEL)" 2>/dev/null || true
	@launchctl bootstrap "gui/$$(id -u)" "$(PLIST_FILE)"
	@echo "✓ cmux-ffm installed and running."

uninstall:
	@echo "Stopping LaunchAgent..."
	@launchctl bootout "gui/$$(id -u)/$(PLIST_LABEL)" 2>/dev/null || true
	@rm -f "$(PLIST_FILE)"
	@rm -f "$(LINKDIR)/cmux-ffm"
	@rm -rf "$(BINDIR)"
	@echo "✓ cmux-ffm uninstalled."

reload:
	@launchctl bootout "gui/$$(id -u)/$(PLIST_LABEL)" 2>/dev/null || true
	@launchctl bootstrap "gui/$$(id -u)" "$(PLIST_FILE)"
	@echo "✓ cmux-ffm reloaded."

doctor: build
	@./cmux-ffm --doctor

clean:
	@rm -rf cmux-ffm .build
	@echo "✓ Cleaned build artifacts."
