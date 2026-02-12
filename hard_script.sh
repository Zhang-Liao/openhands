#!/bin/bash


# NOTE: use socks5:// (httpx does not accept socks://)
export ALL_PROXY="socks5://127.0.0.1:7897/"
export all_proxy="socks5://127.0.0.1:7897/"

# 默认值
INSTANCES_FILE="instance_for_fuzz1.txt"
LLM_CONFIG=".llm_config/openrouter.json"
BUILD_ONLY=0

# 默认 instances 文件优先级：
# 1) instance_set/instances_hard.txt (新路径)
# 2) instances_hard.txt (旧路径)
# 3) instances_hard_1case.txt (单例调试)
if [[ -f "instance_set/instances_hard.txt" ]]; then
    INSTANCES_FILE="instance_set/instances_hard.txt"
elif [[ -f "instances_hard.txt" ]]; then
    INSTANCES_FILE="instances_hard.txt"
elif [[ -f "instances_hard_1case.txt" ]]; then
    INSTANCES_FILE="instances_hard_1case.txt"
else
    INSTANCES_FILE="instance_set/instances_hard.txt"
fi

# 默认 LLM 配置优先级：有 opus 则优先，否则 fallback
if [[ -f ".llm_config/openrouter_opus.json" ]]; then
    LLM_CONFIG=".llm_config/openrouter_opus.json"
else
    LLM_CONFIG=".llm_config/openrouter.json"
fi

# 推理通用参数（与下方各模式共用）
MAX_ATTEMPTS=3
MAX_ITERATIONS=200
MAX_RETRIES=1
NUM_WORKERS=5
N_LIMIT=100

# 输出目录根路径
OUTPUT_BASE="./evaluation_results"

# 运行开关（保持双方功能；默认只跑 baseline + hypothesis，其他需要手动打开）
RUN_BASELINE="${RUN_BASELINE:-1}"
RUN_HYPOTHESIS="${RUN_HYPOTHESIS:-1}"
RUN_INSTALL_PROMPT="${RUN_INSTALL_PROMPT:-0}"
RUN_FUZZ_HYPO_FINAL_AUG="${RUN_FUZZ_HYPO_FINAL_AUG:-0}"
RUN_SUBAGENT_FUZZ="${RUN_SUBAGENT_FUZZ:-0}"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--instances)
            INSTANCES_FILE="$2"
            shift 2
            ;;
        -l|--llm-config)
            LLM_CONFIG="$2"
            shift 2
            ;;
        -d|--dataset)
            DATASET_NAME="$2"
            shift 2
            ;;
        -b|--build-only)
            BUILD_ONLY=1
            shift
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  -i, --instances <文件>    指定测试集文件 (默认: instance_set/instances_hard.txt；若不存在则回退 instances_hard.txt)"
            echo "  -l, --llm-config <文件>   指定LLM配置文件 (默认: 若存在 .llm_config/openrouter_opus.json 则优先，否则 .llm_config/openrouter.json)"
            echo "  -d, --dataset <名称>      指定数据集名称 (默认: princeton-nlp/SWE-bench_Verified)"
            echo "  -b, --build-only          仅构建 Docker 镜像，不跑推理与评测 (省 token)"
            echo "  -h, --help                显示帮助信息"
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            echo "使用 -h 或 --help 查看帮助信息"
            exit 1
            ;;
    esac
done

# 非仅构建模式时才校验 LLM 配置
if [[ $BUILD_ONLY -eq 0 ]]; then
    if ! command -v jq &> /dev/null; then
        echo "错误: 需要安装 jq 来解析 JSON 配置文件"
        exit 1
    fi

    if [[ ! -f "$LLM_CONFIG" ]]; then
        echo "错误: 找不到 LLM 配置文件: $LLM_CONFIG"
        exit 1
    fi

    MODEL=$(jq -r '.model' "$LLM_CONFIG")
    if [[ -z "$MODEL" || "$MODEL" == "null" ]]; then
        echo "错误: 无法从配置文件中读取 model 字段"
        exit 1
    fi
else
    MODEL=""
fi

