{
  wine,
  python3,
  cacert,
  coreutils,
  util-linux,
  systemd,
}:

{
  python = python3;
  pythonSource = ./python;
  runtimeInputs = [
    wine
    python3
    coreutils
    util-linux
    systemd
  ];

  # Separate ownership from Fusion. No Fusion graphics preferences, DLL patches,
  # Identity startup policy, or browser sandbox bypasses are applied here.
  text = # bash
    ''
      data_dir="''${INVENTOR_DATA_HOME:-''${XDG_DATA_HOME:-$HOME/.local/share}/inventor}"
      cache_dir="''${INVENTOR_CACHE_HOME:-''${XDG_CACHE_HOME:-$HOME/.cache}/inventor}"
      state_dir="''${INVENTOR_STATE_HOME:-''${XDG_STATE_HOME:-$HOME/.local/state}/inventor}"
      for directory in "$data_dir" "$cache_dir" "$state_dir"; do
        if [[ "$directory" != /* || "$directory" == / ]]; then
          echo "Inventor paths must be absolute, non-root directories: $directory" >&2
          exit 2
        fi
      done

      export WINEPREFIX="$data_dir/prefix"
      export WINE=${wine}/bin/wine
      export WINESERVER=${wine}/bin/wineserver
      export WINEARCH=win64
      # err is a message class, not a channel. +err hides loader failures after
      # -all; err+all keeps actual errors while suppressing routine trace noise.
      export WINEDEBUG="''${WINEDEBUG:--all,err+all}"
      export NIX_SSL_CERT_FILE="''${NIX_SSL_CERT_FILE:-${cacert}/etc/ssl/certs/ca-bundle.crt}"
      export WINEDLLOVERRIDES="winemenubuilder.exe=d''${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"

      # Autodesk supplies Windows Qt components; don't load Linux desktop plugins.
      unset QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE
      unset QT_PLUGIN_PATH QT_QPA_PLATFORM_PLUGIN_PATH QML2_IMPORT_PATH QML_IMPORT_PATH
      unset QT_WAYLAND_DISABLE_WINDOWDECORATION

      fail() {
        echo "inventor: $*" >&2
        exit 1
      }

      require_display() {
        if [[ -z "''${DISPLAY:-}" && -z "''${SSH_CONNECTION:-}" && -z "''${SSH_TTY:-}" ]]; then
          local key value
          while IFS='=' read -r key value; do
            if [[ "$key" == DISPLAY && "$value" =~ ^:[0-9]+(\.[0-9]+)?$ ]]; then
              export DISPLAY="$value"
              break
            fi
          done < <(timeout 2 systemctl --user show-environment 2>/dev/null || true)
        fi
        [[ -n "''${DISPLAY:-}" ]] || fail "No X11 display. Run from your desktop terminal (Xwayland on Wayland)."
      }

      require_owned_prefix() {
        [[ -f "$data_dir/setup/prefix-v1" && -f "$WINEPREFIX/system.reg" ]] \
          || fail "No managed Inventor prefix. Run 'inventor install --installer /path/to/Setup.exe' first."
      }

      lock_prefix() {
        umask 077
        [[ ! -L "$data_dir" && ! -L "$WINEPREFIX" && ! -L "$data_dir/prefix.lock" ]] \
          || fail "Symlinked data directories, prefixes, or locks are not supported."
        mkdir -p "$data_dir" "$state_dir"
        exec 9>"$data_dir/prefix.lock"
        flock "$1" --nonblock 9 \
          || fail "Inventor is running, or another installation is in progress. Close Inventor and use 'inventor stop' if services remain."
      }

      require_stopped_prefix() {
        timeout 5 "$WINESERVER" -w \
          || fail "Wine is still running in this prefix. Use 'inventor stop' first; no processes were killed."
      }

      stop_prefix() {
        "$WINE" wineboot --end-session --shutdown
        timeout 15 "$WINESERVER" -w \
          || fail "Wine did not stop. Close remaining Windows applications; nothing was force-killed."
      }

      resolve_executable() {
        ${python3}/bin/python3 ${./python}/deployment.py resolve "$WINEPREFIX" "$1"
      }
    '';
}
