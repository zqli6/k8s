#!/bin/bash
# ============================================================
# push-to-registry.sh
# 执行节点：一台能同时访问【公网或离线介质】和【华为云 SWR】的机器
# 功能：把 K8s 部署所需的全部镜像推送到华为云 SWR（amd64 单平台）
# 前置：先在 config/cluster.env 配置 SWR_AK / SWR_LOGIN_KEY
# 用法：
#   ./push-to-registry.sh --pull       # 先联网拉取（阿里云/DaoCloud）再推送
#   ./push-to-registry.sh              # 用本地已有镜像推送（已 import 过 tar）
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

MODE="local"
[ "$1" == "--pull" ] && MODE="pull"

echo "=========================================="
echo " 推送镜像到华为云 SWR"
echo "=========================================="

if [ -z "${PRIVATE_REGISTRY}" ]; then
    echo "[✗] 未配置 PRIVATE_REGISTRY，请先编辑 config/cluster.env"
    exit 1
fi
echo "目标仓库: ${PRIVATE_REGISTRY}"
echo "运行模式: ${MODE}（pull=先联网拉取, local=用本地镜像）"
echo ""

# --- 登录华为云 SWR ---
REGISTRY_HOST=$(echo "${PRIVATE_REGISTRY}" | cut -d/ -f1)
echo "--- 登录 SWR ${REGISTRY_HOST} ---"
if [ -z "${SWR_AK}" ] || [ -z "${SWR_LOGIN_KEY}" ]; then
    echo "[✗] 未填 SWR_AK / SWR_LOGIN_KEY，请在 config/cluster.env 配置" >&2
    exit 1
fi
if command -v docker &>/dev/null && systemctl is-active --quiet docker 2>/dev/null; then
    CTL="docker"
else
    command -v nerdctl &>/dev/null && CTL="nerdctl" || { echo "[✗] 需要 docker 或 nerdctl"; exit 1; }
fi
echo "${SWR_LOGIN_KEY}" | ${CTL} login "${REGISTRY_HOST}" -u "${SWR_USERNAME}" --password-stdin \
    || { echo "[✗] SWR 登录失败，检查 SWR_AK/SWR_LOGIN_KEY/region"; exit 1; }
echo "[✓] SWR 登录成功，使用 ${CTL} 推送"

# --- 收集镜像清单 ---
echo ""
echo "--- 收集镜像清单 ---"
K8S_SRC=$(kubeadm config images list \
    --kubernetes-version "v${KUBE_VERSION}" \
    --image-repository "registry.aliyuncs.com/google_containers" 2>/dev/null)

declare -a PAIRS
for img in $K8S_SRC; do
    PAIRS+=("${img}|${IMAGE_REPOSITORY}/${img##*/}")
done
PAIRS+=("ghcr.io/kube-vip/kube-vip:${KUBEVIP_VERSION}|${KUBEVIP_IMAGE}")
for c in node cni kube-controllers; do
    PAIRS+=("m.daocloud.io/docker.io/calico/${c}:${CALICO_VERSION}|${CALICO_IMAGE_REGISTRY}/calico/${c}:${CALICO_VERSION}")
done

echo "共 ${#PAIRS[@]} 个镜像待推送"
echo ""

# --- 拉取（可选）→ 打标签 → 推送 ---
FAIL=0
for pair in "${PAIRS[@]}"; do
    src="${pair%%|*}"
    tgt="${pair##*|}"
    echo ">>> $src"
    echo "    → $tgt"

    if [ "$MODE" == "pull" ]; then
        ${CTL} pull --platform linux/amd64 "$src" 2>/dev/null || { echo "  [✗] 拉取失败"; FAIL=$((FAIL+1)); continue; }
    fi
    ${CTL} tag "$src" "$tgt" 2>/dev/null || { echo "  [✗] 打标签失败（本地无此镜像？试 --pull）"; FAIL=$((FAIL+1)); continue; }
    ${CTL} push --platform linux/amd64 "$tgt" 2>/dev/null || { echo "  [✗] 推送失败"; FAIL=$((FAIL+1)); continue; }
    echo "  [✓] 已推送"
done

echo ""
echo "=========================================="
if [ $FAIL -eq 0 ]; then
    echo " ✓ 全部 ${#PAIRS[@]} 个镜像已推送到 ${PRIVATE_REGISTRY}"
else
    echo " ✗ 有 ${FAIL} 个镜像失败，请检查上方日志"
    exit 1
fi
echo "=========================================="
