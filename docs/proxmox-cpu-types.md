# Proxmox CPU Type Configuration Guide

This guide explains the different CPU types available in Proxmox VE and when to use each one.

## Quick Reference

**Most Common Questions:**

- **What CPU type for homelab K3s?** → `x86-64-v3` (if migration needed) or `host` (maximum performance)
- **Enable NUMA?** → **No** (numa 0) for VMs with ≤8 cores and <16GB RAM
- **host vs Skylake-Client?** → `host` = max performance, `Skylake-Client` = specific Intel gen
- **qemu64 vs kvm64?** → Use `kvm64`, never `qemu64` (too slow)
- **What is 'max'?** → All CPU features exposed, **not recommended** - use `host` instead

**Quick Selection Guide:**
```
Need VM migration?           → x86-64-v3
Don't need VM migration?     → host
Same CPU gen everywhere?     → Skylake-Client (or similar)
Mixed Intel/AMD?             → x86-64-v2-AES
Want all CPU features?       → host (not 'max')
Small VM (≤8 cores)?         → numa 0 (disabled)
Large VM (16+ cores)?        → numa 1 (enabled)
```

## Overview

Proxmox uses QEMU/KVM for virtualization, which can emulate different CPU models. The CPU type affects:
- VM performance
- Feature availability (CPU instructions/extensions)
- VM migration compatibility
- Live migration capability between different hardware

## Common CPU Types

### 1. host (CPU Passthrough)

**Description**: Passes through the physical CPU model directly to the VM.

**Advantages**:
- Maximum performance
- All CPU features/instructions available to VM
- Best for CPU-intensive workloads
- Native CPU performance

**Disadvantages**:
- Cannot migrate VMs between hosts with different CPUs
- Not compatible with live migration across different hardware
- VM tied to specific CPU generation

**Use Cases**:
- Single-host environments
- Workloads requiring specific CPU features
- Performance-critical applications
- GPU passthrough scenarios
- When you won't migrate VMs between different hardware

**Example Configuration**:
```
cpu: host
```

### 2. x86-64-v2-AES

**Description**: Generic x64 CPU with AES instruction support.

**Advantages**:
- Good compatibility across different Intel/AMD CPUs
- Supports modern encryption (AES-NI)
- Allows migration between similar CPU generations
- Balanced performance and compatibility

**Disadvantages**:
- Some performance overhead vs host
- May not support latest CPU features
- Less optimized than host passthrough

**Use Cases**:
- Multi-host clusters with mixed CPU generations
- When VM migration is needed
- Production environments requiring HA
- Workloads using encryption (databases, web servers)

**Example Configuration**:
```
cpu: x86-64-v2-AES
```

### 3. x86-64-v3

**Description**: More modern generic x64 with AVX2 and other extensions.

**Advantages**:
- Better performance than v2
- Supports AVX2 instructions (faster math/crypto)
- Good migration compatibility
- Modern feature set

**Disadvantages**:
- Requires newer CPUs (2013+ for Intel, 2015+ for AMD)
- Older hosts may not support it

**Use Cases**:
- Modern CPU clusters
- Scientific computing
- Video encoding/processing
- Applications using AVX2 optimizations

**Example Configuration**:
```
cpu: x86-64-v3
```

### 4. x86-64-v4

**Description**: Latest generic x64 with AVX-512 support.

**Advantages**:
- Highest performance generic type
- AVX-512 support for HPC workloads
- Latest instruction sets

**Disadvantages**:
- Requires very recent CPUs (2017+ Intel, 2020+ AMD)
- Limited hardware compatibility
- May not be supported on all hosts

**Use Cases**:
- High-performance computing
- AI/ML workloads
- Scientific simulations
- Latest hardware only

**Example Configuration**:
```
cpu: x86-64-v4
```

### 5. kvm64

**Description**: Basic x86-64 generic CPU model.

**Advantages**:
- Maximum compatibility
- Works on any x86-64 host
- Easiest for migration

**Disadvantages**:
- Lower performance
- Minimal CPU features
- No modern instruction sets (AES, AVX)

**Use Cases**:
- Very old CPU hosts
- Maximum migration flexibility
- Testing/development
- Not recommended for production

**Example Configuration**:
```
cpu: kvm64
```

### 6. qemu64

**Description**: Even more basic x86-64 CPU model than kvm64.

**Advantages**:
- Universal compatibility
- Works on absolutely any x86-64 host

**Disadvantages**:
- Very poor performance
- Absolute minimum CPU features
- No acceleration features whatsoever

