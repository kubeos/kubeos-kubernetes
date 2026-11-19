#!/bin/sh
# Mirror the pinned Kubernetes debs into the KubeOS archive, unchanged.
#
# WHEN   once per Kubernetes version, from the builder VM, in this repository checkout:
#            bin/mirror.sh --dry-run     # download and verify, publish nothing
#            bin/mirror.sh               # download, verify, publish
# WHY    A KubeOS node must not follow pkgs.k8s.io on its own: a kubelet newer than the
#        control plane KubeOS ships is a broken cluster, and the upstream feed moves
#        without warning. So the upstream repository is not configured on a node at all;
#        the four packages come from repo.kubeos.in, copied byte for byte, and only what
#        PINNED lists can be reached by `apt upgrade`. This script is the only thing that
#        puts them there.
# SAFE   Downloads into a temporary directory, verifies every sha256 from PINNED, refuses
#        to publish a file that does not match, and never touches a node. Re-running it is
#        harmless: the archive publisher replaces a package's own stanza.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
UPSTREAM=${KUBEOS_K8S_UPSTREAM:-https://pkgs.k8s.io/core:/stable:/v1.37/deb}
PUBLISHER=${KUBEOS_PUBLISHER:-/root/pkgs/archive-publish.sh}
DRY_RUN=${KUBEOS_MIRROR_DRY_RUN:-0}

log() { printf 'mirror: %s\n' "$*"; }
die() { printf 'mirror: ERROR: %s\n' "$*" >&2; exit 1; }

case ${1:-} in
    --dry-run) DRY_RUN=1 ;;
    '') : ;;
    *) die "unknown argument: $1 (try --dry-run)" ;;
esac

[ -f "$HERE/PINNED" ] || die "no PINNED file next to bin/"
command -v curl >/dev/null 2>&1 || die "curl is not installed"
[ "$DRY_RUN" = 1 ] || [ -x "$PUBLISHER" ] || die "archive publisher not found: $PUBLISHER"

# The metapackage's own version names the Kubernetes release; a mismatch means the pin and
# the package disagree and the archive would advertise a version nothing depends on.
PKG_VERSION=$(sed -n '1s/.*(\(.*\)).*/\1/p' "$HERE/debian/changelog")
case "$PKG_VERSION" in
    1.37.*) : ;;
    *) die "debian/changelog says $PKG_VERSION - update this guard AND bin/mirror.sh's upstream line together" ;;
esac

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

COUNT=0
while read -r pkg ver sha _rest; do
    case "$pkg" in ''|'#'*) continue ;; esac
    deb="${pkg}_${ver}_amd64.deb"
    log "fetching $deb"
    curl -fsSL -o "$WORK/$deb" "$UPSTREAM/amd64/$deb" || die "download failed: $UPSTREAM/amd64/$deb"
    got=$(sha256sum "$WORK/$deb" | awk '{print $1}')
    [ "$got" = "$sha" ] || die "$deb does not match PINNED (want $sha, got $got)"
    log "  sha256 OK"
    if [ "$DRY_RUN" = 1 ]; then
        log "  would publish (dry run)"
    else
        # The publisher refuses foreign packages unless this is set: the exception exists
        # only for this deliberate mirror.
        KUBEOS_ARCHIVE_ALLOW_FOREIGN=1 "$PUBLISHER" "$WORK/$deb" || die "publishing $deb failed"
    fi
    COUNT=$((COUNT + 1))
done < "$HERE/PINNED"

[ "$COUNT" -gt 0 ] || die "PINNED listed no packages"
log "done: $COUNT package(s)"
