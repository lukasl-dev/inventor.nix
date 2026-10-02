{
  writeShellApplication,
  common,
  installer,
  wine,
}:

writeShellApplication {
  name = "inventor";
  runtimeInputs = common.runtimeInputs;
  text =
    common.text
    # bash
    + ''
      usage() {
        cat <<'EOF'
      Autodesk Inventor on NixOS (experimental; compatibility not established)

      Usage: inventor [COMMAND] [OPTIONS]

      Commands:
        install --installer FILE [--graphics wine|dxvk] [-- INSTALLER_ARGS...]
                                 Run official local installation media in a dedicated prefix
        run [--year YYYY] [FILES...]
                                 Launch Inventor (default); never guess between installed years
        stop                     Request graceful shutdown of this Inventor Wine session
        doctor                   Show runtime, installation paths, and available space
        wine PROGRAM [ARGS...]   Run a diagnostic Windows command in the owned Inventor prefix

      Defaults:
        ~/.local/share/inventor   Prefix, setup markers, provenance, and stopped-prefix backups
        ~/.cache/inventor         Reserved installer cache (no automatic Autodesk downloads)
        ~/.local/state/inventor   Logs

      XDG paths and INVENTOR_{DATA,CACHE,STATE}_HOME overrides are respected.
      Supply original Autodesk installation media and a valid Inventor entitlement.
      Linux/Wine is not supported by Autodesk. Nothing is installed by running --help.
      EOF
      }

      command="''${1:-run}"
      (( $# == 0 )) || shift
      case "$command" in
        --help|-h|help) usage; exit 0 ;;
        install) exec ${installer}/bin/inventor-install "$@" ;;
        run|stop|doctor|wine) ;;
        *) fail "Unknown command: $command. Use 'inventor --help'." ;;
      esac

      case "$command" in
        doctor)
          (( $# == 0 )) || fail "doctor takes no arguments."
          echo "Status: experimental; no Inventor compatibility established."
          echo "Wine package: ${wine}"
          echo "Wine version: ${wine.version}"
          echo "Wine diagnostics: $WINEDEBUG"
          echo "Prefix: $WINEPREFIX"
          echo "Cache: $cache_dir"
          echo "Logs: $state_dir"
          echo "DISPLAY: ''${DISPLAY:-unset} (Xwayland on Wayland)"
          if [[ -f "$data_dir/setup/prefix-v1" ]]; then
            echo "Owned prefix: present"
            resolve_executable "" || true
          else
            echo "Owned prefix: absent"
          fi
          echo "Available disk space (no prefix is created):"
          df -h "$HOME" /nix/store
          ;;
        stop)
          (( $# == 0 )) || fail "stop takes no arguments."
          require_owned_prefix
          require_display
          # A shared lock lets stop request shutdown while the launcher still waits.
          lock_prefix --shared
          echo "Requesting graceful shutdown. Save and close your Inventor documents first."
          stop_prefix
          echo "Inventor Wine session stopped."
          ;;
        wine)
          (( $# > 0 )) || fail "Usage: inventor wine PROGRAM [ARGS...]"
          require_owned_prefix
          require_display
          lock_prefix --shared
          # Don't record arguments: an Identity callback can contain credentials.
          "$WINE" "$@"
          ;;
        run)
          year=""
          if [[ "''${1:-}" == --year ]]; then
            (( $# >= 2 )) || fail "--year requires a four-digit Inventor release year."
            year="$2"
            [[ "$year" =~ ^20[0-9]{2}$ ]] || fail "Inventor year must be four digits (20xx)."
            shift 2
          fi
          [[ "''${1:-}" != --* ]] || fail "Unknown run option: $1"
          require_owned_prefix
          files=()
          for argument in "$@"; do
            files+=("$(realpath -e "$argument")")
          done
          require_display
          lock_prefix --shared
          # Resolve under the lock: an installer must not replace the chosen
          # executable between discovery and process creation.
          executable="$(resolve_executable "$year")"
          for index in "''${!files[@]}"; do
            files[index]="$("$WINE" winepath -w "''${files[index]}" | tr -d '\r')"
          done
          umask 077
          log="$state_dir/run-$(date +%Y%m%dT%H%M%S)-$$.log"
          echo "Launching Inventor (experimental). Log: $log"
          cd "$(dirname "$executable")"
          rc=0
          "$WINE" "$executable" "''${files[@]}" >"$log" 2>&1 || rc=$?
          # Keep installation excluded while child processes and services remain.
          # Closing a document is not proof that its Wine session has stopped.
          "$WINESERVER" -w
          exit "$rc"
          ;;
      esac
    '';
}
