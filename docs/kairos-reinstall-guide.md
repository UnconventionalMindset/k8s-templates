# Reinstalling the cluster nodes on Proxmox (Kairos BYOI, Fedora 43)

Fresh install of all three K3s nodes from your own image on Quay, then bring the cluster up with the main [README](../README.md).

| Node | Proxmox host | Node IP | Hostname | k3s node name | Role (install order) |
|------|--------------|---------|----------|---------------|----------------------|
| e1 | elitedesk-1 (192.168.31.85) | 192.168.31.191 | kairos-fed-k3s-e1 | `e1` | **first server** (`--cluster-init`), install 1st |
| e2 | elitedesk-2 (192.168.31.86) | 192.168.31.192 | kairos-fed-k3s-e2 | `e2` | joins e1, install 2nd |
| hs | homeserver (192.168.31.84) | 192.168.31.193 | kairos-fed-k3s-hs | `hs` | joins e1, install 3rd |

`e1` is the master (first) server: it initialises the cluster, creates the join token, and is the join endpoint `https://192.168.31.191:6443` for the other two. All three are control-plane and etcd servers once the cluster is up.

Keep the node names. `apps/media/jellyfin/jellyfin.yaml` pins Jellyfin to `nodeName: hs`.

**Status (2026-11-07).** The first install attempt failed: `e1` installed the earlier `4.4.4` image and reboot-looped in the initramfs (`mkdir /sysroot/etc/ssl/certs: file exists`; see Troubleshooting). `4.4.4` was republished with the fix and a new ISO was built from it. `e1` was then reinstalled from it and **booted correctly**: SSH with `~/.ssh/kairos` works, `KAIROS_VERSION=v4.4.4` on kernel 7.2.15, the static IP is up, k3s v1.35.10 is `Ready` as the first server, the partition layout matches section 5 exactly, and the GPU driver and VA-API work (checked from this machine after boot, details in section 10). `e2` then joined `e1` with the token and is `Ready` on the same versions (seen from `kubectl get nodes` after I switched `~/.kube/config` to `e1` at about 01:30), so the token flow in step 6 works for `e2`. `hs` had not joined yet, and none of section 9 (the README apps) has been run on the new cluster. The new ISO is uploaded under its full file name to all three Proxmox hosts and attached to VMs 301, 302 and 303. The old VMs (201, 202, 203) have been deleted.

## 0. Read first: three things that would break the install

1. **Use a plain Ed25519 key for the nodes.** `~/.ssh/kairos` is now a plain `ssh-ed25519` key (checked 2026-11-07: the private and public halves match, and it has no passphrase), which is what the nodes need. The earlier `kairos` key was type `ssh-mldsa44-ed25519`, and the sshd in the Fedora 43 image (OpenSSH 10.0p1) does not list that type among the key types it accepts (`ssh -Q key` inside the image), so a node installed with that key would have been unreachable over SSH. Do not switch back to a post-quantum hybrid key until the image's OpenSSH supports it. `~/.ssh/kairos` is the only key installed on the nodes, with no fallback key and no console password, so keep a backup of it: losing it means reinstalling the nodes.
2. **Never put the k3s token in the public config repo.** The node configs are installed from `github.com/UnconventionalMindset/kairos-setup`, which is public. Before 2026-11-07 its `kairos-e1.yaml` and `kairos-e2.yaml` contained the cluster `K3S_TOKEN` in plain text. The current files carry no real token: `e1` has none (it generates one on first boot) and `e2` and `hs` have the placeholder `REPLACE_WITH_TOKEN_FROM_E1`, which you replace on the node at install time (step 6). Removing it from the current files does not remove it from the repo's git history, so treat the old token as exposed and do not reuse it. The new cluster generates its own token on `e1`, so the old one stops mattering once the old cluster is gone.
3. **Watch homeserver's disk.** On homeserver `local` is the Proxmox **root filesystem** (`/dev/mapper/pve-root`), so filling it can take the host down, not just the VM. On 2026-11-07 it had 85 GiB free (61% used) after the old VM 203 was deleted, which is enough for VM 303's thin 120 GiB disk (about 40 GiB once installed). Check `df -h /var/lib/vz` on homeserver now and then; other stopped VMs there (101, 999, 1111) still hold space. elitedesk-2 (191 GiB free) and elitedesk-1 (150 GiB free) have plenty of room.