**Use Cases**:
- Ancient hardware only
- Compatibility testing
- **Not recommended** - use kvm64 instead

**Example Configuration**:
```
cpu: qemu64
```

### 7. max

**Description**: Exposes ALL CPU features available on the host.

**Advantages**:
- Every possible CPU instruction available
- Maximum performance and features
- Good for testing what host supports

**Disadvantages**:
- Cannot migrate between different hardware
- Unpredictable - features change with hardware
- May expose CPU bugs/quirks
- Not recommended for production

**Use Cases**:
- Testing maximum CPU capabilities
- Benchmarking
- Development/debugging
- **Not for production** - use 'host' instead

**Example Configuration**:
```
cpu: max
```

**Warning**: 'max' is generally not recommended. Use 'host' for maximum performance in production.

### 8. Specific Intel CPU Models

**Description**: Emulates specific Intel CPU generations with their feature sets.

#### Common Intel Models:

**Skylake-Client** (6th/7th gen, 2015-2017):
- **Use when**: Cluster of Skylake/Kaby Lake CPUs
- **Features**: AVX2, AES-NI, good modern support
- **Migration**: Works across Skylake-gen Intel CPUs

**Example**:
```
cpu: Skylake-Client
```

**Haswell** (4th gen, 2013-2014):
- **Use when**: Cluster of Haswell CPUs
- **Features**: AVX2, AES-NI, TSX (some models)
- **Migration**: Works across Haswell-gen Intel CPUs

**Example**:
```
cpu: Haswell
```

**Broadwell** (5th gen, 2014-2015):
- **Use when**: Cluster of Broadwell CPUs
- **Features**: Similar to Haswell with refinements
- **Migration**: Works across Broadwell-gen Intel CPUs

**Example**:
```
cpu: Broadwell
```

**IvyBridge** (3rd gen, 2012-2013):
- **Use when**: Older Ivy Bridge cluster
- **Features**: AVX, AES-NI (no AVX2)
- **Migration**: Works across IvyBridge-gen Intel CPUs

**Example**:
```
cpu: IvyBridge
```

**SandyBridge** (2nd gen, 2011-2012):
- **Use when**: Older Sandy Bridge cluster
- **Features**: AVX, AES-NI
- **Migration**: Works across SandyBridge-gen Intel CPUs

**Example**:
```
cpu: SandyBridge
```

### 9. Specific AMD CPU Models

**Description**: Emulates specific AMD CPU generations.

#### Common AMD Models:

**EPYC** (Server, 2017+):
- **Use when**: AMD EPYC server cluster
- **Features**: Full modern instruction set, server optimizations
- **Migration**: Works across EPYC generation CPUs

**Example**:
```
cpu: EPYC
```

**EPYC-Rome** (2nd gen EPYC, 2019+):
- **Use when**: AMD EPYC Rome cluster
- **Features**: Enhanced over base EPYC
- **Migration**: Works across Rome-gen EPYC CPUs

**Example**:
```
cpu: EPYC-Rome
```

**Opteron_G5** (Piledriver, 2012-2015):
- **Use when**: Older AMD Opteron cluster
- **Features**: Limited modern instructions
- **Migration**: Works across Opteron G5-gen AMD CPUs

**Example**:
```
cpu: Opteron_G5
```

### When to Use Specific CPU Models vs Generic Types

**Choose Specific CPU Model (e.g., Skylake-Client) when**:
- All hosts in cluster have the same CPU generation
- You need predictable features across migrations
- Application requires specific CPU generation features
- You want tighter control than 'host' but more features than generic x86-64-vX

**Choose Generic Type (x86-64-v2/v3/v4) when**:
- Mixed Intel/AMD environment
- Different CPU generations in cluster
- Maximum migration flexibility needed
- You don't care about specific CPU model quirks

**Choose 'host' when**:
- Single host or no migration needed
- Maximum performance required
- GPU passthrough or PCIe passthrough

**Quick Decision Guide**:
```
Same CPU generation everywhere? → Specific model (e.g., Skylake-Client)
Mixed Intel/AMD or generations?  → Generic (x86-64-v3)
No migration ever needed?         → host
Need every feature possible?      → host (not 'max')
Ancient hardware?                 → kvm64 (not qemu64)
```

## CPU Type Decision Matrix

