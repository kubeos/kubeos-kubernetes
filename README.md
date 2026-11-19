# kubeos-kubernetes

**What a KubeOS node's Kubernetes version is, and the only thing that can change it.**

Kubernetes ships four Debian packages a KubeOS node needs: `kubelet`, `kubeadm`,
`kubectl` and `kubernetes-cni`. Upstream publishes them at `pkgs.k8s.io` and keeps moving
them — patch releases arrive without notice, and a kubelet newer than the control plane is a
broken cluster. A KubeOS node must therefore not follow that feed.

This repository holds:

| Path | What it is |
|---|---|
| `PINNED` | the exact versions and sha256 of the debs KubeOS ships |
| `bin/mirror.sh` | downloads those debs, verifies them, publishes them to `repo.kubeos.in` |
| `debian/` | the `kubeos-kubernetes` metapackage: `Depends: kubelet (= …), kubeadm (= …), kubectl (= …), kubernetes-cni (= …)` |

## The model (user decision, 2026-11-19)

The debs are **byte-identical** to upstream: same version (`1.37.2-1.1`), same files, same
maintainer scripts, same checksums. Nothing is rebuilt and nothing is re-versioned, so they
behave exactly like the upstream release — but they are reachable only from
`repo.kubeos.in`, because the `pkgs.k8s.io` line is **not** configured on a KubeOS node.

The result: `apt update && apt upgrade` moves Kubernetes **only** to a version KubeOS has
mirrored, while `kubeos-kubernetes` answers "which Kubernetes does this node run?" and
pins it with `=`.

The upstream archive really does refuse to carry somebody else's packages
(`archive-publish.sh` dies with *"not a KubeOS package"*); `bin/mirror.sh` is the single,
explicit exception, and it sets `KUBEOS_ARCHIVE_ALLOW_FOREIGN=1` for exactly these files.

## Moving Kubernetes (a deliberate act)

1. Take the new versions and sha256 from
   `https://pkgs.k8s.io/core:/stable:/v1.37/deb/Packages.gz` (amd64 stanza).
2. Update `PINNED` and, if the minor moved, `UPSTREAM` in `bin/mirror.sh` and the version
   guard in it too.
3. Bump `debian/changelog` so the metapackage's version names the new release, and update
   the `=` pins in `debian/control`.
4. `bin/mirror.sh` — publish the debs themselves **first**.
5. `bin/build-deb.sh`, then publish the metapackage with `archive-publish.sh` (it is a
   `kubeos-*` package, no exception needed) — **second**, so nothing ever depends on a file
   the archive does not have yet.
6. On a node: `apt update && apt install kubeos-kubernetes`, then
   `kubeadm upgrade plan` / `kubeadm upgrade apply` as usual.

Never publish a deb that is not in `PINNED`, and never publish `kubeos-kubernetes` before
the debs it depends on exist in the archive — a node would see a dependency it cannot
fetch.

## Licence

The mirrored debs are Apache-2.0 (Kubernetes). Redistribution with their own
`/usr/share/doc/*/copyright` intact is what the licence allows; KubeOS adds no terms.
`debian/copyright` covers this metapackage.