## 1. What you are installing

Image: `quay.io/unconventionalmindset/kairos-fedora-transcoding:4.4.4-fedora43-k3s-1.35.10` (digest `sha256:4a9c490ef6b158b2367afb0011e855777295b975cce188a07cebb0f2a6ad3242`, on Quay since 2026-11-07)

| Component | Version |
|-----------|---------|
| Fedora | 43 (kernel 7.2.15) |
| Kairos tooling | kairos-init v4.4.0 (image version `4.4.4`) |
| K3s | v1.35.10+k3s1 |
| Extra | Intel GPU stack (`intel-media-driver`, `intel-opencl`, `intel-gpu-firmware`, `igt-gpu-tools`), plus `libva-utils` and `clinfo` for checking, `nfs-utils`, `iscsi-initiator-utils`, `systemd-networkd` (NetworkManager removed) |

K3s 1.35.10 was released 2026-11-03. Kubernetes 1.34 should be at or near end of life by now going by the usual 14-month window (I did not look up the exact date). The apps in the README (Longhorn v1.12.1, cert-manager v1.21.2, MetalLB v0.16.1, kube-router v2.11.1, Traefik chart 41.5.0, Authentik 2026.8.3) have **not** been checked against Kubernetes 1.35. If you want a safer start, install `4.4.3-fedora43-k3s-1.34.13` instead (same OS, no `libva-utils`/`clinfo`).

Do not use `:latest`. It still points at the old Kairos 3.5.3 / Fedora 40 image.

## 2. Prepare on your workstation

There is nothing to render or serve locally. The node configs are in the public repo `UnconventionalMindset/kairos-setup` (cloned at `~/proj/kairos-setup`) and are installed straight from their raw URLs:

| Node | Raw URL |
|------|---------|
| e1 (first server) | `https://raw.githubusercontent.com/UnconventionalMindset/kairos-setup/master/kairos-e1.yaml` |
| e2 | `https://raw.githubusercontent.com/UnconventionalMindset/kairos-setup/master/kairos-e2.yaml` |
| hs | `https://raw.githubusercontent.com/UnconventionalMindset/kairos-setup/master/kairos-hs.yaml` |

They were last pushed on 2026-11-07 (commit `447ecdc`, which made `e1` the first server). I checked that all three raw URLs serve that content and parse as YAML; GitHub caches raw files briefly, so a fresh push can take a few minutes to show up. Each config:
- installs the pinned image `quay.io/unconventionalmindset/kairos-fedora-transcoding:4.4.4-fedora43-k3s-1.35.10` (not `:latest`), so installing from the wrong ISO cannot pull the old OS
- authorizes only `~/.ssh/kairos.pub` (plain Ed25519) for the `kairos` user: no `github:` entry, no RSA key, no password
- sets the disk layout from section 5 (`state` 32768 MiB and so on) and a static IP matched with `en*`
- contains **no token**: `e1` generates one on first boot, and `e2`/`hs` carry the placeholder `REPLACE_WITH_TOKEN_FROM_E1` (where to get the real token: step 6, "The k3s token")

Before installing, check that your node key is the plain Ed25519 one (it must say `(ED25519)`):

```bash
ssh-keygen -lf ~/.ssh/kairos.pub
```

To change a config, edit it in `~/proj/kairos-setup`, commit, and push; the raw URL updates within a few minutes.

## 3. Installer ISO

**Use an ISO built from your own image, not an official one.** Since Kairos v4 the official ISOs (for example `kairos-hadron-v0.6.3-standard-amd64-generic-v4.4.0-k3sv1.37.1+k3s1.iso`) contain Hadron, not Fedora, and the Fedora flavor repos are no longer updated. An ISO built from your Quay image installs exactly that image with no pull at install time.

**The ISO has been built from the fixed 4.4.4 image** (digest `sha256:4a9c490ef6b158b2367afb0011e855777295b975cce188a07cebb0f2a6ad3242`) on 2026-11-07, using the command below, and is in `~/proj/kairos-transcoding/build-fixed/`:

