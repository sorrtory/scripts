#!/bin/sh
set -eu
sudo --preserve-env=WAYLAND_DISPLAY,XDG_SESSION_TYPE,DBUS_SESSION_BUS_ADDRESS,XDG_RUNTIME_DIR \
  /usr/local/bin/vpnexec firefox 2ip.ru

# firefox -CreateProfile private
# firefox -P private -private -new-session