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

## Publish to PowerShell Gallery

Use GitHub Actions -> **Publish PowerShell Gallery** -> **Run workflow**.

The optional `expected_version` input is a safety check. For example:

```text
0.4.4-preview1
```

If supplied, the workflow fails unless it exactly matches the version derived from the manifest.

The workflow:

1. checks out the selected commit;
2. builds the Gallery package;
3. validates the manifest;
4. derives the complete Gallery version from `ModuleVersion` plus `Prerelease`;
5. verifies that the Microsoft runtime DLL is not bundled;
6. publishes with the `PSGALLERY_API_KEY` repository secret.

A normal push to `main` does not invoke publication.

## Create the GitHub release and immutable tag

After the Gallery publication and smoke test succeed, use GitHub Actions -> **Create GitHub Release** -> **Run workflow**.

Optionally enter the same `expected_version` value. The workflow derives the tag from the manifest, for example:

```text
v0.4.3-preview1
```

It refuses to continue if that tag or release already exists. It then creates a GitHub release targeted at the exact commit on which the workflow runs and uses GitHub-generated release notes. Preview versions are marked as prereleases.

This gives the Gallery version a stable source-code reference.

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
Publish PowerShell Gallery workflow
        |
        v
install the actual Gallery package and smoke-test it
        |
        v
Create GitHub Release workflow
        |
        v
immutable vX.Y.Z[-prerelease] source tag
```

The GitHub release is intentionally created after the Gallery smoke test so a tag is only frozen once the published artifact has been verified.

## Signing roadmap

WindowsDeviceLink is currently unsigned. The planned supply-chain improvement is public Authenticode signing, preferably through SignPath Foundation, followed by verification in the release pipeline. Once signing is implemented, repeat the WinPE `Install-Module` test without `-SkipPublisherCheck` and update `docs/INSTALLATION.md` based on the result.