- File (keep this full name, AuroraBoot generates it): `kairos-fedora-43-standard-amd64-generic-v4.4.4-k3sv1.35.10+k3s1.iso` (1,066,598,400 bytes, about 1.0 GiB)
- SHA-256: `ed693b0361c827ffed2d31c17ab487ffb7cbb0696bfc7e0899c41357efe394ad` (matches the `.sha256` file next to it)
- It is uploaded under that same full name to the ISO storage of all three Proxmox hosts (checksum verified on each host) and attached to VMs 301, 302 and 303.
- Checked: it is a bootable ISO 9660 image with volume label `COS_LIVE`, top-level entries `boot`, `EFI`, `rootfs.squashfs` and `config.yaml`, and its embedded `config.yaml` is empty, so nothing is pre-configured.
- **Not tested:** it has not been booted. `qemu` is not installed on the build machine.
- The older ISO in `~/proj/kairos-transcoding/build/` (SHA-256 `390915d1…cfd3d84`) has the **same file name** but was built from the broken image. Do not use it. The hosts also still hold an older, short-named copy (`kairos-fedora43-4.4.4.iso`) that nothing references any more; you can delete it in the Proxmox UI.

Because each config pins `install.source` to the Quay tag, the installed system comes from Quay, not from the ISO; the ISO is the installer environment.

To rebuild it (peak free disk used was about 4.7 GB; the files come out owned by `root` because Docker writes them, which is fine for `scp` but needs `sudo` to delete). Use a new output directory so an old ISO with the same name is never overwritten:

```bash
docker pull quay.io/unconventionalmindset/kairos-fedora-transcoding:4.4.4-fedora43-k3s-1.35.10
mkdir -p build-fixed
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/build-fixed":/output \
  quay.io/kairos/auroraboot:v0.28.0 \
  build-iso --output /output/ \
  oci:quay.io/unconventionalmindset/kairos-fedora-transcoding:4.4.4-fedora43-k3s-1.35.10
ls -lh build-fixed/      # the .iso and its .sha256, named after the image
```

Upload it to each Proxmox host's ISO storage **under its full name** (the `.part` name keeps Proxmox from listing a half-copied file; the checksum is checked before the rename):

```bash
cd ~/proj/kairos-transcoding/build-fixed
ISO='kairos-fedora-43-standard-amd64-generic-v4.4.4-k3sv1.35.10+k3s1.iso'
sha256sum -c "$ISO.sha256"
for h in 192.168.31.84 192.168.31.86 192.168.31.85; do
  scp -i ~/.ssh/coreos "$ISO" root@$h:"/var/lib/vz/template/iso/$ISO.part"
  ssh -i ~/.ssh/coreos root@$h "cd /var/lib/vz/template/iso && sha256sum '$ISO.part' && mv '$ISO.part' '$ISO'"
done
```

(Compare the printed checksum with `ed693b03…efe394ad` before trusting the `mv`.) Attach it to a VM with `qm set <id> --ide2 'local:iso/kairos-fedora-43-standard-amd64-generic-v4.4.4-k3sv1.35.10+k3s1.iso,media=cdrom'`.

Do not bake a cloud-config into the ISO: each node needs its own, and they are installed from the raw URLs in step 6.

## 4. Proxmox VMs

**These VMs were created on 2026-11-07.** They mirror the old VMs (read from `/etc/pve/qemu-server/*.conf` before those were deleted), changing the disk size, memory, and the ISO. The ISO (`local:iso/kairos-fedora-43-standard-amd64-generic-v4.4.4-k3sv1.35.10+k3s1.iso`, uploaded to all three hosts and checksum-verified on each) is attached on `ide2` of every VM. State when I last looked: VM 301 and 302 stopped, VM 303 running (it had written only 19 MB to its disk, so it looked to be sitting at the live installer).

