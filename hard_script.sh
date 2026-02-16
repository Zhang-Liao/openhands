#!/bin/bash

# NOTE: use socks5:// (httpx does not accept socks://)
export ALL_PROXY="socks5://127.0.0.1:7897/"
export all_proxy="socks5://127.0.0.1:7897/"

# 默认值
INSTANCES_FILE="instance_set/instances_for_fuzz1.txt"
LLM_CONFIG=".llm_config/openrouter.json"
DATASET_NAME="princeton-nlp/SWE-bench_Verified"
SPLIT="test"
BUILD_ONLY=0

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
            echo "  -i, --instances <文件>    指定测试集文件 (默认: instance_set/instances_hard.txt)"
            echo "  -l, --llm-config <文件>   指定LLM配置文件 (默认: .llm_config/openrouter_opus.json)"
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

# 非仅构建模式时才校验 LLM 配置并读取模型
if [[ $BUILD_ONLY -eq 0 ]]; then
    # 从 LLM 配置文件中提取 model 字段
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
  --num-workers 5 \
  --select "$INSTANCES_FILE" \
  --n-limit 100

[[ $BUILD_ONLY -eq 1 ]] && echo "Docker 镜像构建完成，已退出。" && exit 0
# # Run with fuzz_hypo tool enabled
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


# Run with fuzz_hypo tool enabled, and install before fixing prompt
# uv run swebench-infer "$LLM_CONFIG" \
#     --select "$INSTANCES_FILE" \
#     --workspace docker \
#     --output-dir "./evaluation_results/eval_outputs_fuzz_hypo_final_aug/${INSTANCES_SUBDIR}" \
#     --max-attempts 3 \
#     --max-iterations 200 \
#     --max-retries 1 \
#     --num-workers 5 \
#     --extra-tools fuzz_hypo \
#     --prompt-path benchmarks/swebench/prompts/fuzz_final_only_aug.j2 \
#     --n-limit 100

# uv run swebench-eval "./evaluation_results/eval_outputs_fuzz_hypo_final_aug/${INSTANCES_SUBDIR}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/output.jsonl" \
#   --dataset "$DATASET_NAME" \
#   --output-file "./evaluation_results/eval_outputs_fuzz_hypo_final_aug/${INSTANCES_SUBDIR}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/results.swebench.jsonl" \
#   --workers 5

# Baseline
uv run swebench-infer "$LLM_CONFIG" \
    --select "$INSTANCES_FILE" \
    --workspace docker \
    --output-dir "./evaluation_results/eval_outputs/${INSTANCES_SUBDIR}" \
    --max-attempts 3 \
    --max-iterations 200 \
    --max-retries 1 \
    --num-workers 5 \
    --prompt-path benchmarks/swebench/prompts/default.j2 \
    --n-limit 100

uv run swebench-eval "./evaluation_results/eval_outputs/${INSTANCES_SUBDIR}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/output.jsonl" \
  --dataset "$DATASET_NAME" \
  --output-file "./evaluation_results/eval_outputs/${INSTANCES_SUBDIR}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/results.swebench.jsonl" \
  --workers 5


# # Run with install before fixing prompt
uv run swebench-infer "$LLM_CONFIG" \
    --select "$INSTANCES_FILE" \
    --workspace docker \
    --output-dir "./evaluation_results/eval_outputs_aug/${INSTANCES_SUBDIR}" \
    --max-attempts 3 \
    --max-iterations 200 \
    --max-retries 1 \
    --num-workers 5 \
    --prompt-path benchmarks/swebench/prompts/default_install.j2 \
    --n-limit 100

uv run swebench-eval "./evaluation_results/eval_outputs_aug/${INSTANCES_SUBDIR}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/output.jsonl" \
  --dataset "$DATASET_NAME" \
  --output-file "./evaluation_results/eval_outputs_aug/${INSTANCES_SUBDIR}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/results.swebench.jsonl" \
  --workers 5

# run with augmented prompt
# uv run swebench-infer "$LLM_CONFIG" \
#     --select "$INSTANCES_FILE" \
#     --workspace docker \
#     --output-dir "./evaluation_results/eval_outputs_0209/${INSTANCES_SUBDIR}" \
#     --max-attempts 3 \
#     --max-iterations 200 \
#     --max-retries 1 \
#     --num-workers 5 \
#     --prompt-path benchmarks/swebench/prompts/default_aug_2.j2 \
#     --n-limit 100

# uv run swebench-eval "./evaluation_results/eval_outputs_0209/${INSTANCES_SUBDIR}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/output.jsonl" \
#   --dataset "$DATASET_NAME" \
#   --output-file "./evaluation_results/eval_outputs_0209/${INSTANCES_SUBDIR}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/results.swebench.jsonl" \
#   --workers 5

# run with prompting a subagent to fuzz the target function
# uv run swebench-infer "$LLM_CONFIG" \
#     --dataset "$DATASET_NAME" \
#     --select "$INSTANCES_FILE" \
#     --workspace docker \
#     --output-dir "./evaluation_results/eval_outputs_subfuzz/${INSTANCES_SUBDIR}" \
#     --max-attempts 3 \
#     --max-iterations 200 \
#     --max-retries 1 \
#     --num-workers 5 \
#     --prompt-path benchmarks/swebench/prompts/subagent_hypo.j2 \
#     --n-limit 100
# # # 格式: ./batch_verify.sh <output.jsonl 路径>
# uv run swebench-eval "./evaluation_results/eval_outputs_subfuzz/${INSTANCES_SUBDIR}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/output.jsonl" \
#   --dataset "$DATASET_NAME" \
#   --output-file "./evaluation_results/eval_outputs_subfuzz/${INSTANCES_SUBDIR}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/results.swebench.jsonl" \
#   --workers 5

# --- 新增：自动运行盲测验证 ---
# echo ">>> 开始自动盲测验证生成的补丁..."
# OUTPUT_JSONL="./evaluation_results/eval_outputs_subfuzz/${INSTANCES_SUBDIR}/${DATASET_PATH}/${MODEL_PATH_SUFFIX}/output.jsonl"

# if [[ -f "$OUTPUT_JSONL" ]]; then
#     ./batch_verify.sh "$OUTPUT_JSONL" \
#         --num-workers 5 \
#         --extra-tools fuzz_hypo \
#         --select "$INSTANCES_FILE" \
#         --n-limit 10
# else
#     echo "跳过验证：找不到输出文件 $OUTPUT_JSONL"
# fi