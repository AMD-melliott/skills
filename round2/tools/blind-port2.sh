#!/usr/bin/env bash
# Round-2 blind port. Usage: blind-port2.sh <arm: A|B|Bdi|A5|B4r> <label> <project-git-url> <commit> [request-file]
# - Fresh clone of the project at <commit> into round2/projects/<label>.
# - Installs the arm's skill as ~/.claude/skills/cuda-to-rocm (same name for both arms).
# - Strips GitHub/Docker/HF credentials from the agent's environment and adds deny rules, so an
#   outward-facing attempt is refused and shows up in the transcript.
# - After the run, restores ownership of files that root containers wrote into the project.
set -u
R2=/data/melliott/moat-testing/round2
ROOT=/data/melliott/moat-testing
ARM=$1; LABEL=$2; URL=$3; COMMIT=$4; REQF=${5:-$ROOT/prompts/request-generic.txt}
SKILL_SRC=$R2/arms/arm$ARM/.claude/skills/cuda-to-rocm
[[ -f $SKILL_SRC/SKILL.md ]] || { echo "no arm $ARM skill at $SKILL_SRC"; exit 1; }
P=$R2/projects/$LABEL; T=$R2/transcripts/$LABEL
[[ -e $P || -e $T ]] && { echo "$P or $T exists"; exit 1; }
mkdir -p "$T"

# GPU 7 must have no process using VRAM (gpuagent and tritonserver hold empty handles on every GPU).
busy=$(amd-smi process -g 7 --csv 2>/dev/null | awk -F, 'NR>1 && $6+0>0' | wc -l)
[[ $busy -eq 0 ]] || { echo "GPU 7 busy; not starting"; exit 2; }

git clone -q "$URL" "$P" && git -C "$P" checkout -q --detach "$COMMIT" || exit 3
git -C "$P" remote set-url --push origin DISABLED-no-push

others=$(ls ~/.claude/skills | grep -iE 'cuda|rocm|hip' | grep -vx cuda-to-rocm)
[[ -z $others ]] || { echo "other cuda/rocm skills installed: $others"; exit 4; }
ln -sfn "$SKILL_SRC" ~/.claude/skills/cuda-to-rocm
{ echo "arm=$ARM"; echo "skill=$(readlink -f ~/.claude/skills/cuda-to-rocm)";
  echo "skill_tree=$(git -C $R2/arms/arm$ARM rev-parse HEAD^{tree})"; echo "project=$URL@$COMMIT"; } > "$T/meta"
{ cat "$REQF"; echo; cat $ROOT/prompts/env-notes.md; } > "$T/prompt.txt"

cd "$P" && date -Is > "$T/start"
env -u GH_TOKEN -u GITHUB_TOKEN -u SSH_AUTH_SOCK -u HF_TOKEN -u HUGGING_FACE_HUB_TOKEN \
  GH_CONFIG_DIR=$R2/iso/gh DOCKER_CONFIG=$R2/iso/docker HF_HOME=$R2/iso/hf \
  GIT_CONFIG_GLOBAL=$R2/iso/gitconfig CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 GIT_SSH_COMMAND=/bin/false GIT_TERMINAL_PROMPT=0 \
  timeout 21600 claude -p --settings $R2/blind-settings-r2b.json --max-budget-usd ${MAX_BUDGET:-25} --strict-mcp-config \
  --disallowedTools "Skill(hf-cli)" "Skill(git-status-review)" \
  --allowedTools "Bash,Read,Write,Edit,Glob,Grep,Skill,WebSearch,WebFetch,TodoWrite" \
  --output-format stream-json --verbose < "$T/prompt.txt" > "$T/transcript.jsonl" 2> "$T/stderr.txt"
echo $? > "$T/exit"; date -Is > "$T/end"

# Root-owned files from rocm-run containers: give them back to the invoking user.
docker run --rm -v "$P":"$P" rocm/dev-ubuntu-24.04:7.2.1-complete chown -R "$(id -u):$(id -g)" "$P" >/dev/null 2>&1
rm -f ~/.claude/skills/cuda-to-rocm