| Setting | hs | e2 | e1 |
|---------|----|----|----|
| Host | homeserver (192.168.31.84) | elitedesk-2 (192.168.31.86) | elitedesk-1 (192.168.31.85) |
| VM ID | 303 | 302 | 301 |
| Name | hs-kairos-fedora43 | e2-kairos-fedora43 | e1-kairos-fedora43 |
| Memory | 16384 MiB | 12288 MiB | 12288 MiB (the old e1 had 8096) |
| Cores / sockets | 4 / 1 | 4 / 1 | 4 / 1 |
| CPU type | host | host | host (the old e1 used `x86-64-v2-AES`) |
| Disk | 120 GiB, VirtIO Block, iothread, qcow2 on `local` | same | same |
| PCI passthrough (iGPU) | `0000:00:02,rombar=0` | `0000:00:02` | `0000:00:02` |
| MAC | `BC:24:11:49:BA:5A` | `BC:24:11:A4:EF:C7` | `BC:24:11:9E:6F:3E` |
| Start at boot | on (I created them with it off; you turned it on) | on | on |

Common settings: machine `i440fx` and BIOS `SeaBIOS` (the defaults; **do not switch to q35/OVMF**, because iGPU passthrough works as is), SCSI controller VirtIO SCSI single, network VirtIO on `vmbr0` with firewall on, QEMU guest agent on, OS type Linux, tags `fedora;k3s;kairos`, boot order disk then CD-ROM (an empty disk falls through to the ISO).

**The old VMs (203, 202, 201) have been deleted**, so there is no longer a clash over IPs or the iGPU, and *start at boot* is on for the new VMs. If you ever bring an old VM back, keep it stopped while the new one on that host runs, because both reference `0000:00:02`.

**VM 301 (`e1`) still has the broken first install on its disk.** Boot order is disk first (`order=virtio0;ide2`), so starting it boots the broken system and reboot-loops. To reinstall `e1` from the ISO, boot from the CD-ROM once: `qm set 301 --boot 'order=ide2;virtio0'`, run the install, then eject the ISO (`qm set 301 --ide2 none,media=cdrom`) and set the order back with `qm set 301 --boot 'order=virtio0;ide2'`. VMs 302 and 303 have empty disks, so they fall through to the ISO by themselves.

Reference command used (for hs; ID, memory, name, and `hostpci0` differ per node):

```bash
qm create 303 --name hs-kairos-fedora43 --tags 'fedora;k3s;kairos' \
  --ostype l26 --memory 16384 --cores 4 --sockets 1 --cpu host --numa 0 \
  --agent 1 --onboot 0 --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr0,firewall=1 \
  --virtio0 local:120,iothread=1,format=qcow2 \
  --ide2 'local:iso/kairos-fedora-43-standard-amd64-generic-v4.4.4-k3sv1.35.10+k3s1.iso,media=cdrom' \
  --boot 'order=virtio0;ide2' \
  --hostpci0 0000:00:02,rombar=0
```

If your router has DHCP reservations or firewall rules keyed to the old MAC addresses, copy the old `net0` MAC onto the new VM (`qm set <id> --net0 virtio=<old-mac>,bridge=vmbr0,firewall=1`). The nodes use static IPs, so this only matters for router-side rules.

Only one VM can own a host's iGPU at a time, and the old and new VMs both reference `0000:00:02`. Keep the old VM on that host stopped while the new one runs. The `haos` VM on elitedesk-1 has no PCI passthrough, so it does not conflict with e1. To start a node: `qm start 301` on elitedesk-1 (e1), `qm start 302` on elitedesk-2 (e2), `qm start 303` on homeserver (hs), once you are ready to run its install in step 6.

## 5. Disk and partition sizing

Kairos stores the OS as image files: `active.img` and `passive.img` on the state partition, `recovery.img` on the recovery partition. Today's nodes use 2.5 GiB images in an 8.2 GiB state partition and a 5.1 GiB recovery partition. They fit, but with almost no room (hs's root image is 82% full), which is why a bigger image is a problem for a later upgrade.

The 4.4.4 image holds about 2.13 GiB of files (measured; 4.4.3, which lacks `libva-utils` and `clinfo`, was 1.94 GiB). The layout in the `kairos-setup` configs:

