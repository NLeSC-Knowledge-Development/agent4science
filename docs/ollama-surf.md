# Run Ollama on the SURF Research Environment

!!! danger "Do not use this in production"

    This page documents an engineering research project. The setup below is an
    internal experiment, not a supported or production-ready service. Never run
    it for a production or shared workload.

    If you need large LLMs for your own research, contact SURF. Do not copy
    this setup as a substitute.

> **AI generated, human guided.** Model `qwen3.8-flash-next:125b-a6b-q4_K_M`
> through Qwen Code, 2026-11-19. A human set the scope and reviewed the result.
> Commands and output were checked against a running SURF GPU VM the same day.
> The session ran 38 minutes over 109 model calls and used 9,831,078 tokens.

## 1. Create the VM

In the SURF Research Environment, create a VM from the **Ubuntu 24.04 LTS**
image with **CUDA**. Select the **maximum number of GPUs** available.

Note the host name and your user name. You need both for the tunnel.

## 2. Install Ollama

Ollama needs a working NVIDIA driver and does not install one. Connect over
SSH and check the driver first. A `GPU 0` row with a driver version means it
works.

```bash
nvidia-smi
curl -fsSL https://ollama.com/install.sh | sudo sh
sudo systemctl enable --now ollama
```

The service listens on `127.0.0.1:11434` only.

## 3. Check the configuration on the VM

Read the live settings. Never assume where models are stored.

```bash
ollama --version
systemctl show ollama --property=Environment
ollama list
```

`OLLAMA_MODELS` is the store path. If it points at the root disk, move it to
your large volume. The service reads its environment once at start, so restart
it after any change:

```bash
sudo systemctl edit ollama   # add: Environment="OLLAMA_MODELS=<large-volume-path>"
sudo systemctl daemon-reload && sudo systemctl restart ollama
```

## 4. Test a model on the VM

Test on the VM before you add a tunnel. That separates a broken install from a
broken tunnel. Keep the long tag in a variable, and export it again on your
workstation.

```bash
export MODEL=qwen3.8-flash-next:125b-a6b-q4_K_M
ollama pull $MODEL
ollama run $MODEL "What is precision?"
```

`/bye` quits. Confirm the GPU did the work:

```bash
ollama ps
```

`100% GPU` in the PROCESSOR column is what you want. A share on CPU is slow.

## 5. Tunnel port 11434 to your workstation

Run this on your workstation. Keep the terminal open, or use `tmux`.

```bash
ssh -N -o ServerAliveInterval=60 -L 11434:localhost:11434 <user>@<vm-host>
```

## 6. Use it like a local model

Install the Ollama client on your workstation. It talks to the VM instead of a
local server.

```bash
export OLLAMA_HOST=http://127.0.0.1:11434
export MODEL=qwen3.8-flash-next:125b-a6b-q4_K_M
curl -s $OLLAMA_HOST/api/tags
ollama run $MODEL "What is precision?"
```

JSON from `curl` means the tunnel works. Inference still runs on the VM's GPU.

For an SDK that speaks OpenAI, use the base URL `$OLLAMA_HOST/v1`. Ollama
ignores the API key, so any non-empty string passes. The same setting in Qwen
Code:

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
| `no space left on device` | The store filled its disk. Set `OLLAMA_MODELS` as in step 3. |
| Model missing on the workstation | `OLLAMA_HOST` unset or wrong in that shell. |
