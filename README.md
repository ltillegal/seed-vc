# Seed-VC

Zero-shot voice conversion, singing voice conversion and real-time voice conversion
with in-context learning. A reference clip of 1–30 seconds is enough — no training required.

This repository is a fork of [Plachtaa/seed-vc](https://github.com/Plachtaa/seed-vc)
(paper: [arXiv:2411.09943](https://arxiv.org/abs/2411.09943),
demo: [Hugging Face](https://huggingface.co/spaces/Plachta/Seed-VC),
[project page](https://plachtaa.github.io/seed-vc/)).

## What is different in this fork

- **English-only UI** — Chinese strings were removed from `app.py`, `app_vc.py`,
  `app_svc.py` and `app_vc_v2.py`.
- **One-command launch on macOS** — `start-mac.command` creates the virtual
  environment, installs the right PyTorch for your Mac and opens the web UI.
- **Model installer** — `install-model.py` puts a downloaded model into
  `my_models/<name>/` and prints the exact command to run it.
- The Chinese and Japanese README translations were dropped in favour of this
  single English document.

## Quick start (macOS)

Requirements: macOS 12+, Python 3.10 or 3.11, [Homebrew](https://brew.sh) (recommended).

```bash
git clone https://github.com/ltillegal/seed-vc.git
cd seed-vc
./start-mac.command
```

The first run creates `.venv` and installs the dependencies (a few minutes);
later runs start instantly. The browser opens at <http://127.0.0.1:7860>.

If double-clicking in Finder does nothing, make the file executable once:

```bash
chmod +x start-mac.command
```

and open it with right click → **Open** (Gatekeeper asks only on the first run).

### Launcher modes

```bash
./start-mac.command            # voice conversion UI (default)
./start-mac.command svc        # singing voice conversion UI
./start-mac.command v2         # V2 voice / accent conversion UI
./start-mac.command all        # integrated UI (V1 + V2)
./start-mac.command install <model.zip|dir>
./start-mac.command vc my_models/my-model
./start-mac.command check      # show Python, PyTorch, device, ffmpeg
```

Environment variables: `PORT` (default `7860`), `FP16=1`, `SHARE=1`,
`NO_OPEN=1`, `DRY_RUN=1`.

Apple Silicon uses the MPS backend; Intel Macs fall back to CPU, which works but
is slow. Models are downloaded from Hugging Face on first inference and cached in
`./checkpoints`.

### Manual macOS install

```bash
python3.11 -m venv .venv
source .venv/bin/activate
pip install torch==2.4.1 torchvision==0.19.1 torchaudio==2.4.1     # Apple Silicon
pip install torch==2.2.2 torchvision==0.17.2 torchaudio==2.2.2    # Intel Mac
pip install -r requirements-mac.txt
python app_vc.py --fp16 True
```

On Apple Silicon (MPS), `--fp16 True` is safe: `autocast` is automatically disabled for the MPS backend (see the `fix(mps)` commit), so the model runs in float32 while tensors stay on the GPU. On Intel Macs keep `--fp16 False`.

## Windows and Linux

```bash
python -m venv .venv
source .venv/bin/activate      # Windows: .venv\Scripts\activate
# Install PyTorch first (CUDA or CPU build for your system):
pip install torch torchvision torchaudio
# Then the rest. requirements.txt contains a `--pre` flag that some pip/uv
# versions reject; if that happens, remove the torch line from
# requirements.txt (torch is already installed above) and re-run.
pip install -r requirements.txt
python app_vc.py
```

A CUDA GPU is strongly recommended. On Windows you may install
`triton-windows==3.2.0.post13` to use `--compile` with the V2 model.

## Models

Models are downloaded automatically unless `--checkpoint` and `--config` are given.

| Version | Name | Purpose | Sampling rate | Notes |
|---|---|---|---|---|
| v1.0 | [seed-uvit-tat-xlsr-tiny](https://huggingface.co/Plachta/Seed-VC/blob/main/DiT_uvit_tat_xlsr_ema.pth) | Voice conversion | 22.05 kHz | 25M params, made for real-time use |
| v1.0 | [seed-uvit-whisper-small-wavenet](https://huggingface.co/Plachta/Seed-VC/blob/main/DiT_seed_v2_uvit_whisper_small_wavenet_bigvgan_pruned.pth) | Voice conversion | 22.05 kHz | 98M params, default for offline VC |
| v1.0 | [seed-uvit-whisper-base](https://huggingface.co/Plachta/Seed-VC/blob/main/DiT_seed_v2_uvit_whisper_base_f0_44k_bigvgan_pruned_ft_ema.pth) | Singing voice conversion | 44.1 kHz | 200M params, best zero-shot SVC |
| v2.0 | [hubert-bsqvae-small](https://huggingface.co/Plachta/Seed-VC/tree/main/v2) | Voice / accent conversion | 22.05 kHz | suppresses source speaker traits |

Configuration files live in `configs/presets/` (V1) and `configs/v2/` (V2).

### Pitch shift

The singing voice conversion UI (`app_svc.py`) exposes a **Pitch shift** slider
(−24 to +24 semitones). It only has an effect when the F0-conditioned model
is in use, which is the default for singing models. Set it to `0` for speech-like
output; use positive values to raise the voice and negative values to lower it.

## Usage

### Web UIs

```bash
python app_vc.py --fp16 False           # voice conversion
python app_svc.py --fp16 False          # singing voice conversion
python app_vc_v2.py                     # V2 voice / accent conversion
python app.py --enable-v1 --enable-v2   # both V1 and V2 in one UI
```

Then open <http://127.0.0.1:7860>. Use `--share True` to get a public Gradio link.

### Custom models

```bash
python install-model.py path/to/model.zip
# or
./start-mac.command install path/to/model.zip
```

The archive (or directory) must contain a `.pth` checkpoint and a `config*.yml`.
Files are copied to `my_models/<archive name>/`; the script prints the command to
run the model. Run it later with:

```bash
python app_vc.py --checkpoint my_models/<name>/*.pth --config my_models/<name>/config*.yml
# macOS shortcut:
./start-mac.command vc my_models/<name>
```

### Command line inference

```bash
python inference.py \
  --source examples/source/yae_0.wav \
  --target examples/reference/dingzhen_0.wav \
  --output out/ \
  --diffusion-steps 25 \
  --length-adjust 1.0 \
  --inference-cfg-rate 0.7 \
  --f0-condition False \
  --auto-f0-adjust False \
  --semi-tone-shift 0 \
  --fp16 False
```

Use `--f0-condition True` for singing voice conversion, `--diffusion-steps 30–50`
for the best quality and `4–10` for the fastest inference. `--checkpoint` and
`--config` select a custom model.

For the V2 model use `inference_v2.py` (see `python inference_v2.py --help`).

### Real-time voice conversion

```bash
python real-time-gui.py
```

Requires a GPU in practice (algorithm delay ~300 ms plus device delay ~100 ms).
On macOS this needs a Python build with Tkinter and PortAudio:
`brew install python-tk@3.11 portaudio`.

## Training

Fine-tuning on your own data needs very little material: from one utterance per
speaker, ~100 steps.

```bash
python train.py \
  --config configs/presets/config_dit_mel_seed_uvit_whisper_small_wavenet.yml \
  --dataset-dir path/to/audio \
  --run-name my-run \
  --batch-size 2 \
  --max-steps 1000 \
  --save-every 500 \
  --num-workers 0
```

Checkpoints and logs go to `runs/<run-name>/`; pass `ft_model.pth` and the config
to `--checkpoint` / `--config` to use them. See the
[upstream README](https://github.com/Plachtaa/seed-vc#training) for the full
training and dataset guide, and `EVAL.md` for objective comparisons.

## Troubleshooting

- **`no suitable Python found`** — install Python 3.10 or 3.11 (`brew install python@3.11`).
  The pinned dependencies (`numpy==1.26.4`, `funasr`, `modelscope`) are not tested on newer versions.
- **`ffmpeg not found`** — `brew install ffmpeg` (needed for mp3 and some inputs).
- **`No module named '_tkinter'`** — install a Python build with Tkinter:
  `brew install python-tk@3.11`.
- **MPS errors on Apple Silicon** — the launcher sets
  `PYTORCH_ENABLE_MPS_FALLBACK=1`; for stubborn cases run with `FP16=0` (the default).
- **Intel Mac is very slow** — that is expected, there is no GPU acceleration;
  use fewer diffusion steps.
- **Port already in use** — `PORT=7861 ./start-mac.command`.
- **`Another instance...` / stale `.venv`** — delete `.venv` and relaunch; it will
  be rebuilt.

## License and credits

The project is distributed under the licence in [LICENSE](LICENSE), the original
work belongs to the Seed-VC authors (Plachtaa and contributors). Thanks to
Amphion/Vevo, MegaTTS3, ASTRAL-quantization, RVC and SEED-TTS for the ideas and
components this project builds on.