| Partition / image | Size | Why |
|-------------------|------|-----|
| `COS_OEM` | 64 MiB | Holds the cloud config. 64 MiB is what the current nodes have. |
| `system` and `passive` images | 5120 MiB each | About 2.3x the current content, so the OS can grow. |
| `COS_STATE` | 32768 MiB | Doubled from the first plan (16384). active + passive + one temporary image during an upgrade is 3 x 5120 = 15360 MiB at today's image size, so 32 GiB also covers system images up to roughly 10 GiB each (3 x 10 GiB) before the state partition becomes the limit. The temporary-image part is inferred from how the current partitions are sized, not documented. |
| `recovery-system` image | 4096 MiB | About 1.9x the content. |
| `COS_RECOVERY` | 9216 MiB | Twice the recovery image plus slack, so the recovery image can be upgraded in place (same inference). |
| `COS_PERSISTENT` | the rest (about 79 GiB on a 120 GiB disk) | The k3s containerd image store is about 21 GiB today and grows with every image. Longhorn data on the nodes is small (two volumes, about 270 MB actually used). Everything else in your PVCs is NFS on TrueNAS. |

**Proxmox disk size: 120 GiB per node.** The partitions before persistent add up to about 41 GiB (64 MiB + 32 GiB + 9 GiB), which leaves about 79 GiB for persistent. The image sizes in the `kairos-setup` configs stay at 5120 MiB for `system` and `passive`: that is what lets the OS grow, and the 32 GiB state partition leaves room to raise it later. The disk is thin-provisioned qcow2, so it only uses what is written, but the host still needs that real space (see section 0, item 3, for homeserver).

These keys come from the Kairos configuration reference (`install.partitions.<name>.size`, `install.system.size`, `install.passive.size`, `install.recovery-system.size`, all in MiB; a persistent size of 0 takes the rest). After the first install, confirm the layout was applied (step 8) before doing the other two nodes.

Before any future upgrade check `df -h /run/initramfs/cos-state` and compare with the new image's size.

## 6. Install each node (e1 first)

Install in this order: **e1, e2, hs**. `e1` initialises the cluster; `e2` and `hs` join through it (`https://192.168.31.191:6443`), so `e1` has to be up first. `hs` goes last, which also gives you time to free space on homeserver (section 0, item 3). The install erases `/dev/vda`.

### e1 (first server)

1. Start the VM (`qm start 301` on elitedesk-1) and open its console in Proxmox. It boots the ISO because the disk is empty.
2. Get a shell on the live system the way you do today for `kairos-agent manual-install`. The ISO's GRUB menu has `Kairos (install)` (the default), `Kairos (boot local node from livecd)` and `Kairos (debug)`. I have not tested which entry gives you the shell on this ISO or what the live login is.
3. Download the config and install from the local copy. (`e1` was first installed straight from the raw URL, which worked, but `manual-install <URL>` makes Kairos store that URL and retry it at every boot, which produces the harmless `could not fetch config_url` warning described in Troubleshooting. A local copy avoids it. The `kairos-setup` README still shows the direct-URL form for `e1`.)
   ```bash
   curl -fsSL https://raw.githubusercontent.com/UnconventionalMindset/kairos-setup/master/kairos-e1.yaml > kairos-e1.yaml
   sudo kairos-agent manual-install kairos-e1.yaml
   ```
4. It partitions the disk, installs the pinned image, and reboots. The first boot from disk takes a few minutes while k3s starts. Detach the ISO afterwards (Proxmox: Hardware, CD/DVD drive, "Do not use any media").
5. **Test your key and read the cluster token.** This SSH call is also the check that your key works. If it is refused, stop here: there is no console password, so fixing it means reinstalling `e1` (fix the config in `kairos-setup` first).
   ```bash
   ssh -i ~/.ssh/kairos kairos@192.168.31.191 'sudo k3s kubectl get nodes'          # e1 Ready
   ssh -i ~/.ssh/kairos kairos@192.168.31.191 'sudo cat /var/lib/rancher/k3s/server/token'
   ```
   Copy the output now. The next section explains what it is and how to handle it.

### The k3s token

**Where it comes from.** You never choose it. `e1`'s config sets no token, so K3s creates a random one the first time `e1` starts, and K3s docs say the server token is always written to `/var/lib/rancher/k3s/server/token` on `e1`. Read it from `e1` after `e1` is up:

