{
  lib,
  writeShellApplication,
  common,
  wine,
  dxvk,
}:

writeShellApplication {
  name = "inventor-install";
  runtimeInputs = common.runtimeInputs;
  text =
    common.text
    # bash
    + ''
      usage() {
        cat <<'EOF'
      Usage: inventor install --installer /path/to/Setup.exe [--graphics wine|dxvk] [-- INSTALLER_ARGS...]

      Experimental installation from local official Autodesk media into a separate prefix.
      Use the extracted media's Setup.exe, not an MSI stripped of its prerequisites.
      Keep all media files together. The default opens Autodesk's installer interactively.
      Sign-in and licensing require a valid Inventor entitlement and are not yet validated.
      No Autodesk payload is downloaded automatically. No Fusion workarounds are applied.

      --graphics wine|dxvk   Direct3D implementation for a new prefix (default: wine).
      --                    Forward remaining arguments to Setup.exe without shell evaluation.

      An existing owned prefix is backed up before the installer runs again.
      This is not a tested installation, repair, or update recipe.
      EOF
      }

      installer=""
      graphics=""
      arguments=()
      while (( $# )); do
        case "$1" in
          --help|-h) usage; exit 0 ;;
          --installer)
            (( $# >= 2 )) || fail "--installer requires a file."
            installer="$2"
            shift 2
            ;;
          --graphics)
            (( $# >= 2 )) || fail "--graphics requires wine or dxvk."
            graphics="$2"
            shift 2
            ;;
          --) shift; arguments=("$@"); break ;;
          *) fail "Unknown install option: $1" ;;
        esac
      done
      [[ -n "$installer" ]] || fail "Provide official extracted Autodesk media with --installer /path/to/Setup.exe."
      case "$graphics" in
        ""|wine|dxvk) ;;
        *) fail "Graphics must be wine or dxvk." ;;
      esac
      installer="$(realpath -e "$installer")"
      ${common.python}/bin/python3 ${common.pythonSource}/deployment.py validate "$installer"
      require_display
      lock_prefix --exclusive

      mkdir -p "$cache_dir" "$data_dir/setup"
      if [[ -f "$WINEPREFIX/system.reg" ]]; then
        require_owned_prefix
        require_stopped_prefix
        snapshot="$data_dir/backups/$(date +%Y%m%dT%H%M%S)-$$"
        mkdir -p "$snapshot"
        cp --archive --reflink=auto "$WINEPREFIX" "$data_dir/setup" "$snapshot/"
        for name in installation.json graphics; do
          [[ ! -f "$data_dir/$name" ]] || cp --archive "$data_dir/$name" "$snapshot/"
        done
        echo "Stopped-prefix backup: $snapshot"
      elif [[ -e "$WINEPREFIX" || -e "$data_dir/setup/prefix-v1" ]]; then
        fail "An incomplete or unrelated prefix already exists. Inspect it before proceeding; nothing was reset."
      fi

      umask 077
      log="$state_dir/install-$(date +%Y%m%dT%H%M%S)-$$.log"
      echo "Experimental installation log: $log"
      exec > >(tee -a "$log") 2>&1
      if [[ ! -f "$data_dir/setup/prefix-v1" ]]; then
        # Ownership is recorded after prefix creation, not after application success.
        ${wine}/bin/wineboot --init
        "$WINESERVER" -w
        touch "$data_dir/setup/prefix-v1"
        "$WINE" winecfg -v win11
        stop_prefix
      fi

      if [[ -z "$graphics" && -f "$data_dir/graphics" ]]; then
        graphics="$(cat "$data_dir/graphics")"
      fi
      graphics="''${graphics:-wine}"
      case "$graphics" in
        wine|dxvk) ;;
        *) fail "Invalid saved graphics selection. Use --graphics wine or dxvk." ;;
      esac
      if [[ "$graphics" == dxvk ]]; then
        for arch in x64 x32; do
          target=system32
          [[ "$arch" != x32 ]] || target=syswow64
          for dll in d3d11 dxgi; do
            install -m 644 "${lib.getBin dxvk}/$arch/$dll.dll" "$WINEPREFIX/drive_c/windows/$target/$dll.dll"
          done
        done
      fi
      override=builtin
      [[ "$graphics" != dxvk ]] || override=native
      for dll in d3d11 dxgi; do
        "$WINE" reg add 'HKCU\Software\Wine\DllOverrides' /v "$dll" /d "$override" /f >/dev/null
      done
      printf '%s\n' "$graphics" > "$data_dir/graphics"
      stop_prefix

      # The installer owns prerequisites and licensing. Never bypass its licensing
      # service, invent version-specific product codes, or silently accept a EULA.
      printf 'Installer entrypoint: %s\n' "$installer"
      printf 'Wine diagnostics: %s\n' "$WINEDEBUG"
      echo "Starting Autodesk's installer. Review its license terms and component choices."
      cd "$(dirname "$installer")"
      rc=0
      "$WINE" "$installer" "''${arguments[@]}" || rc=$?
      stop_prefix
      (( rc == 0 )) || fail "Autodesk installer exited with $rc. Inspect the log; no successful installation was recorded."
      ${common.python}/bin/python3 ${common.pythonSource}/deployment.py record \
        "$WINEPREFIX" "$data_dir" "$installer" "${wine.version}"
      echo "Inventor.exe was found. Launch, licensing, graphics, and file operations still need validation."
    '';
}
