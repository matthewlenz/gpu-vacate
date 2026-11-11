# gpu-vacate. `sudo make install` installs and activates it. With DESTDIR set (for
# packages), only the files are installed.
PREFIX       ?= /usr/local
BINDIR       ?= $(PREFIX)/bin
SYSCONFDIR   ?= /etc
UDEVRULESDIR ?= $(SYSCONFDIR)/udev/rules.d
UNITDIR      ?= $(SYSCONFDIR)/systemd/system
TMPFILESDIR  ?= $(SYSCONFDIR)/tmpfiles.d
SYSUSERSDIR  ?= $(SYSCONFDIR)/sysusers.d
AUTOSTARTDIR ?= $(SYSCONFDIR)/xdg/autostart
BASHCOMPDIR  ?= $(PREFIX)/share/bash-completion/completions
MANDIR       ?= $(PREFIX)/share/man

VERSION := $(shell sed -n 's/^VERSION=//p' gpu-vacate)

UNITS = gpu-vacate-trigger.path gpu-vacate-restore.service gpu-vacate-firmware-input.service

FILES = $(BINDIR)/gpu-vacate \
	$(UDEVRULESDIR)/61-gpu-vacate.rules \
	$(TMPFILESDIR)/gpu-vacate.conf \
	$(SYSUSERSDIR)/gpu-vacate.conf \
	$(UNITDIR)/gpu-vacate-trigger.path \
	$(UNITDIR)/gpu-vacate-trigger.service \
	$(UNITDIR)/gpu-vacate-restore.service \
	$(UNITDIR)/gpu-vacate-firmware-input.service \
	$(AUTOSTARTDIR)/gpu-vacate-sync.desktop \
	$(BASHCOMPDIR)/gpu-vacate \
	$(MANDIR)/man1/gpu-vacate.1

.PHONY: all install uninstall check

all:
	@echo "Nothing to build. Run: sudo make install"

install:
	install -Dm755 gpu-vacate $(DESTDIR)$(BINDIR)/gpu-vacate
	install -Dm644 data/gpu-vacate.bash-completion $(DESTDIR)$(BASHCOMPDIR)/gpu-vacate
	install -Dm644 man/gpu-vacate.1 $(DESTDIR)$(MANDIR)/man1/gpu-vacate.1
	install -Dm644 data/61-gpu-vacate.rules $(DESTDIR)$(UDEVRULESDIR)/61-gpu-vacate.rules
	install -Dm644 data/gpu-vacate.tmpfiles $(DESTDIR)$(TMPFILESDIR)/gpu-vacate.conf
	install -Dm644 data/gpu-vacate.sysusers $(DESTDIR)$(SYSUSERSDIR)/gpu-vacate.conf
	install -Dm644 data/gpu-vacate-trigger.path $(DESTDIR)$(UNITDIR)/gpu-vacate-trigger.path
	install -Dm644 data/gpu-vacate-trigger.service $(DESTDIR)$(UNITDIR)/gpu-vacate-trigger.service
	install -d $(DESTDIR)$(UNITDIR) $(DESTDIR)$(AUTOSTARTDIR)
	sed 's|@BINDIR@|$(BINDIR)|g' data/gpu-vacate-firmware-input.service.in \
		> $(DESTDIR)$(UNITDIR)/gpu-vacate-firmware-input.service
	sed 's|@BINDIR@|$(BINDIR)|g' data/gpu-vacate-restore.service.in \
		> $(DESTDIR)$(UNITDIR)/gpu-vacate-restore.service
	sed 's|@BINDIR@|$(BINDIR)|g' data/gpu-vacate-sync.desktop.in \
		> $(DESTDIR)$(AUTOSTARTDIR)/gpu-vacate-sync.desktop
	chmod 644 $(DESTDIR)$(UNITDIR)/gpu-vacate-firmware-input.service \
		$(DESTDIR)$(UNITDIR)/gpu-vacate-restore.service \
		$(DESTDIR)$(AUTOSTARTDIR)/gpu-vacate-sync.desktop
	@# Never overwrite the admin's settings
	[ -e $(DESTDIR)$(SYSCONFDIR)/gpu-vacate.conf ] || \
		install -Dm644 data/gpu-vacate.conf $(DESTDIR)$(SYSCONFDIR)/gpu-vacate.conf
ifeq ($(DESTDIR),)
	systemd-sysusers $(SYSUSERSDIR)/gpu-vacate.conf
	systemd-tmpfiles --create $(TMPFILESDIR)/gpu-vacate.conf
	systemctl daemon-reload
	udevadm control --reload
	@# The firmware-input service must be running now, or its stop (the shutdown
	@# switch) won't happen at the next reboot
	systemctl enable --now $(UNITS)
	@if [ -n "$$SUDO_USER" ] && ! id -nG "$$SUDO_USER" | grep -qw gpu-vacate; then \
		usermod -aG gpu-vacate "$$SUDO_USER" && \
		echo "Added $$SUDO_USER to the gpu-vacate group: log out and back in before using it."; \
	fi
	@echo "Installed. Set the monitor input codes in $(SYSCONFDIR)/gpu-vacate.conf (see: gpu-vacate inputs)."
endif

uninstall:
ifeq ($(DESTDIR),)
	-systemctl disable --now $(UNITS)
endif
	rm -f $(addprefix $(DESTDIR),$(FILES))
ifeq ($(DESTDIR),)
	rm -rf /run/gpu-vacate /var/lib/gpu-vacate
	systemctl daemon-reload
	udevadm control --reload
	udevadm trigger --subsystem-match=drm --action=change
	@echo "Removed. Kept $(SYSCONFDIR)/gpu-vacate.conf and the gpu-vacate group."
	@echo "Log out and back in to put the desktop back on the dGPU."
endif

check:
	bash -n gpu-vacate
	shellcheck -x gpu-vacate
	shellcheck -s bash data/gpu-vacate.bash-completion
	LC_ALL=C.UTF-8 groff -ww -z -man man/gpu-vacate.1
	@grep -q '"gpu-vacate $(VERSION)"' man/gpu-vacate.1 || \
		{ echo "man page version doesn't match $(VERSION)"; exit 1; }