```bash
ssh -i ~/.ssh/kairos kairos@192.168.31.191 'sudo cat /var/lib/rancher/k3s/server/token'
```

It is a long string that starts with `K10` (109 characters on e1). On k3s 1.35.10 `token` is the real file, and `node-token` and `agent-token` are symlinks to it (checked on e1), so either path returns the same value; `token` is the one the K3s docs name for the server token.

**What it is.** The server token joins both servers and agents, and anyone who has it effectively has cluster-admin access. Keep it out of git, out of the public `kairos-setup` repo, and out of chat. K3s also uses it to encrypt the cluster's bootstrap data, so you need it to restore an etcd snapshot: **store a copy in your password manager now**. By default the agent token is the same value, so you don't need a second one.

**Where it goes.** Into `kairos-e2.yaml` and `kairos-hs.yaml`, on the node, replacing the placeholder `REPLACE_WITH_TOKEN_FROM_E1`, as in the next section. `e1` itself needs no edit.

### e2, then hs

For each (`qm start 302` on elitedesk-2, then `qm start 303` on homeserver after freeing space), get a shell on the live system as above, then download the config, put the token in, and install from the local copy:

```bash
curl -fsSL https://raw.githubusercontent.com/UnconventionalMindset/kairos-setup/master/kairos-e2.yaml > kairos-e2.yaml   # kairos-hs.yaml for hs
# the token is the output of this on your workstation (see "The k3s token" above):
#   ssh -i ~/.ssh/kairos kairos@192.168.31.191 'sudo cat /var/lib/rancher/k3s/server/token'
vi kairos-e2.yaml          # replace REPLACE_WITH_TOKEN_FROM_E1 with that token (same for kairos-hs.yaml)
sudo kairos-agent manual-install kairos-e2.yaml
```

After each node reboots, detach its ISO and wait until it shows `Ready` in `kubectl get nodes` before starting the next one.

If you ever reinstall `e1` again while the others are running, edit its config to use `- --server https://192.168.31.192:6443` instead of `- --cluster-init`, otherwise it will start a separate cluster.

## 7. Get the kubeconfig

```bash
cp ~/.kube/config ~/.kube/config.old-cluster      # the current file holds the old cluster's credentials
ssh -i ~/.ssh/kairos kairos@192.168.31.191 'sudo cat /etc/rancher/k3s/k3s.yaml' \
  | sed 's#https://127.0.0.1:6443#https://192.168.31.191:6443#' > ~/.kube/config
chmod 600 ~/.kube/config
kubectl get nodes -o wide      # e1, e2, hs: roles control-plane,etcd (k3s 1.35 shows no `master` role; seen on e1); v1.35.10+k3s1
```

## 8. Check the install itself

On each node:

```bash
ssh -i ~/.ssh/kairos kairos@<node-ip>
lsblk -o NAME,SIZE,LABEL,MOUNTPOINT          # state ~32G, recovery ~9G, persistent ~79G
sudo ls -la /run/initramfs/cos-state/cOS      # active.img and passive.img, about 5 GiB each
df -h / /run/initramfs/cos-state /usr/local
grep -E 'KAIROS_(VERSION|FLAVOR_RELEASE|SOFTWARE_VERSION)' /etc/kairos-release   # v4.4.4, 43, v1.35.10+k3s1
grep PRETTY_NAME /etc/os-release              # Kairos - Fedora Linux (Container) - transcoding
uname -r                                      # 7.2.15-100.fc43.x86_64
```

If the sizes are wrong, the keys were not applied. Reinstall that node before moving on rather than discovering it at the next upgrade.

## 9. Bring up the cluster

Follow the main README top to bottom. The order matters in a few places:

1. **Kube router**, then **Metal LB** (including `apps/admin/metallb/ipaddress_pools.yaml`), before anything else needs networking or a LoadBalancer IP.
2. **Secrets handling** (GPG, helm-secrets) before any app that uses `secrets/*.yaml`.
3. **Cert Manager**, **Traefik** (apply the CRDs first, as written), the **Further Traefik** reverse proxies, and **Longhorn**.
4. **Certificates**: staging first, check it issues, then production.
5. **Postgres**, **Redis**, **Authentik**, then the interfaces (Headlamp, Radar, K8s dashboard).
6. **Mosquitto**, **Zigbee**, **K3s multus**, **Home Assistant**, **Code**, **Jellyfin**, the **RR** stack, and the rest in README order.

