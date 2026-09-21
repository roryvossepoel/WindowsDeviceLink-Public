# Releasing WindowsDeviceLink

WindowsDeviceLink uses a deliberately manual, release-driven publication process. A normal push to `main` must never publish a PowerShell Gallery package or create a GitHub release.

## Version source of truth

The module manifest is the source of truth:

```text
src/WindowsDeviceLink/WindowsDeviceLink.psd1
```

A preview such as `0.4.3-preview1` is represented by:

```powershell
ModuleVersion = '0.4.3'
PrivateData.PSData.Prerelease = 'preview1'
```

The corresponding GitHub tag is:

```text
v0.4.3-preview1
```

For a stable release, leave `Prerelease` empty/remove the prerelease label and use a tag such as `v1.0.0`.

## Release principles

- Releases are intentional and manually started.
- The version is derived from the manifest; workflow files do not hardcode a release number.
- The PowerShell Gallery package is built with `tools/New-GalleryPackage.ps1`.
- `Windows.Management.Service.dll` must never be redistributed in the Gallery package.
- Existing Gallery versions and GitHub release tags are immutable. Bump the version instead of replacing a release.
- `PSGALLERY_API_KEY` is stored only as a GitHub Actions secret.
- Code signing is planned separately. Until signing is implemented, the current WinPE publisher-check workaround is documented in `docs/INSTALLATION.md`.

## Pre-release checklist

Before publishing a new version:

1. update `ModuleVersion` and `PrivateData.PSData.Prerelease` in the manifest;
2. update release-facing documentation where the currently published version is mentioned;
3. run the Windows 11 smoke tests;
4. run the AMD64 WinPE smoke tests where applicable;
5. review `TESTING.md` and record new validated behavior;
6. scan the public repository for tenant IDs, serial numbers, association IDs, JWT data, secrets, test API keys and other environment-specific identifiers;
7. confirm `Windows.Management.Service.dll` is not present in the public repository or release package;
8. build locally with `tools/New-GalleryPackage.ps1` when doing a final manual verification;
9. verify the public command surface with `Test-ModuleManifest` / `Get-Command`;
10. commit all release content to `main` before starting either release workflow.

## Create the GitHub release and immutable tag

Use GitHub Actions -> **Create GitHub Release** -> **Run workflow**.

The optional `expected_version` input is a safety check. For example:

```text
0.9.0-preview1
```

The workflow derives `v<version>` from the manifest, verifies that the source is the current GitHub-Verified `main` commit, and creates the prerelease/tag without moving an existing tag.

The immutable tag is required before Gallery publication.

## Publish to PowerShell Gallery

After the GitHub release/tag exists, use GitHub Actions -> **Publish PowerShell Gallery** -> **Run workflow** and provide the exact release version, for example:

```text
0.9.0-preview1
```

The Gallery workflow:

1. checks out the exact immutable `v<version>` tag;
2. verifies that HEAD matches that exact tag;
3. builds the staged Gallery package;
4. validates the manifest and public command surface;
5. runs hardware-independent regression checks against the staged artifact;
6. verifies that no Microsoft runtime DLL is bundled;
7. publishes with the `PSGALLERY_API_KEY` repository secret.

A normal push to `main` never publishes a Gallery package.

## Recommended order

```text
finish code and documentation
        |
        v
validate Windows / WinPE
        |
        v
final public-repository audit
        |
        v
merge release-prep PR through GitHub
        |
        v
GitHub Verified main commit
        |
        v
Create GitHub Release workflow
        |
        v
immutable vX.Y.Z[-prerelease] source tag
        |
        v
Publish PowerShell Gallery workflow
        |
        v
install the actual Gallery package and smoke-test it
```

The GitHub release/tag is intentionally created before Gallery publication because the Gallery workflow publishes only from an immutable release tag.

## Signing roadmap

WindowsDeviceLink is currently unsigned. The planned supply-chain improvement is public Authenticode signing, preferably through SignPath Foundation, followed by verification in the release pipeline. Once signing is implemented, repeat the WinPE `Install-Module` test without `-SkipPublisherCheck` and update `docs/INSTALLATION.md` based on the result.
