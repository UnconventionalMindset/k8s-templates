# Kairos / K3s upgrade plan: bring your own image (hs, e2, e1)

## Why the strategy changed

Kairos v4.0.0 (Feb 2026) publishes **Hadron-only** official artifacts. The distro flavor repos on `quay.io/kairos/*` (Fedora, Ubuntu, openSUSE) are no longer updated: `quay.io/kairos/fedora` stops at Kairos v3.7.2 (Fedora 40), and no v4 Fedora image exists. Building on a pre-built `quay.io/kairos/fedora:*` base is a dead end.

The supported path for Fedora is **BYOI**: build your own image with `kairos-init`, publish it to your own registry, and upgrade nodes from it. Facts that shape the plan:

- `kairos-init` now ships from the `kairos-io/kairos` monorepo. The current image is `quay.io/kairos/kairos-init:v4.4.0`. The old repo is archived, and the factory docs still show the older `v0.17.3`.
- Its smoke-test matrix covers **Fedora 42 and 43** (41 for FIPS/Trusted Boot). Fedora 40 is not in the matrix.
- K3s is selected at build time with `--provider k3s --provider-k3s-version <tag>`, so **any k3s release** can be installed. It is no longer tied to what Kairos bundled.
- Fedora release, Kairos tooling version, k3s version, and our own image version are now independent build args, so every upgrade step can change exactly one of them.
- The old `-k` / `--k8sversion` flags were removed in kairos-init v0.6.0. The untracked `~/proj/kairos-transcoding/kairos-init/Dockerfile` uses them and a stale v0.8.4, so it is superseded by `Dockerfile.byoi`.

## Current state (2026-11-06)

| Node | IP | Kairos | Image | K3s | Active/passive image | Root free | State free | Pods |
|------|----|--------|-------|-----|----------------------|-----------|------------|------|
| hs | 192.168.31.193 | v3.5.3 | `2.0.3-kairos-3.5.3-k3s-1.33.4` | v1.33.4+k3s1 | 2.5 GiB | 439 MB (82% used) | 3.4 GB | 45 |
| e2 | 192.168.31.192 | v3.5.3 | `2.0.3-kairos-3.5.3-k3s-1.33.4` | v1.33.4+k3s1 | 2.5 GiB (loop size only; free space not measured) | not measured | not measured | 33 |
| e1 | 192.168.31.191 | v3.5.2 | `2.0.0-kairos-3.5.2-k3s-1.33.4` | v1.33.4+k3s1 | 3.0 GiB | 943 MB (68% used) | 5.9 GB | 11 |

- All three are control-plane + etcd (3-member quorum), run `kairos-agent v2.24.0`, and expose `/dev/dri`, so all three need the Intel transcoding stack.
- Each node has one disk (`vda`) with the standard Kairos layout. `COS_PERSISTENT` is mounted at `/usr/local`, and Longhorn's data (`/var/lib/longhorn`) lives on it. The kernel cmdline has no `rd.cos.mount`, `rd.immucore.mount`, or `VOLUMES`.
- Each node's cmdline has `rd.emergency=reboot rd.shell=0`, so a boot failure reboots instead of opening a shell.
- `/oem/90_custom.yaml` still sets `install.source` to `...kairos-fedora-transcoding:latest`.

## Target

- **Fedora 43** (latest tested by kairos-init; 40 is EOL).
- **Kairos tooling v4.4.0** (`kairos-init` v4.4.0).
- **K3s 1.35.10** via **1.34.13**. K3s upgrades one minor at a time, so 1.34 is a required hop. 1.33 is a dead end: the last release was v1.33.13 on 2026-08-04, and 1.34.13 and 1.35.10 were released 2026-11-03. Later optional steps: 1.36.6, 1.37.2.

Skipping Fedora 41/42 and Kairos 3.6–4.3 is safe. Images are rebuilt from scratch and swapped wholesale, and node state lives in persistent paths, so there is no in-place Fedora upgrade path to step through. In the release notes I found breaking changes only in v4.0.0 (Hadron-only) and v4.4.0 (below). That was a check of headings and flagged lines, not a line-by-line read of every release.

## Image matrix (one component per step)

Built from `~/proj/kairos-transcoding/Dockerfile.byoi`. `IMAGE_VERSION` is written to `/etc/kairos-release` and must be semver. It must stay above the nodes' current v3.5.3, so the old 2.x tags would read as downgrades.