| Scenario | Recommended Type | Reason |
|----------|-----------------|--------|
| Single Proxmox host | host | Maximum performance |
| Cluster with identical CPUs | host or Skylake-Client | Best performance, still migratable |
| Cluster with same Intel gen | Skylake-Client/Haswell | Predictable features |
| Cluster with mixed Intel/AMD | x86-64-v2-AES | Compatibility |
| Modern cluster (2015+) | x86-64-v3 | Performance + compatibility |
| Latest hardware only | x86-64-v4 or host | Maximum features |
| High availability required | x86-64-v2-AES or v3 | Migration flexibility |
| Testing/development | x86-64-v2-AES | Good balance |
| GPU passthrough | host | Required for best compatibility |
| Old hardware (pre-2013) | kvm64 | Only option |
| Ancient hardware (pre-2010) | qemu64 | Last resort only |
| Testing host capabilities | max | Not for production |
| Homelab K3s (2-node, different CPUs) | x86-64-v3 | Migration + performance |
| Homelab K3s (no migration needed) | host | Maximum performance |

## CPU Flags and Features

Common CPU flags and what they enable:

- **AES-NI**: Hardware encryption acceleration (important for databases, HTTPS)
- **AVX/AVX2**: Advanced vector math (faster video encoding, scientific computing)
- **AVX-512**: Even faster vector operations (HPC, AI/ML)
- **VT-x/AMD-V**: Hardware virtualization (required for nested virtualization)
- **VT-d/AMD-Vi**: I/O virtualization (required for PCIe passthrough)

## Checking Host CPU Capabilities

### From Proxmox Host

```bash
# Show CPU model
cat /proc/cpuinfo | grep "model name" | head -1

# Show CPU flags
cat /proc/cpuinfo | grep flags | head -1

# Check for specific features
lscpu | grep -E "Model name|Flags"

# List available CPU types
qm showcpu
```

### From Proxmox Web UI

1. Select the host node
2. Go to "Summary"
3. Check "CPU(s)" field for model and features

## Configuring CPU Type

### Via Web UI

1. Select the VM
2. Go to "Hardware"
3. Double-click "Processors"
4. Select "Type" dropdown
5. Choose desired CPU type
6. Click "OK"

### Via CLI

```bash
# Set CPU type for VM 100
qm set 100 -cpu host

# Set with specific options
qm set 100 -cpu x86-64-v3,flags=+aes

# Show current CPU config
qm config 100 | grep cpu
```

### Via Configuration File

Edit `/etc/pve/qemu-server/<VMID>.conf`:

```
cpu: host
# or
cpu: x86-64-v2-AES
# or
cpu: x86-64-v3
```

## CPU Pinning (Advanced)

For maximum performance, you can pin VM vCPUs to specific physical cores:

```bash
# Pin VM 100 to cores 0-3
qm set 100 -vcpus 4 -cpulimit 4 -cpuunits 1024 -affinity 0-3
```

**Benefits**:
- Reduced cache thrashing
- Better NUMA locality
- Predictable performance

**Drawbacks**:
- Less flexibility
- Manual management required
- Can't overcommit CPUs

## NUMA (Non-Uniform Memory Access)

NUMA improves memory access patterns for large VMs by organizing memory into nodes that are local to specific CPUs.

### When to Enable NUMA

**Enable NUMA (numa 1) when**:
- VM has **16+ vCPUs**
- VM has **32GB+ RAM**
- VM spans multiple physical NUMA nodes on the host
- Running large databases or memory-intensive applications

**Disable NUMA (numa 0) when**:
- VM has **8 or fewer vCPUs** (most common)
- VM has **16GB or less RAM**
- VM fits within a single physical NUMA node
- Running typical homelab workloads (K3s, containers, web servers)

### NUMA Configuration

```bash
# Disable NUMA (recommended for small VMs)
qm set 100 -numa 0

# Enable NUMA (only for large VMs)
qm set 100 -numa 1
```

### Why NUMA Matters

**Small VMs (≤8 cores) with NUMA enabled**:
- ❌ Adds unnecessary overhead
- ❌ Can **hurt performance**
- ❌ Complicates memory management
- ❌ No benefit since VM fits in one NUMA node

**Large VMs (16+ cores) with NUMA disabled**:
- ❌ Poor memory locality
- ❌ Cross-node memory access slowdowns
- ❌ Suboptimal performance

**Rule of Thumb**:
```
Small VMs (1-8 cores, <16GB RAM):   numa 0 (disabled)
Medium VMs (8-16 cores, 16-32GB):   numa 0 (disabled)
Large VMs (16+ cores, 32GB+ RAM):   numa 1 (enabled)
```

### Checking Host NUMA Topology

