#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.0.0-dev}"
PUBLISHER="${2:-CN=FloApp}"
APP_ID="${3:-FloApp}"
OUT_DIR="${4:-$ROOT_DIR/dist/msix}"
SIGNING_READY="${SIGNING_READY:-false}"
RELEASE_CHANNEL="${RELEASE_CHANNEL:-preview}"

if [[ "$RELEASE_CHANNEL" == "ga" && "$SIGNING_READY" != "true" ]]; then
  echo "GA MSIX/winget release is blocked until signing readiness is true."
  exit 1
fi

mkdir -p "$OUT_DIR/winget"
MANIFEST_PATH="$OUT_DIR/AppxManifest.xml"

cat > "$MANIFEST_PATH" <<XML
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  IgnorableNamespaces="uap">
  <Identity Name="$APP_ID" Publisher="$PUBLISHER" Version="$VERSION.0" />
  <Properties>
    <DisplayName>FloApp</DisplayName>
    <PublisherDisplayName>Flo</PublisherDisplayName>
    <Description>Flo Windows app</Description>
    <Logo>Assets\\StoreLogo.png</Logo>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>
  <Applications>
    <Application Id="FloApp" Executable="flo-app.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements
        DisplayName="FloApp"
        Description="Flo Windows app"
        Square150x150Logo="Assets\\Square150x150Logo.png"
        Square44x44Logo="Assets\\Square44x44Logo.png"
        BackgroundColor="transparent" />
    </Application>
  </Applications>
  <Capabilities>
    <Capability Name="runFullTrust" />
  </Capabilities>
</Package>
XML

WINGET_PACKAGE="flo.floapp"
WINGET_VERSION="$VERSION"
WINGET_INSTALLER="https://downloads.flo.app/windows/flo-windows-$VERSION.zip"

cat > "$OUT_DIR/winget/$WINGET_PACKAGE.yaml" <<YAML
PackageIdentifier: $WINGET_PACKAGE
PackageVersion: $WINGET_VERSION
PackageLocale: en-US
Publisher: Flo
PackageName: FloApp
License: MIT
ShortDescription: Flo Windows app
Installers:
  - Architecture: x64
    InstallerType: zip
    InstallerUrl: $WINGET_INSTALLER
    InstallerSha256: REPLACE_WITH_SHA256
ManifestType: singleton
ManifestVersion: 1.6.0
YAML

echo "Generated MSIX + winget prep artifacts in $OUT_DIR"
echo "- $MANIFEST_PATH"
echo "- $OUT_DIR/winget/$WINGET_PACKAGE.yaml"