| Image version | Fedora | kairos-init | K3s | Changes vs. previous step |
|---------------|--------|-------------|-----|---------------------------|
| current | 40 (Kairos prebuilt) | v3.5.3 tooling | v1.33.4+k3s1 | n/a |
| **4.4.1** | 40 | v4.4.0 | v1.33.4+k3s1 | Kairos tooling and packaging only |
| **4.4.2** | 43 | v4.4.0 | v1.33.4+k3s1 | Fedora only |
| **4.4.3** | 43 | v4.4.0 | v1.34.13+k3s1 | K3s minor only |
| **4.4.4** | 43 | v4.4.0 | v1.35.10+k3s1 | K3s minor, and adds `libva-utils` and `clinfo` (host-side GPU check tools). This is the one step that changes more than one thing. |
| optional | 43 | v4.4.0 | v1.36.6+k3s1 / v1.37.2+k3s1 | One minor each |
| optional | 43 | v4.4.0 | latest | CIS hardening on (`KAIROS_INIT_ARGS=""`) |

Tag format: `quay.io/unconventionalmindset/kairos-fedora-transcoding:<version>-fedora<N>-k3s-<ver>`, for example `4.4.3-fedora43-k3s-1.34.13`. The `latest` tag is not moved.

"Fedora only" and "Kairos only" steps still pick up newer packages from the Fedora repos at build time (kernel included), which cannot be pinned further. Step 4.4.1 rebuilds from `fedora:40` with current packages, so it is not byte-identical to today's OS even though the release is the same.

## Kairos v4.4.0 behavior, checked against these nodes

- **Boot fails hard on persistence mount errors.** Applies only when a disk named in `rd.cos.mount` / `rd.immucore.mount` / `VOLUMES` is missing. None are set here, so the nodes are not affected. Because of `rd.emergency=reboot`, a failure would loop on reboot rather than drop to a shell.
- **`/usr/libexec` is no longer persisted.** Nothing in `/oem/90_custom.yaml` depends on it.
- **CIS Level 1 hardening is on by default** (account lockout including root, 14-character passwords, `su` limited to wheel, immutable auditd rules, sysctls including `accept_ra=0`, persistent journald). `Dockerfile.byoi` skips it by default with `--skip-step cisHardening` so it can be adopted as its own step.
- **`/tmp` and `/dev/shm` are mounted `noexec`.** This is done by immucore, so `--skip-step cisHardening` does not disable it. Anything that executes from `/tmp` will fail. Watch Longhorn instance managers, democratic-csi, and any node scripts during the pilot.

## Image size gate

The root filesystem on hs and e2 is a 2.5 GiB loop image that is already 82% full. A Fedora 43 image with the transcoding stack must fit, or the upgrade may fail.

**Measured unpacked root filesystem sizes:** 1.89 GiB (4.4.1), 1.94 GiB (4.4.2 and 4.4.3) and 2.13 GiB (4.4.4, which also carries `libva-utils` and `clinfo`); full table under "Published images". The root image on hs and e2 is 2.47 GiB with 1.9 GiB used today (439 MB free), so 4.4.1 to 4.4.3 should fit with about 0.5 GiB to spare, but **4.4.4 leaves only about 0.3 GiB** by the same measure, or less once ext4 overhead is counted. That is a tar-byte measurement of the file contents. If an in-place upgrade of hs or e2 does not resize the image, 4.4.4 is the step most likely to fail there; the reinstall guide avoids the problem by creating 5 GiB images. How `kairos-agent upgrade` sizes the new image when the source is larger than the current one is still not verified. Test on e1 first: it has 3 GiB images and 5.9 GB free on state.

The space freed on hs on 2026-11-06 was on `COS_PERSISTENT` (`/usr/local`, now 20 GB free). It does not change the image-size gate: the root image is still 82% full and `COS_STATE` still has 3.4 GB free.

## Risks and disruption

1. **Etcd quorum.** Three servers means quorum needs two healthy members. Upgrade one node at a time and wait for etcd to be healthy before the next.
2. **Single-replica workloads** go down during each node's reboot:
   - Auth: `authentik-server`, `authentik-worker`, `ak-outpost`, `vaultwarden`
   - Ingress and DNS: `traefik`, `coredns`, `metallb` controller
   - Storage: `local-path-provisioner`, `longhorn-driver-deployer`
   - Data: `postgres` (db, bazar, bazar-test), `redis-master`
   - Apps: `hass`, `radar`, `jellyfin`, `immich-server`, `sonarr`, `radarr`, `prowlarr`, `bazarr`, `homarr`, `seerr`, `qbit`, `kopia`, `gitea`, `headlamp`, `mosquitto`, `zigbee`

   Check where `traefik` and `authentik-server` are scheduled before choosing the order.
