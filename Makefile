# Версия берётся из ssh-monitor (SSH_MONITOR_VERSION).
.PHONY: dist clean-dist
VERSION := $(shell sed -n 's/^SSH_MONITOR_VERSION="\(.*\)".*/\1/p' ssh-monitor | head -n1)
DIST := ssh-monitor-$(VERSION).tar.gz

dist: $(DIST)

$(DIST): ssh-monitor
	git archive --format=tar.gz --prefix=ssh-monitor-$(VERSION)/ -o $(DIST) HEAD

clean-dist:
	rm -f ssh-monitor-*.tar.gz
