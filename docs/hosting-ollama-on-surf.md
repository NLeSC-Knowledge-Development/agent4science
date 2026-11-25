# Hosting Ollama on a SURF Research Cloud GPU node

**The short version.** Install Ollama as a native binary on the GPU node. Point its model
directory at the fast scratch disk, never the root disk. Keep the server on loopback. Reach
it from your laptop with an SSH port forward. Because the server opens no routable port, SSH
is your only layer of authentication.

This page assumes you already have SURF Research Cloud access and know your way around it.
The two notes below explain who wrote the page and how to read the placeholders. Read them
once, then start at [What you build](#what-you-build).

!!! info "How this page was written"
    A human and an AI model wrote this page. The human set the scope, chose the design, and
    reviewed the result. The model wrote the prose and the commands.

    Model: `qwen3.8-flash-next:125b-a6b-q4_K_M`, served by Ollama 0.40.16 and reached over
    the same tunnel as step 7. Harness: Qwen Code, a CLI agent from Alibaba Group.

    This is a transparency experiment, not a vendor document. Everything below was observed
    on one reference node, so check it on your own machine first. [Known
    gaps](#known-gaps) lists what nobody verified.

!!! info "Placeholders"
    This site is public, so real identifiers stay out of it.
    `<gpu-node>` is the node hostname or address. `<user>` is your account name.
    Replace both with your own values. Nothing below depends on the real ones.

## What you build

The table below is the observed state of the reference node.

| Item | Reference node |
| --- | --- |
| Guest OS | Ubuntu 24.04.5 LTS (kernel 6.8.0-149-generic) |
| vCPU / RAM | 60 cores / 354 GiB |
| GPUs | 2x NVIDIA RTX PRO 6000 Blackwell Server Edition, 97887 MiB each |
| GPU driver / CUDA | 595.112.07 / CUDA 13.2 (compute capability 12.0) |
| Ollama | 0.40.16, native binary at `/usr/local/bin/ollama` (not Docker) |
| Service | `ollama.service`, `User=ollama`, enabled, `Restart=always` |
| Model storage | `/mnt/scratch/ollama/models` (fast local scratch, not the root disk) |
| Listen socket | `127.0.0.1:11434` only, never `0.0.0.0` |
| Client access | SSH local port forward from your laptop |

Three choices define this design:

- **Native install, not a container.** The vendor installer plus a systemd drop-in is the
  whole stack.
- **Models on the scratch partition.** The root filesystem is 100 GB. One model here is
  65-120 GB. The spinning data disk is too slow to load them.
- **Loopback only.** SSH is the authentication layer.

## Why it is built this way

### Biggest GPUs first

A model runs at full speed only when it fits in VRAM. `ollama ps` shows the shortfall: when
`size_vram` is smaller than `size`, part of the model sits in system RAM and generation
slows down. No setting fixes that.

More VRAM also removes work. You serve the model at its native quantisation instead of
hunting for a smaller one that squeezes in. With two GPUs, Ollama splits the model across
both on its own, so you need no load balancing. VRAM is the one constraint you cannot work
around, so pick the biggest card available, such as the 97 GB class.

### Models on the scratch partition

The server reads a model file in full at load time. Disk speed is therefore part of your
latency.

The persistent data disk in this setup sits behind **slow spinning disks**. Reading a 120 GB
file from rotating media takes minutes. That is unacceptable when an agent waits on every
request. Use the **scratch partition**: fast local block storage.

Two consequences follow:

- Scratch is **ephemeral**. The reference node carries a `DATALOSS_WARNING_README.txt` in
  `/mnt/scratch`. Treat everything on it as a cache you can rebuild. Model weights qualify,
  because you can pull them again. Put nothing there that you cannot afford to lose.
- Because the cache can vanish, your pull commands must be written down. Keep the list in
  [step 6](#6-pull-your-models) current. A wipe then costs you a re-download and nothing else.

Check the rotation flag on your own node before you decide. `ROTA` is `1` for rotating media
and `0` for solid state:

```bash
lsblk -d -o NAME,SIZE,ROTA,MOUNTPOINT
```

## Before you start

Step 1 covers the machine itself. On top of the machine you need:

- Your SSH public key registered on the node, so you can log in as `<user>` and use `sudo`.
- A local machine with `ssh` and the `ollama` client.

## The steps

At a glance:

1. Request a machine with a big GPU.
2. Check what the machine actually has.
3. Install Ollama, then fix the ownership of the model directory.
4. Set the environment in a systemd drop-in.
5. Confirm the server stays on loopback.
6. Pull your models.
7. Open the SSH tunnel from your laptop.
8. Point your clients at `localhost:11434`.

### 1. Request a machine with a big GPU

The portal flow is outside the scope of this guide. Ask your SURF Research Cloud
administrator for a GPU machine in your collaboration, and say which machine type you need.
Choose on these criteria:

- The GPU model with the most VRAM that is available to you.
- As many GPUs as you can get. Ollama uses both.
- A separate local scratch disk for the model weights.

Everything below starts from here: the machine exists, and you can SSH into it as `<user>`.

### 2. Confirm what the machine actually has

Every later step uses values you read from the machine. Do not copy them from this page.

```bash
ssh -4 <user>@<gpu-node>

nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
nproc
free -g | head -2
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
df -h / | tail -1
```

The reference node reports two GPUs and three disks: one root disk and two data disks, one
of which is not mounted yet:

```text
NAME     SIZE TYPE MOUNTPOINT
vda      100G disk
├─vda1    99G part /
├─vda14    4M part
├─vda15  106M part /boot/efi
└─vda16  913M part /boot
vdb      5.6T disk /mnt/scratch
vdc      1.5T disk
└─vdc1   1.5T part /data/llm-model-storage
```

Read it this way: `vda` is the operating system disk, and everything else is storage. The
provider mounts the data disks and the scratch partition, so you do not edit `/etc/fstab`
here. If your model directory ends up under `/`, one `ollama pull` fills the root filesystem.

### 3. Install Ollama, then fix the ownership

```bash
curl -fsSL https://ollama.com/install.sh | sh
systemctl status ollama --no-pager | head -8
```

The installer does four things on Ubuntu 24.04. You can observe each part afterwards:

- it puts the binary at `/usr/local/bin/ollama`;
- it creates the `ollama` user and group;
- it writes `/etc/systemd/system/ollama.service` with
  `ExecStart=/usr/local/bin/ollama serve`, `User=ollama`, `Group=ollama`,
  `Restart=always`, `RestartSec=3`, and an `Environment=` line that points
  `OLLAMA_MODELS` at the installer default;
- it registers the unit.

Confirm the binary and the unit are in place. Do not edit the base unit by hand, because the
next installer run overwrites it.

Now make the model directory belong to the service user. The service drops its privileges to
the `ollama` user the installer created (on the reference node: `uid=499999(ollama)`, home
`/usr/share/ollama`, shell `/bin/false`). That user must own the directory that step 4 points
`OLLAMA_MODELS` at:

```bash
sudo mkdir -p /mnt/scratch/ollama/models
sudo chown -R ollama:ollama /mnt/scratch/ollama
```

Get this wrong and the failure is quiet. The server starts and serves nothing, or falls back
to the root disk.

### 4. Set the environment in a drop-in

Override the installer defaults in a drop-in file. This file is the whole server
configuration:

```bash
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null <<'EOF'
[Service]
Environment="OLLAMA_MODELS=/mnt/scratch/ollama/models"
Environment="OLLAMA_KEEP_ALIVE=1h"
Environment="OLLAMA_LOAD_TIMEOUT=15m"
EOF
```

| Setting | Reason |
| --- | --- |
| `OLLAMA_MODELS` | points at the fast scratch disk, not the 100 GB root disk and not the spinning data disk |
| `OLLAMA_KEEP_ALIVE=1h` | a 120 GB model must not be evicted between agent requests; a reload costs minutes |
| `OLLAMA_LOAD_TIMEOUT=15m` | a model this large takes a long time to load; the default timeout stops it |

Activate the change and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
sudo systemctl enable ollama
```

Then confirm the running process agrees with the file. This check catches a missed
`daemon-reload`:

```bash
systemctl show ollama -p Environment
```

Expected output, in this order, with `PATH` extended with the CUDA path:

```text
Environment=OLLAMA_MODELS=/mnt/scratch/ollama/models PATH=...:/usr/local/cuda/bin OLLAMA_KEEP_ALIVE=1h OLLAMA_LOAD_TIMEOUT=15m
```

If the output differs from `override.conf`, the daemon did not reload. Run
`sudo systemctl daemon-reload && sudo systemctl restart ollama`.

### 5. Confirm the server stays on loopback

Do not add `OLLAMA_HOST=0.0.0.0:11434`. The default binding is what you want:

```bash
ss -ltnp | grep 11434
```

```text
LISTEN 0  4096  127.0.0.1:11434  0.0.0.0:*
```

A model server with no authentication, no rate limiting, and no tenant isolation does not
belong on a routable address. Authentication stays with SSH by design.

### 6. Pull your models

```bash
ollama pull qwen3-coder-next:q8_0
ollama list
curl -s localhost:11434/api/version
```

The models on the reference node are 65-120 GB each. A pull of that size takes a while, and
`OLLAMA_LOAD_TIMEOUT` protects the load later. Confirm that the server sees the models:

```bash
curl -s localhost:11434/api/tags | head -c 400
```

Check the upstream tags and quants again before you pull. They change.

### 7. Open the SSH tunnel from your laptop

Add the port forward to your local shell configuration. `ssh -4` forces IPv4, so the forward
cannot quietly bind IPv6 only while your client connects to `127.0.0.1`:

```bash
# Tunnel to the GPU node's Ollama (it runs there as a service).
# Stop the LOCAL Ollama first: it uses the same port.
alias ollama-gpu='ssh -4 -N -L 11434:localhost:11434 <user>@<gpu-node>'
```

Open the tunnel in another terminal:

```bash
sudo systemctl stop ollama   # on your laptop, if it runs one locally
ollama-gpu &
```

Verify it. The listener on `11434` must be `ssh`, and the version must come from the node:

```bash
ss -ltnp | grep 11434       # expect users:(("ssh",pid=...,fd=...))
curl -s localhost:11434/api/version
```

### 8. Point your clients at localhost

With the tunnel up, client tools talk to `localhost:11434`. They do not need to know that the
server is remote. On the reference laptop, `~/.ollama/config.json` registers the model into
each agent integration, and the harness starts from the Ollama CLI:

```bash
ollama launch qwen       # Qwen Code, matches Qwen models' tool-call format
ollama launch opencode   # fallback for non-Qwen models
```

The OpenAI-compatible endpoint (`/v1/chat/completions`) works the same way for other clients.

## Day-2 checks

```bash
sudo journalctl -u ollama -f   # needs sudo on the reference node
ollama ps
curl -s localhost:11434/api/ps
```

`/api/ps` is the honest health check. Compare `size` with `size_vram`. When `size_vram` is
smaller than `size`, the model spills into system RAM and generation is slow. The `runner`
and `context_length` fields show which runtime served the model and at what window.

## Troubleshooting

- **Connection refused on `localhost:11434`.** The tunnel is not running. Start `ollama-gpu`,
  then confirm with `ss -ltnp`.
- **Local `11434` answers, but the models are wrong.** A local Ollama holds the port, so the
  tunnel could not bind. Stop the local Ollama and restart the tunnel.
- **`systemctl show` disagrees with `override.conf`.** The configuration changed after the
  unit loaded. Run `sudo systemctl daemon-reload && sudo systemctl restart ollama`.
- **`ollama list` is empty after a reboot.** Either the scratch disk is unmounted or the model
  directory is not writable by `ollama`. Check the mount with `findmnt /mnt/scratch` and ask
  the provider if it is gone. If the mount is fine, re-run the `chown` from step 3.
- **The root disk fills up.** `OLLAMA_MODELS` still points at `/`. Set it in the drop-in, move
  the files, and restart.
- **A model loads, then stops.** The load timeout is too short. Raise `OLLAMA_LOAD_TIMEOUT`.
- **Generation is slow.** `size_vram` is smaller than `size`, so the model spills into system
  RAM. Use a smaller quant, or a machine with more VRAM.
- **A model load takes minutes.** The weights sit on the spinning data disk. Move the models
  to the scratch partition.
- **`journalctl -u ollama` prints nothing.** Journal access needs elevation on this node. Run
  `sudo journalctl -u ollama`.

## Known gaps

- The SURF Research Cloud portal flow, the machine catalogue, and the entitlement process are
  not documented or verified here. Step 1 states what to ask for, not how to request it.
- The provider manages the mount for the scratch partition and the data disks. How the provider
  creates that mount is neither documented nor verified here.
- The reference configuration was read live from one specific node. Machine-specific values
  change: the `vdb`/`vdc` order, UUIDs, uid and gid, CUDA path, and the Ollama and driver
  versions.
- There is no load balancing, no authentication beyond SSH, and no multi-user isolation. One
  server serves one collaboration, over the tunnel only.