# 动态获取 SDK submodule 的 short SHA（与 Python 代码中的 SDK_SHORT_SHA 保持一致）
SDK_SHA=$(git submodule status vendor/software-agent-sdk | awk '{print $1}' | sed 's/^[+-]*//')
SDK_SHORT_SHA="${SDK_SHA:0:7}"

# 构建评估输出路径的基础部分
# 格式: {output_dir}/{dataset_sanitized}-{split}/{model}_sdk_{sha}_maxiter_200_N_initial/output.jsonl
DATASET_SANITIZED=${DATASET_NAME//\//__}
DATASET_PATH="${DATASET_SANITIZED}-${SPLIT}"
MODEL_PATH_SUFFIX="${MODEL}_sdk_${SDK_SHORT_SHA}_maxiter_200_N_initial"

# 从 INSTANCES_FILE 提取文件名（不含扩展名）作为子目录名
INSTANCES_SUBDIR=$(basename "$INSTANCES_FILE" .txt)

echo "使用测试集: $INSTANCES_FILE"
echo "使用数据集: $DATASET_NAME"
if [[ $BUILD_ONLY -eq 0 ]]; then
    echo "使用LLM配置: $LLM_CONFIG"
    echo "模型: $MODEL"
fi
echo "输出子目录: $INSTANCES_SUBDIR"
[[ $BUILD_ONLY -eq 1 ]] && echo "仅构建镜像 (--build-only)，不运行推理与评测"

uv run benchmarks/swebench/build_images.py \
  --dataset "$DATASET_NAME" \
  --split "$SPLIT" \
  --image ghcr.io/openhands/eval-agent-server \
  --target source-minimal \
  --num-workers "$NUM_WORKERS" \
  --select "$INSTANCES_FILE" \
  --n-limit "$N_LIMIT"

[[ $BUILD_ONLY -eq 1 ]] && echo "Docker 镜像构建完成，已退出。" && exit 0

# Run with fuzz_hypo tool enabled
# uv run swebench-infer "$LLM_CONFIG" \
#     --select "$INSTANCES_FILE" \
#     --workspace docker \
#     --output-dir "./evaluation_results/eval_outputs_fuzz_hypo_100/${INSTANCES_SUBDIR}" \
#     --max-attempts 3 \
#     --max-iterations 200 \
#     --max-retries 1 \
#     --num-workers 5 \
#     --extra-tools fuzz_hypo \
#     --prompt-path benchmarks/swebench/prompts/custom_fuzz_prompt.j2 \
#     --n-limit 100

# uv run swebench-eval "./evaluation_results/eval_outputs_fuzz_hypo_100/${INSTANCES_SUBDIR}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/output.jsonl" \
#   --dataset "$DATASET_NAME" \
#   --output-file "./evaluation_results/eval_outputs_fuzz_hypo_100/${INSTANCES_SUBDIR}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/results.swebench.jsonl" \
#   --workers 5
 # Important: Must be explicitly empty

# After saving, restart your terminal for changes to take effect


run_eval() {
    local out_dir="$1"
    uv run swebench-eval "${out_dir}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/output.jsonl" \
      --dataset "$DATASET_NAME" \
      --output-file "${out_dir}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/results.swebench.jsonl" \
      --workers "$NUM_WORKERS"
}

# 输出目录（统一由 OUTPUT_BASE 控制；想用旧风格则 OUTPUT_BASE="."）
BASELINE_OUT="${OUTPUT_BASE}/eval_outputs/${INSTANCES_SUBDIR}"
HYPOTHESIS_OUT="${OUTPUT_BASE}/eval_outputs_hypothesis_100/${INSTANCES_SUBDIR}"
INSTALL_OUT="${OUTPUT_BASE}/eval_outputs_aug/${INSTANCES_SUBDIR}"
FUZZ_FINAL_AUG_OUT="${OUTPUT_BASE}/eval_outputs_fuzz_hypo_final_aug/${INSTANCES_SUBDIR}"
SUBFUZZ_OUT="${OUTPUT_BASE}/eval_outputs_subfuzz/${INSTANCES_SUBDIR}"

# Run with fuzz_hypo tool enabled, and install before fixing prompt (final aug)
if [[ "$RUN_FUZZ_HYPO_FINAL_AUG" == "1" ]]; then
    uv run swebench-infer "$LLM_CONFIG" \
        --select "$INSTANCES_FILE" \
        --workspace docker \
        --output-dir "$FUZZ_FINAL_AUG_OUT" \
        --max-attempts "$MAX_ATTEMPTS" \
        --max-iterations "$MAX_ITERATIONS" \
        --max-retries "$MAX_RETRIES" \
        --num-workers "$NUM_WORKERS" \
        --extra-tools fuzz_hypo \
        --prompt-path benchmarks/swebench/prompts/fuzz_final_only_aug.j2 \
        --n-limit "$N_LIMIT"
    run_eval "$FUZZ_FINAL_AUG_OUT"
fi

# Baseline (default prompt, no extra tools)
if [[ "$RUN_BASELINE" == "1" ]]; then
    uv run swebench-infer "$LLM_CONFIG" \
        --select "$INSTANCES_FILE" \
        --workspace docker \
        --output-dir "$BASELINE_OUT" \
        --max-attempts "$MAX_ATTEMPTS" \
        --max-iterations "$MAX_ITERATIONS" \
        --max-retries "$MAX_RETRIES" \
        --num-workers "$NUM_WORKERS" \
        --n-limit "$N_LIMIT"
    run_eval "$BASELINE_OUT"
fi

# Run with hypothesis prompt (no extra tools)
if [[ "$RUN_HYPOTHESIS" == "1" ]]; then
    uv run swebench-infer "$LLM_CONFIG" \
        --select "$INSTANCES_FILE" \
        --workspace docker \
        --output-dir "$HYPOTHESIS_OUT" \
        --max-attempts "$MAX_ATTEMPTS" \
        --max-iterations "$MAX_ITERATIONS" \
        --max-retries "$MAX_RETRIES" \
        --num-workers "$NUM_WORKERS" \
        --prompt-path benchmarks/swebench/prompts/hypothesis_default.j2 \
        --n-limit "$N_LIMIT"
    run_eval "$HYPOTHESIS_OUT"
fi

# Run with install before fixing prompt
if [[ "$RUN_INSTALL_PROMPT" == "1" ]]; then
    uv run swebench-infer "$LLM_CONFIG" \
        --select "$INSTANCES_FILE" \
        --workspace docker \
        --output-dir "$INSTALL_OUT" \
        --max-attempts "$MAX_ATTEMPTS" \
        --max-iterations "$MAX_ITERATIONS" \
        --max-retries "$MAX_RETRIES" \
        --num-workers "$NUM_WORKERS" \
        --prompt-path benchmarks/swebench/prompts/default_install.j2 \
        --n-limit "$N_LIMIT"
    run_eval "$INSTALL_OUT"
fi

# run with prompting a subagent to fuzz the target function
if [[ "$RUN_SUBAGENT_FUZZ" == "1" ]]; then
    uv run swebench-infer "$LLM_CONFIG" \
        --dataset "$DATASET_NAME" \
        --select "$INSTANCES_FILE" \
        --workspace docker \
        --output-dir "$SUBFUZZ_OUT" \
        --max-attempts "$MAX_ATTEMPTS" \
        --max-iterations "$MAX_ITERATIONS" \
        --max-retries "$MAX_RETRIES" \
        --num-workers "$NUM_WORKERS" \
        --prompt-path benchmarks/swebench/prompts/subagent_hypo.j2 \
        --n-limit "$N_LIMIT"
    run_eval "$SUBFUZZ_OUT"

    # --- 自动运行盲测验证（可选） ---
    # OUTPUT_JSONL="${SUBFUZZ_OUT}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/output.jsonl"
    # if [[ -f "$OUTPUT_JSONL" ]]; then
    #     ./batch_verify.sh "$OUTPUT_JSONL" \
    #         --num-workers "$NUM_WORKERS" \
    #         --extra-tools fuzz_hypo \
    #         --select "$INSTANCES_FILE" \
    #         --n-limit 10
    # else
    #     echo "跳过验证：找不到输出文件 $OUTPUT_JSONL"
    # fi
fi
