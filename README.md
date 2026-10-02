# inventor.nix

An experimental Nix-native Autodesk Inventor installer and launcher, with a pinned
Wine runtime and a separate mutable prefix.

> [!IMPORTANT]
> This is an unofficial experiment, not a working Linux port. It is not affiliated
> with or endorsed by Autodesk. Autodesk does not support Inventor on Linux.
> Successful Nix builds and CLI tests do not establish that Inventor installs,
> signs in, renders, or saves files under Wine.

## Status

- The Nix environment, command parsing, installation discovery, and provenance
  helpers are implemented and tested without proprietary software.
- Actual Inventor installation, Autodesk Licensing Service, account sign-in,
  graphics, part/assembly workflows, and file operations remain unverified.
- Fusion's working configuration is **not** copied into Inventor: no RSA or popup
  patches, Qt sandbox bypass, legacy .NET dependency list, Identity prestart, or
  Fusion-specific graphics preferences.
- The default is unmodified Wine Staging with its built-in Direct3D implementation.
  DXVK is an explicit graphics experiment, not a proven Inventor requirement.

### Known compatibility obstacles

[Inventor 2027 installer research on NixOS](https://github.com/ejb1123/inventor-wine)
reproduces ADIX installation rollback after `RegLoadAppKeyW` returns Wine's fake
`0xdeadbeef` registry handle. That stub is also present in this flake's stock Wine
11.16. The research project supplies a binary-registry-hive implementation and
additional service fixes, but documents incomplete hive lifetime/isolation
semantics. Its installer and graphics results do not establish a reproducible,
legitimately authenticated clean installation. Those patches are **not bundled**
here without review and a reproduction against the chosen media.

[Inventor 2026 research](https://github.com/cakelesscoder/inventor-on-linux)
reports modeling and Autodesk SSO, but starts from an existing Windows
installation/registry and modifies application binaries. That is not evidence
that the official installer works in our fresh prefix, and is not the recipe used
by this project. A stock-Wine attempt may stop before installation completes;
its purpose is to identify the first concrete blocker, not promise success.

Inventor's .NET requirements depend on the release **and update level**. Autodesk
lists .NET 8 for the original 2026 requirements and .NET 10 for 2027, with later
2025/2026 updates also transitioning to .NET 10. These modern Desktop Runtimes are
not interchangeable with `.NET Framework 4.8`. Do not transplant Fusion's
Winetricks `dotnet48` list. The initial prefix reports Windows 11, matching the
current 2027 system-requirements table.

## First installation experiment

Use a machine with enough space for the downloaded media, its extracted copy,
Inventor and dependencies, temporary installer files, and later prefix backups.
Do not start this on a low-space machine. This project does not download Inventor
automatically or bundle Autodesk software in the Nix store.

1. Obtain official Inventor installation media from your Autodesk account or
   Autodesk's authorized trial/education channel. An Inventor entitlement is
   required; a Fusion entitlement does not establish Inventor access.
2. Fully extract the media on the installation machine. Keep the complete directory
   together and use its top-level `Setup.exe`. Do not invoke an isolated product
   MSI or copy the payload into this Git repository.
3. Run from that machine's graphical desktop terminal:

   ```console
   nix run github:lukasl-dev/inventor.nix -- install --installer "/absolute/path/to/extracted/media/Setup.exe"
   ```

The default opens Autodesk's installer interactively so you can review its license
terms and component choices. Autodesk's own installer is responsible for its
prerequisites and licensing services; their Wine compatibility is an open question.
The wrapper does not disable licensing, bypass installer checks, or silently
accept terms. Extra documented installer arguments can be passed after `--`.

Wine errors are enabled by default with `WINEDEBUG=-all,err+all`. For installer
investigation, preserve the exact media version/update and run with targeted
tracing such as `WINEDEBUG=-all,err+all,+loaddll` for startup DLL failures, or
`WINEDEBUG=-all,err+all,+reg,+seh` for registry/exception failures. Trace files can be
large and contain private paths or account information; inspect and redact them
before sharing. Do not disable signature verification, alter clocks to evade
validation, or substitute a licensing bypass when setup fails.

For an explicit DXVK experiment, add `--graphics dxvk`. Only the D3D11/DXGI DLLs
are replaced; there are no Inventor preference-file edits. The default is
`--graphics wine`. Re-running install in an existing owned prefix backs up its
stopped state before invoking Autodesk's setup again; this is not yet a validated
repair or update workflow.

## Launch and diagnostics

```console
nix run github:lukasl-dev/inventor.nix
nix run github:lukasl-dev/inventor.nix -- run --year 2026 /path/to/part.ipt
nix run github:lukasl-dev/inventor.nix -- doctor
nix run github:lukasl-dev/inventor.nix -- stop
```

When several release years are installed, select one with `--year`; the wrapper
never chooses a release by directory modification time. Executable discovery is
currently limited to `C:\Program Files\Autodesk\Inventor YYYY\Bin\Inventor.exe`.
Custom Autodesk install locations are not yet supported.

`inventor wine PROGRAM [ARGS...]` runs a Windows diagnostic or prerequisite
installer in the owned Inventor prefix. It is an escape hatch for investigation,
not an automatic dependency recipe. Do not paste unredacted authentication URLs
or account-bearing logs into issue reports. TLS certificate verification remains
enabled.

Save and close your documents before `stop`. Shutdown is graceful and bounded;
the wrapper never force-kills Wine. Background licensing services can remain after
the application window closes. Fully stop the prefix and back it up before
changing the Wine runtime; never mix Wine runtimes in one live prefix.

## State and isolation

| Default path | Contents |
| --- | --- |
| `~/.local/share/inventor` | Wine prefix, setup marker, provenance, graphics choice, backups |
| `~/.cache/inventor` | Reserved installer cache; no automatic Inventor downloads |
| `~/.local/state/inventor` | Installation and launch logs |

The standard `XDG_DATA_HOME`, `XDG_CACHE_HOME`, and `XDG_STATE_HOME` variables are
respected. Override individual paths with `INVENTOR_DATA_HOME`,
`INVENTOR_CACHE_HOME`, and `INVENTOR_STATE_HOME`. Use dedicated absolute directories;
do not point these at Fusion's state or an unrelated Wine prefix.

The prefix lock prevents installation during a running Inventor session. Setup
markers identify prefixes this wrapper created; an unrelated existing prefix is
refused. A Wine prefix separates Windows state but is **not an OS sandbox**:
Windows software can access your Unix files through Wine's drive mappings.

`installation.json` records the setup executable's SHA-256, Wine version, and
discovered executable paths. This identifies the entrypoint bytes, **not every
file in multipart installation media**, and does not pin a licensed Inventor
release or certify installation health.

## NixOS / Home Manager

Add the flake as an input and install `inputs.inventor.packages.${pkgs.system}.default`
in `environment.systemPackages` or `home.packages`. The package provides an
experimental launcher desktop entry. Running `nix run` alone does not install a
persistent desktop entry or register an Autodesk sign-in callback.

No generic `adskidmgr:` handler is registered yet: blindly replacing Fusion's
handler could route login callbacks into the wrong product prefix. Inventor's
actual Identity/licensing integration must be observed before adding it.

## Development

```console
nix build
nix flake check
nix develop
cd python
mypy .
ruff check .
ruff format --check .
```

Nix owns the runtime and development tools. Shell applications stay in `.nix`
definitions using `writeShellApplication`; typed Python helpers and tests live in
`python/`. The lockfile starts from the same cached pins as `fusion360.nix` to avoid
an unnecessary local Wine rebuild, but this flake is independent of Fusion.

Tests use temporary files and do not start Wine or download Autodesk media.
The acceptance test remains: complete the official setup and licensing, launch,
create a sketch and solid, save an `.ipt`, close/reopen it, build a small assembly,
and export/import STEP without losing data.

## References

- [Autodesk Inventor](https://www.autodesk.com/products/inventor/overview)
- [Official product downloads](https://www.autodesk.com/support/download-install/individuals/download)
- [Inventor 2027 requirements](https://www.autodesk.com/support/technical/article/caas/sfdcarticles/sfdcarticles/System-requirements-for-Autodesk-Inventor-2027.html)
- [Inventor 2026 requirements](https://www.autodesk.com/support/technical/article/caas/sfdcarticles/sfdcarticles/System-requirements-for-Autodesk-Inventor-2026.html)
- [Inventor ADIX/Wine installer research](https://github.com/ejb1123/inventor-wine)
- [Inventor 2026 Windows-installation-based research](https://github.com/cakelesscoder/inventor-on-linux)
- [Inventor Linux support discussion](https://forums.autodesk.com/t5/inventor-ideas/autodesk-inventor-professional-for-linux-redhat-centos-ubuntu/idi-p/5112010/page/2)
- [Autodesk desktop products' .NET runtime updates](https://blog.autodesk.io/autodesk-desktop-products-2025-2026-net-10-updates/)

This wrapper is MIT-licensed. Autodesk and Microsoft components retain their own
licenses and are supplied by their vendors, not redistributed in this flake.