3. **Pod distribution:** hs 45, e2 33, e1 11.
4. **PodDisruptionBudgets.** Nine exist (postgres, redis, longhorn CSI). A PDB with zero allowed disruptions blocks `kubectl drain`. Check with `kubectl get pdb -A`.
5. **Unexplained reboot.** `hs` and `e2` both booted at `08:48:49` today, and many pods restarted about 12 hours ago. Find the cause first (`journalctl --list-boots`) before changing anything.
6. **Longhorn.** Volumes must be healthy with replicas on other nodes before a drain.
7. **K3s 1.35 changes** (from the v1.35.0 notes): containerd 2.1.5 (now 2.0.5), updated etcd and kine.
8. **GPU.** After each upgrade confirm `/dev/dri` exists and jellyfin and immich still see it. Fedora 43 may rename or drop packages from the F40 list (`intel-opencl`, `igt-gpu-tools`); the build result below shows whether it resolved.
9. **Component compatibility** with k8s 1.34/1.35 is not verified: cert-manager v1.21.2, Longhorn (version not confirmed, installed outside Helm), MetalLB, multus, Authentik 2026.8.3.
10. **Old agent upgrading to a new image.** The nodes run `kairos-agent v2.24.0` and will pull an image built by the v4.4.0 tooling. Not yet tested; the pilot on e1 covers it.

## Rollback

- **VM snapshots first.** The nodes are Proxmox VMs: `hs` on homeserver (192.168.31.84), `e2` on elitedesk-2 (192.168.31.86). The host for `e1` is not in CLAUDE.md. Snapshot or back up each VM before upgrading it. Longhorn data is on the same disk, so a snapshot is crash-consistent only. Prefer to take it with Longhorn volumes healthy and the node drained.
- **A/B partitions.** Kairos keeps the previous image on the passive partition. Pick the previous GRUB entry from the VM console. Not tested here; try it on e1.
- **Recovery image** on `COS_RECOVERY` is also old (2.5–3.5 GiB). Upgrade it only after the node has been healthy on the new image for a while.

## Procedure

### Phase 0: build and publish

Done. The four images are built, size-checked, pushed to Quay, and verified (see "Published images"). Remaining before the pilot: take the VM snapshot of e1 and find out the cause of today's 08:48 reboot on hs and e2.

### Phase 1: pilot on e1 (4 reboots, one component each)

Steps 4.4.1 → 4.4.2 → 4.4.3 → 4.4.4. At each step confirm: node `Ready`, kubelet version as expected, pods back, `/dev/dri` present, Longhorn healthy, nothing broken by `noexec /tmp`.

### Phase 2: e2 and hs (2 reboots each)

Jump straight to **4.4.3**, then **4.4.4**. 4.4.3 bundles the Kairos tooling, Fedora, and k3s 1.34 changes already validated individually on e1. Upgrade e2 fully, then hs (the most pods).

### Phase 3: finish

Upgrade recovery images, then change `install.source` in `/oem/90_custom.yaml` to a pinned tag.

### Per node, per step

```bash
# 1. VM snapshot (Proxmox) and etcd snapshot
ssh -i ~/.ssh/kairos kairos@<node-ip> 'sudo k3s etcd-snapshot save --name pre-<node>-<version>'
kubectl get nodes; kubectl -n longhorn-system get volumes.longhorn.io; kubectl get pdb -A

# 2. Drain, upgrade, reboot
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
ssh -i ~/.ssh/kairos kairos@<node-ip> 'sudo kairos-agent upgrade --source docker:quay.io/unconventionalmindset/kairos-fedora-transcoding:<tag>'
ssh -i ~/.ssh/kairos kairos@<node-ip> 'sudo reboot'

# 3. Verify, then uncordon
kubectl get node <node>
ssh -i ~/.ssh/kairos kairos@<node-ip> 'cat /etc/kairos-release | head; ls /dev/dri; df -h / /run/initramfs/cos-state'
kubectl uncordon <node>
```

Gates between nodes: all three nodes `Ready`; etcd has three healthy members; Longhorn volumes healthy; no pods Pending or crash-looping; a Traefik-routed URL and the Authentik login both work. The `kairos-agent upgrade` syntax has not been run on these nodes; confirm it on e1.

## Open decisions

- **CIS hardening:** skipped by default; adopt as its own later step or not at all?
- **Publishing:** the Quay repo is public, so these tags will be public.
- **Fedora 44:** not in the kairos-init matrix yet, so not used.
- **K3s 1.36 / 1.37:** both released; each needs its own step.
- **e1 hypervisor:** which Proxmox host runs `e1`, for the snapshot.

