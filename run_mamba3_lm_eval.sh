#!/bin/bash
#SBATCH --account=MST115278
#SBATCH --job-name=mamba3_lm_eval
#SBATCH --partition=dev
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=12
#SBATCH --gres=gpu:1
#SBATCH --output=/home/m314510193/GithubMamba3Train/mamba3_evals/mamba3_lm_eval_%j.log

# set is a bash built-in command that toggles shell options
# -e: aborts the script immediately if any command exits with a non-zero status
# -u: treat any reference to an unset variable as an error and abort
# -o pipefail: In a pipe command (e.g. "cmd1 | cmd2"), the command fails if either cmd1 or cmd2 fails
set -euo pipefail

# ---------------------------------------------------------------------------
# Overridable knobs. Defaults reproduce Table3 in the Mamba3 thesis.
# Override Examples:
#   sbatch --export=ALL,TASKS=lambada_openai,ADD_BOS=true ./run_mamba3_lm_eval.sh
#   sbatch --export=ALL,MODEL=state-spaces/mamba3-siso-187m ./run_mamba3_lm_eval.sh
# ---------------------------------------------------------------------------
MODEL="${MODEL:-state-spaces/mamba3-mimo-187m}"
TOKENIZER="${TOKENIZER:-meta-llama/Llama-3.1-8B}"
DTYPE="${DTYPE:-bfloat16}"
# see ../RTX6000_mamba3/evals/lm_harness_eval.py to know why ADD_BOS parameter is added
ADD_BOS="${ADD_BOS:-false}"
BATCH_SIZE="${BATCH_SIZE:-64}"
TASKS="${TASKS:-lambada_openai,hellaswag,piqa,arc_easy,arc_challenge,winogrande,openbookqa}"
TAG="${TAG:-$(basename "$MODEL")_bos${ADD_BOS}}"
OUTDIR="${OUTDIR:-/home/m314510193/GithubMamba3Train/mamba3_evals/results_${TAG}}"

# Refer to: "NANO4 Mamba-3 環境架設與使用.pdf"
module load miniconda3/26.1.1
module load cuda/13.0
conda activate mamba3
export PATH="$CONDA_PREFIX/bin:$PATH"

# let Python to import mixer_seq_simple.py in 
# `RTX6000_mamba3/mamba_ssm/models/mixer_seq_simple.py`
# rather than in
# .../site-packages/mamba_ssm/models/mixer_seq_simple.py
export MAMBA_REPO=/home/m314510193/GithubMamba3Train/RTX6000_mamba3
export PYTHONPATH="$MAMBA_REPO${PYTHONPATH:+:$PYTHONPATH}"

# check if `export PYTHONPATH="$MAMBA_REPO${PYTHONPATH:+:$PYTHONPATH}"` is effective
# `python -` means read the script from stdin rather than from a file.
# "$MAMBA_REPO" after it is passed as sys.argv[1] to that script.
#  everything in `<<'EOF' ... EOF` becomes that script's stdin text.
python - "$MAMBA_REPO" <<'EOF'
import sys, mamba_ssm
expected = sys.argv[1] + "/mamba_ssm/__init__.py"
print("mamba_ssm ->", mamba_ssm.__file__, flush=True)
if mamba_ssm.__file__ != expected:
    sys.exit(f"ERROR: PYTHONPATH shim did not take effect (expected {expected})")
EOF

# Confirm if a GPU is allocated
# `torch.zeros(1, device='cuda')` will throw an error if a GPU is not allocated
python -c "import torch; print('torch sees', torch.cuda.device_count(), 'GPU(s)'); \
torch.zeros(1, device='cuda'); print('CUDA alloc OK')"

# Read the weights/tokenizer staged earlier on the login node
# assign the environment variable (i.e. HF_HOME) for cached_file() called in 
# ../RTX6000_mamba3/mamba_ssm/utils/hf.py to fetch config.json
export HF_HOME=/home/m314510193/GithubMamba3Train/hf_cache
# `HF_HUB_OFFLINE=1` enables the offline mode to avoid any model, 
# tokenizer, or dataset, is automatically fetched
export HF_HUB_OFFLINE=1

# Run the lm_harness_eval.py directly (not the bare `lm_eval` CLI shown as the evaluation 
# example in the official mamba repository) so the class MambaEvalWrapper can be detected when 
# cli_evaluate() looks it up.
python "$MAMBA_REPO/evals/lm_harness_eval.py" --model mamba \
  --model_args "pretrained=${MODEL},tokenizer=${TOKENIZER},dtype=${DTYPE},add_bos_token=${ADD_BOS}" \
  --tasks "$TASKS" \
  --device cuda --batch_size "$BATCH_SIZE" \
  --output_path "$OUTDIR"