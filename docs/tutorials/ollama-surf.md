# Run Ollama on SURF Research Cloud

!!! danger "Do not use this in production"

    This page documents an engineering research project. The setup below is an
    internal experiment, not a supported or production-ready service. Never run
    it for a production or shared workload.

    If you need large LLMs for your own research, contact SURF. Do not copy
    this setup as a substitute.

## 1. Create the VM

In [SURF Research Cloud](https://www.surf.nl/en/services/surf-research-cloud),
create a VM from the **Ubuntu 24.04 LTS** image with **CUDA**.

Select the GPU type and the number of GPUs from the size of your model. Do not
take more than you need. GPUs are a shared resource.

|  | RTX PRO 6000 | A10 |
|---|---|---|
| GPU | 1 | 1 |
| VRAM [GB] | 96 | 24 |
| Compute capability | 12.0 | 8.6 |
| CPU | 30 | 11 |
| RAM [GB] | 180 | 88 |

To find how much VRAM your model needs, look up its tag in the
[Ollama library](https://ollama.com/library). The download size of the tag is
approximately the VRAM for the weights. Add some GB for the context, because
the context memory increases with the context size. After you load the model,
`ollama ps` shows the real memory use (see step 4).

For a more detailed estimate, you can use the
[APXML VRAM calculator](https://apxml.com/tools/vram-calculator). It is a
freemium site: some features need a paid account.

One A10 is sufficient for models such as `gpt-oss`, `qwen3.8` and
`gemma4:31b`. The 125B model on this page needs one RTX PRO 6000.

Note the host name and your user name. You need both for the tunnel.

## 2. Install Ollama

Connect over SSH and install Ollama. SURF installs the NVIDIA driver on GPU
VMs, so you do not have to install it.

```bash
curl -fsSL https://ollama.com/install.sh | sudo sh
sudo systemctl enable --now ollama
```

The service listens on `127.0.0.1:11434` only. To use a different port, edit
the service:

```bash
sudo systemctl edit ollama
```

Add these lines, then restart the service:

```ini
[Service]
Environment="OLLAMA_HOST=127.0.0.1:<port>"
```

```bash
sudo systemctl daemon-reload && sudo systemctl restart ollama
```

Keep `127.0.0.1`. Do not use `0.0.0.0`, because that exposes the server to
the network. If you change the port, use the new port in step 5.

## 3. Optional: move the model store to a large volume

The root disk (`/`) of the VM has only approximately 100 GB. Ollama keeps
models on the root disk by default, in `/usr/share/ollama/.ollama/models`.
That is satisfactory for models of a few GB. A model of approximately 100 GB
fills the disk, and the pull fails with `no space left on device`.

For a large model, move the store to a large volume. Find a volume with
`df -h`. On our VM, it is `/mnt/scratch`.

```bash
sudo mkdir -p /mnt/scratch/ollama/models
sudo chown -R ollama:ollama /mnt/scratch/ollama
sudo systemctl edit ollama
```

Add these lines:

```ini
[Service]
Environment="OLLAMA_MODELS=/mnt/scratch/ollama/models"
```

The service reads its environment only when it starts. Restart it after each
change:

```bash
sudo systemctl daemon-reload && sudo systemctl restart ollama
```

Make sure that the setting is applied:

```bash
systemctl show ollama --property=Environment
```

The output must contain `OLLAMA_MODELS`. If you did not set it, the output
shows only `PATH`, and Ollama uses the default path.

## 4. Test a model on the VM

Test on the VM before you add a tunnel. Then you know if a problem is in the
installation or in the tunnel. Keep the long model tag in a variable.

```bash
export MODEL_QWEN38=qwen3.8-flash-next:125b-a6b-q4_K_M
ollama pull $MODEL_QWEN38
ollama run $MODEL_QWEN38 "What is precision?"
```

`/bye` quits. Make sure that the GPU did the work:

```bash
ollama ps
```

`100% GPU` in the PROCESSOR column is correct. If a part runs on the CPU, the
model is slow.

## 5. Use the model from your workstation

Open an SSH tunnel to the VM. Run this on your workstation. Keep the terminal
open, or use `tmux`.

```bash
ssh -N -o ServerAliveInterval=60 -L 11434:localhost:11434 <user>@<vm-host>
```

Install the Ollama client on your workstation. In a second terminal, point it
at the tunnel and export the model tag again:

```bash
export OLLAMA_HOST=http://127.0.0.1:11434
export MODEL_QWEN38=qwen3.8-flash-next:125b-a6b-q4_K_M
curl -s $OLLAMA_HOST/api/tags
ollama run $MODEL_QWEN38 "What is precision?"
```

JSON from `curl` means that the tunnel works. The model runs on the GPU of the
VM, not on your workstation.

For an SDK that uses the OpenAI API, use the base URL `$OLLAMA_HOST/v1`.
Ollama ignores the API key, so any string that is not empty is accepted. The
same setting in Qwen Code:

```json
{
  "model": {
    "baseUrl": "http://127.0.0.1:11434/v1",
    "name": "qwen3.8-flash-next:125b-a6b-q4_K_M"
  }
}
```

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `could not connect to ollama server` | Service down. `sudo systemctl restart ollama`, then read `journalctl -u ollama --no-pager`. |
| `connection refused` on the tunnel | The `ssh -N -L` is not running. Start it again and check the port. |
| `no space left on device` | The model store filled the root disk. Move it as in step 3. |
| Model missing on the workstation | `OLLAMA_HOST` is not set or is wrong in that shell. |

<details markdown>
<summary>AI disclosure</summary>

**AI generated, human guided.** Model `qwen3.8-flash-next:125b-a6b-q4_K_M`
through Qwen Code, 2026-11-19. A human set the scope and reviewed the result.
Commands and output were checked against a running SURF GPU VM the same day.
The session ran 38 minutes over 109 model calls and used 9,831,078 tokens.

A human revised the page after peer review on 2026-11-26.

</details>