## Published images

Pushed to `quay.io/unconventionalmindset/kairos-fedora-transcoding` on 2026-11-06 and verified with `docker manifest inspect`. `latest` was not touched.

| Tag | Fedora | Kernel | K3s | Unpacked root fs | Digest |
|-----|--------|--------|-----|------------------|--------|
| `4.4.1-fedora40-k3s-1.33.4` | 40 | 6.14.5 | v1.33.4+k3s1 | 2,031,159,296 B (1.89 GiB) | `sha256:cbb0b44a81e1c3dbd8eb5396ad25fe553f8a3ad5e7dccb78ffa2a9e10bbba919` |
| `4.4.2-fedora43-k3s-1.33.4` | 43 | 7.2.15 | v1.33.4+k3s1 | 2,082,820,096 B (1.94 GiB) | `sha256:00de44cab4b7bc9d3fd6a1b247bb8cea34df98a0f1c9c868c555d1c5d7f592ad` |
| `4.4.3-fedora43-k3s-1.34.13` | 43 | 7.2.15 | v1.34.13+k3s1 | 2,087,685,120 B (1.94 GiB) | `sha256:34b136946999f5b52310c3eed51195557cc61670e29a5db8bb902a5811078fda` |
| `4.4.4-fedora43-k3s-1.35.10` | 43 | 7.2.15 | v1.35.10+k3s1 | 2,290,369,536 B (2.13 GiB) | `sha256:4a9c490ef6b158b2367afb0011e855777295b975cce188a07cebb0f2a6ad3242` |

**Important (2026-11-07): `4.4.1` to `4.4.3` cannot boot on Fedora.** `kairos-init` v4.4.0 persists `/etc/ssl/certs`, which is a symlink on Fedora, and immucore v4.4.0 treats the failed bind as fatal (`mkdir /sysroot/etc/ssl/certs: file exists`); the node reboot-loops. Only the current `4.4.4` has the fix. Do not use `4.4.1` to `4.4.3` for an upgrade unless they are rebuilt with `Dockerfile.byoi` step 1b and republished.

On 2026-11-07 the first 4.4.4 (digest `0706b348…`, without `libva-utils` and `clinfo`) and a short-lived 4.4.5 were removed, and the corrected image was republished as 4.4.4 so the version numbers stay on the Kairos 4.4 line with only four steps. Quay keeps replaced and deleted tags recoverable by digest for a while (the repo's tag expiry is 14 days), so the old digests may remain pullable until then.

What was checked inside two earlier local test builds of the same Dockerfile (Fedora 40 + k3s 1.33.4, and Fedora 43 + k3s 1.34.13). The four pushed images were then rebuilt from the final Dockerfile and were not re-inspected, apart from their sizes and registry digests:
- `/etc/kairos-release` shows the expected `KAIROS_VERSION`, flavor release, and k3s version.
- `k3s --version` matches the build arg, and `kairos-agent`, `immucore`, and the Kairos provider are present.
- Kernel, initrd, and `/boot/vmlinuz` link are in place.
- `intel-media-driver`, `intel-opencl`, `intel-gpu-firmware`, `igt-gpu-tools`, `nfs-utils`, `iscsi-initiator-utils`, and `systemd-networkd` are installed, including on Fedora 43 (the package names resolved).
- NetworkManager is absent, `systemd-networkd` and `iscsid` are enabled, and `firewalld` is disabled.
- The `kairos-init` binary is not left in the image.

**Not verified:** none of these images has been booted. Boot, networking, GPU access, and the `kairos-agent upgrade` path from a v3.5.x node are all untested until the e1 pilot. The pushed images include a fix for a duplicate `VARIANT_ID` line that the test builds had in `/etc/os-release`; that fix was not re-checked inside a pushed image.

**Fedora 43 kernel jump:** the nodes run 6.14.5 today and the Fedora 43 images carry 7.2.15. That affects the Intel GPU driver, iSCSI and ext4 for Longhorn, and kube-router's netfilter usage. It is why 4.4.2 isolates Fedora as its own step.

Build notes: `Dockerfile.byoi` uses `COPY --from` instead of `RUN --mount` because the build machine's Docker has no BuildKit/buildx. Build and push: `docker build -f Dockerfile.byoi --build-arg FEDORA_VERSION=<n> --build-arg K3S_VERSION=<tag> --build-arg IMAGE_VERSION=<semver> -t <repo>:<tag> .`
