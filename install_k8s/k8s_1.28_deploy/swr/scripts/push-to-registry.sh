#!/bin/bash
# ============================================================
# push-to-registry.sh
# 执行节点：一台能同时访问【公网或离线介质】和【私有仓库】的机器
# 功能：把 K8s 部署所需的全部镜像推送到私有仓库（Harbor / registry）
# 前置：先在 config/cluster.env 配置 PRIVATE_REGISTRY
# 用法：
#   ./push-to-registry.sh --pull       # 先联网拉取（DaoCloud/阿里云）再推送（有外网时）
#   ./push-to-registry.sh              # 用本地已有镜像推送（已 import 过 tar）
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

MODE="local"
[ "$1" == "--pull" ] && MODE="pull"

echo "=========================================="
echo " 推送镜像到私有仓库"
echo "=========================================="

# --- 前置检查 ---
if [ -z "${PRIVATE_REGISTRY}" ]; then
    echo "[✗] 未配置 PRIVATE_REGISTRY，请先编辑 config/cluster.env"
    exit 1
fi
echo "目标私有仓库: ${PRIVATE_REGISTRY}"
echo "运行模式: ${MODE}（pull=先联网拉取, local=用本地镜像）"
echo ""

# --- 登录华为云 SWR（用 cluster.env 的 AK 凭据，非交互）---
REGISTRY_HOST=$(echo "${PRIVATE_REGISTRY}" | cut -d/ -f1)   # swr.<region>.myhuaweicloud.com
echo "--- 登录 SWR ${REGISTRY_HOST} ---"
if [ -z "${SWR_AK}" ] || [ -z "${SWR_LOGIN_KEY}" ]; then
    echo "[✗] 未填 SWR_AK / SWR_LOGIN_KEY，请先在 config/cluster.env 配置"
    echo "    获取：SWR 控制台 → 我的凭证 → 访问密钥(AK/SK) → 生成登录指令"
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
# K8s 核心镜像：用阿里云源列出（保证 etcd tag 与版本匹配），再映射到私有仓库
K8S_SRC=$(kubeadm config images list \
    --kubernetes-version "v${KUBE_VERSION}" \
    --image-repository "registry.aliyuncs.com/google_containers" 2>/dev/null)

# 源镜像 → 私有仓库目标 的映射表（源|目标）
declare -a PAIRS
for img in $K8S_SRC; do
    # registry.aliyuncs.com/google_containers/X:tag → IMAGE_REPOSITORY/X:tag
    # IMAGE_REPOSITORY = swr.../zqli/google_containers，与部署侧拉取路径一致
    PAIRS+=("${img}|${IMAGE_REPOSITORY}/${img##*/}")
done
# kube-vip → KUBEVIP_IMAGE（swr.../zqli/ghcr.io/kube-vip/kube-vip:tag）
PAIRS+=("ghcr.io/kube-vip/kube-vip:${KUBEVIP_VERSION}|${KUBEVIP_IMAGE}")
# calico → CALICO_IMAGE_REGISTRY/calico/X（swr.../zqli/docker.io/calico/X:tag）
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
    # SWR 不接受多平台 OCI index，用 --platform 推单平台（真机验证 kube-vip 必需）
    ${CTL} push --platform linux/amd64 "$tgt" 2>/dev/null || { echo "  [✗] 推送失败"; FAIL=$((FAIL+1)); continue; }
    echo "  [✓] 已推送"
done

echo ""
echo "=========================================="
if [ $FAIL -eq 0 ]; then
    echo " ✓ 全部 ${#PAIRS[@]} 个镜像已推送到 ${PRIVATE_REGISTRY}"
    echo ""
    echo " 下一步："
    echo "   1. 确认 config/cluster.env 中 PRIVATE_REGISTRY 已设置"
    echo "   2. 各节点 containerd 配置信任私有仓库（自签证书/HTTP 见文档）"
    echo "   3. 执行 deploy-all.sh 正常部署，镜像自动从私有仓库拉取"
else
    echo " ✗ 有 ${FAIL} 个镜像失败，请检查上方日志"
    exit 1
fi
echo "=========================================="