Check your Proxmox host's NUMA configuration:

```bash
# View NUMA topology
numactl --hardware

# Show NUMA node info
lscpu | grep NUMA
```

Most consumer/prosumer hardware has a single NUMA node, making NUMA settings irrelevant for hosts.

### Homelab Recommendation

**For typical K3s VMs (4-8 cores, 8-16GB RAM)**:
```bash
# Keep NUMA disabled
qm set <VMID> -numa 0
```

This is the correct setting for 99% of homelab VMs.

## Migration Considerations

### Live Migration Requirements

For live migration to work between hosts:
1. Both hosts must support the chosen CPU type
2. CPU flags must be compatible
3. Use generic CPU types (x86-64-vX) for maximum compatibility

### Checking Migration Compatibility

```bash
# Test migration possibility (doesn't actually migrate)
pvecm migrate <VMID> <target-node> --test
```

### CPU Feature Masking

Hide features for compatibility:

```bash
# Hide AVX2 feature
qm set 100 -cpu host,-avx2
```

## Performance Tuning

### Enable CPU Host Cache Passthrough

Improves performance by passing through host cache topology:

```bash
qm set 100 -cpu host,flags=+pcid
```

### Adjust CPU Units (Priority)

Give more CPU time to important VMs:

```bash
# Default is 1024
# Higher = more priority
qm set 100 -cpuunits 2048
```

### CPU Limit

Limit maximum CPU usage:

```bash
# Limit to 50% of total CPU
qm set 100 -cpulimit 0.5
```

## Homelab Recommendations

For the current K3s cluster setup:

### Current Configuration Check
```bash
# Check VM CPU type on Proxmox hosts
ssh -i ~/.ssh/coreos root@192.168.31.84 "qm config <VMID> | grep cpu"
ssh -i ~/.ssh/coreos root@192.168.31.86 "qm config <VMID> | grep cpu"
```

### Recommended Settings

**For Homelab with 2 Different Proxmox Hosts**:
- Use `x86-64-v2-AES` or `x86-64-v3` for VM migration capability
- Enables moving VMs between homeserver and elitedesk-2
- Good balance of performance and flexibility

**If VMs Never Migrate**:
- Use `host` for maximum performance
- Best for static node assignments
- Optimal for K3s workloads

**Example VM Configuration**:
```bash
# For migration capability (recommended for 2-node cluster)
qm set <VMID> -cpu x86-64-v3 -cores 4 -numa 0

# For maximum performance (no migration needed)
qm set <VMID> -cpu host -cores 4 -numa 0

# Note: NUMA is disabled (numa 0) because typical K3s VMs
# have ≤8 cores and <16GB RAM. This is correct for homelab VMs.
```

**NUMA Settings for K3s VMs**:
```bash
# Small K3s node (4 cores, 8GB RAM) - NUMA disabled
qm set <VMID> -numa 0

# Medium K3s node (8 cores, 16GB RAM) - NUMA disabled
qm set <VMID> -numa 0

# Large K3s node (16+ cores, 32GB+ RAM) - NUMA enabled
qm set <VMID> -numa 1
```

**Recommended**: Keep NUMA disabled (numa 0) for typical homelab K3s nodes.

## Common Issues and Solutions

### Issue: VM won't start after changing CPU type
**Solution**: The new CPU type may not be supported by the host. Revert to a more generic type:
```bash
qm set <VMID> -cpu x86-64-v2-AES
```

### Issue: Performance degradation after changing from 'host'
**Solution**: This is expected. Consider:
1. Using x86-64-v3 instead of v2 for better performance
2. Returning to 'host' if migration isn't needed
3. Enabling CPU flags: `-cpu x86-64-v3,flags=+aes;+avx2`

### Issue: Migration fails with CPU incompatibility
**Solution**:
1. Use a more generic CPU type (x86-64-v2-AES)
2. Ensure target host supports the CPU type
3. Check CPU flags are compatible

### Issue: Application requires specific CPU instruction
**Solution**:
1. Use 'host' CPU type
2. Or add specific flag: `-cpu x86-64-v3,flags=+<instruction>`
3. Check if host CPU supports the instruction first

## References

- [Proxmox CPU Types Documentation](https://pve.proxmox.com/wiki/Qemu/KVM_Virtual_Machines#qm_cpu)
- [QEMU CPU Models](https://qemu.readthedocs.io/en/latest/system/qemu-cpu-models.html)
- x86-64 microarchitecture levels: v1 (basic), v2 (2009+), v3 (2015+), v4 (2017+)