Persistent data for most apps is on NFS. Your static PVs (`*-volume+claim.yaml`) point back at the same TrueNAS paths, so applying them reattaches the existing data. Longhorn volumes on the old nodes are not recovered: the only ones were a 10 GiB test volume (`bazar-test/minio`, about 270 MB used) and a 1 MiB runner volume.

Your new cluster's Kubernetes objects and secrets come only from the repo and the (git-ignored) `secrets/` directory. Make sure `secrets/` is complete before you start.

## 10. Verify the transcoding packages are reachable

**On each node** (the iGPU must be passed through, step 4):

```bash
ls -l /dev/dri                       # card0, card1, renderD128; renderD128 group is "render"
getent group render video            # render:x:105, video:x:39 (these must match jellyfin.yaml)
for c in /sys/class/drm/card[01]; do echo "$(basename $c): $(readlink $c/device/driver | xargs basename) $(cat $c/device/vendor) $(cat $c/device/device)"; done   # card1: i915 (or xe), vendor 0x8086; card0 is the emulated VGA (bochs-drm). lspci is NOT installed in the image
sudo dmesg | grep -Ei 'i915|xe |guc|huc|firmware' | tail -n 20   # firmware loaded, no "failed"
rpm -q intel-media-driver intel-opencl intel-gpu-firmware igt-gpu-tools libva-utils clinfo
sudo intel_gpu_top -L                # lists the GPU
vainfo --display drm --device /dev/dri/renderD128    # expect "Intel iHD driver", a list of VAProfile/VAEntrypoint lines incl. VAEntrypointEncSlice; the supported codecs depend on the GPU generation
clinfo | grep -i 'device name'       # may legitimately say "Number of platforms 0", see the note below
```

The image's libva already searches `/usr/lib64/dri-nonfree/` (checked in the published 4.4.4 image: its compiled-in search path is `dri`, `dri-freeworld`, `dri-nonfree`), and that is where `intel-media-driver` installs `iHD_drv_video.so`. So `vainfo` should find it without help. If it still reports no `iHD` driver, force the path:

```bash
LIBVA_DRIVERS_PATH=/usr/lib64/dri-nonfree vainfo --display drm --device /dev/dri/renderD128
```

**What `e1` actually showed (2026-11-07, from this machine, the check is yours to repeat on `e2` and `hs`):** `/dev/dri` has `card0`, `card1`, `renderD128` (`renderD128` mode 666 group `render`, GID 105; `video` is 39); `card1` is bound to `i915` (Intel `8086:1912`, a **Skylake / Gen9 HD 530**) and loaded its DMC firmware; `vainfo` loads `/usr/lib64/dri-nonfree/iHD_drv_video.so` (iHD 26.1.5, libva 2.22) and lists 10 encode entrypoints with H.264 and HEVC decode, and no VP9 or AV1 decode. Two things look like faults but are expected for this machine: dmesg says `[ENCODER:...] failed to retrieve link info, disabling eDP` (no display is attached to a passed-through iGPU), and `clinfo` reports `Number of platforms 0` even though the Intel OpenCL runtime and its ICD are installed. My reading of that last one, not verified, is that current Intel OpenCL (NEO) builds do not support Gen9, so it would not recover; it only matters for OpenCL features such as HDR tone mapping. Jellyfin is pinned to `hs` (an Alder Lake-N), so repeat `vainfo` and `clinfo` there before judging the transcoding setup. The Jellyfin container brings its own userspace; the node only has to provide the driver, firmware, device nodes and group IDs.

The group IDs matter because Jellyfin runs with `supplementalGroups: [105, 39]`. The Fedora 43 image uses `render=105` and `video=39`, matching the manifest.

**In the cluster, once Jellyfin is up:**

```bash
kubectl -n jellyfin exec deploy/jellyfin -- ls -l /dev/dri     # card0, card1, renderD128 visible
kubectl -n jellyfin exec deploy/jellyfin -- id                  # groups include 105 and 39
kubectl -n jellyfin get pod -o wide                             # running on node hs
```

Then in Jellyfin, Dashboard, Playback, Transcoding: enable VAAPI (or QSV) with device `/dev/dri/renderD128`, enable hardware decoding for the codecs you use, and play something that forces a transcode. While it plays, run `sudo intel_gpu_top` on `hs` and watch the Video engine. The Jellyfin transcode log should show a `*_vaapi` or `*_qsv` encoder. Jellyfin brings its own userspace in its container, so the node only has to provide the kernel driver, firmware, `/dev/dri`, and the group IDs.

## 11. Later upgrades

Build a new image tag from `~/proj/kairos-transcoding` (see its README), then per node:

```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
ssh -i ~/.ssh/kairos kairos@<node-ip> 'sudo kairos-agent upgrade --source docker:quay.io/unconventionalmindset/kairos-fedora-transcoding:<tag>'
ssh -i ~/.ssh/kairos kairos@<node-ip> 'sudo reboot'
kubectl uncordon <node>
```

This syntax has not been run on these nodes. One node at a time, wait for etcd and Longhorn to settle between nodes, take a Proxmox snapshot first, and check free space on `COS_STATE` first.

## Troubleshooting

- **Locked out over SSH**: the key type problem in section 0, or the wrong key file. The config sets no password for the `kairos` user, so there is no console login to fall back on; fixing a bad key means reinstalling that node. That is why step 6 has you test SSH on `e1` before installing the others.
- **Boot loop after install, console shows `mkdir /sysroot/etc/ssl/certs: file exists`** (seen on `e1` on 2026-11-07). The failure is in immucore, in the initramfs. On Fedora `/etc/ssl/certs` is a symlink, but Kairos lists it as a path to persist, and a bind onto a symlink cannot work (upstream kairos-io/kairos#4755 and #4901). Up to Kairos v4.3 that was only a logged error. **Kairos v4.4.0 makes any failed persistent bind fatal**, and the kernel line has `rd.emergency=reboot rd.shell=0`, so the node reboots forever instead of opening a shell. The `4.4.4-fedora43-k3s-1.35.10` image was republished on 2026-11-07 with the entry removed from `/system/oem/00_rootfs.yaml` (build step 1b in `Dockerfile.byoi`). `4.4.1` to `4.4.3` still have the bug and cannot boot on Fedora. A node that already installed the broken image cannot repair itself; reinstall it from the ISO with the fixed image.
- **Boot log shows `could not fetch config_url ... lookup raw.githubusercontent.com ... connection refused ... Booting without it`**: harmless, and checked on `e1`. Installing with `manual-install <URL>` stores that URL as `config_url:` in `/oem/90_custom.yaml` (not on the kernel line). At every boot immucore tries to fetch it from the initramfs, about 9 seconds before `systemd-networkd` brings the link up (`ens18: Gained carrier` came at 00:23:27, the warning at 00:23:18), so DNS has no resolver yet and the fetch fails with `Booting without it`. The config was already saved on the disk at install time and is used regardless: the same boot reached k3s `Ready`. I found no later fetch of the URL in that boot's journal. The caveat: if the network were ever up that early, the file in the public repo would be fetched and applied at every boot, so anyone who can push to `kairos-setup` could change your nodes. To avoid the whole thing, install from a local copy (what steps 6 now do), or remove the `config_url:` line from `/oem/90_custom.yaml` on the node. I have not tested the removal.
- **Node does not join**: the token pasted into `kairos-e2.yaml` / `kairos-hs.yaml` does not match the one in `/var/lib/rancher/k3s/server/token` on e1 (or is still the `REPLACE_WITH_TOKEN_FROM_E1` placeholder), e1 is not up yet, or `192.168.31.191:6443` is not reachable from the joining node.
- **`/tmp` is `noexec`** on Kairos v4: anything that runs a binary from `/tmp` fails. This is set by the OS image and is not disabled by skipping CIS hardening.
- **CIS hardening** (account lockout including root, 14-character passwords, `su` limited to wheel) is skipped in these images. Adopting it is a separate decision.
