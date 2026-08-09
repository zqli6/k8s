#!/bin/bash
# ============================================================
# 08-renew-certs.sh
# 执行节点：每个 master 节点（串行，一次一个）
# 功能：使用 openssl 重签证书为 10 年
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

echo "=========================================="
echo " 证书续期 10 年: $(hostname)"
echo "=========================================="
echo ""
echo "┌─────────────────────────────────────────────────────────┐"
echo "│  证书 10 年在哪里指定？                                    │"
echo "│                                                         │"
echo "│  方法 A（本脚本使用）: openssl 重签脚本                      │"
echo "│    → 通过 --days ${CERT_DAYS} 参数指定有效期                │"
echo "│    → 脚本: yuyicai/update-kube-cert                     │"
echo "│    → 用现有 CA 私钥重新签发所有叶子证书                      │"
echo "│                                                         │"
echo "│  方法 B: 重编译 kubeadm（备选，需 Go 环境）                  │"
echo "│    → 修改源码 cmd/kubeadm/app/constants/constants.go     │"
echo "│    → 常量: CertificateValidity = time.Hour * 24 * 365   │"
echo "│    → 改为: time.Hour * 24 * 365 * 10                    │"
echo "│    → 重新编译: make WHAT=cmd/kubeadm                     │"
echo "│                                                         │"
echo "│  方法 C: ClusterConfiguration 字段（v1.31+ 才支持）         │"
echo "│    → certificateValidityPeriod: 87600h                  │"
echo "│    → caCertificateValidityPeriod: 87600h                │"
echo "│    → v1.28 不支持此字段！                                  │"
echo "└─────────────────────────────────────────────────────────┘"
echo ""

# --- 前置检查 ---
if [ ! -f /etc/kubernetes/pki/ca.crt ]; then
    echo "[✗] 未找到 /etc/kubernetes/pki/ca.crt，本节点非控制平面"
    exit 1
fi

# 检查当前证书有效期
echo "--- 当前证书有效期 ---"
kubeadm certs check-expiration 2>/dev/null || true
echo ""

CURRENT_EXPIRE=$(openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate 2>/dev/null | cut -d= -f2)
echo "apiserver 证书到期: $CURRENT_EXPIRE"

# 如果已经是 10 年（距今 >9 年），跳过
EXPIRE_EPOCH=$(date -d "$CURRENT_EXPIRE" +%s 2>/dev/null || echo "0")
NOW_EPOCH=$(date +%s)
YEARS_LEFT=$(( (EXPIRE_EPOCH - NOW_EPOCH) / 86400 / 365 ))
if [ "$YEARS_LEFT" -gt 9 ]; then
    echo "[=] 证书剩余 ${YEARS_LEFT} 年，已是长期证书，跳过续期"
    exit 0
fi

# --- 1. 备份 ---
echo ""
echo "--- 备份证书 ---"
BACKUP_DIR="/etc/kubernetes/pki-backup-$(date +%Y%m%d%H%M%S)"
cp -a /etc/kubernetes/pki "$BACKUP_DIR"
cp -a /etc/kubernetes/*.conf "${BACKUP_DIR}/" 2>/dev/null || true
echo "[✓] 已备份到: $BACKUP_DIR"

# --- 2. 获取重签脚本（优先仓库内置 → 离线介质 → 联网兜底）---
CERT_SCRIPT="/tmp/update-kubeadm-cert.sh"
BUNDLED="${SCRIPT_DIR}/../../tools/update-kubeadm-cert.sh"
if [ -f "$BUNDLED" ]; then
    cp "$BUNDLED" "$CERT_SCRIPT"
    echo "[=] 使用仓库内置证书脚本: tools/update-kubeadm-cert.sh"
elif [ -f "${OFFLINE_DIR:-/opt/k8s-offline}/tools/update-kubeadm-cert.sh" ]; then
    cp "${OFFLINE_DIR:-/opt/k8s-offline}/tools/update-kubeadm-cert.sh" "$CERT_SCRIPT"
    echo "[=] 使用离线介质证书脚本"
else
    echo "下载证书续期脚本..."
    curl -sSL --connect-timeout 15 https://raw.githubusercontent.com/yuyicai/update-kube-cert/master/update-kubeadm-cert.sh -o "$CERT_SCRIPT" || {
        echo "[✗] 脚本下载失败，改用 kubeadm 内置续期（仅 1 年，非 10 年）"
        echo "[!] 要 10 年请把 tools/update-kubeadm-cert.sh 一并拷到节点后重跑"
        kubeadm certs renew all
        kubeadm certs check-expiration
        exit 0
    }
fi
# 校验脚本有效（新版含 KUBE_CERT_DAYS 变量）
if ! grep -q "KUBE_CERT_DAYS" "$CERT_SCRIPT"; then
    echo "[✗] 证书脚本内容异常（缺少 KUBE_CERT_DAYS），中止"
    exit 1
fi
chmod +x "$CERT_SCRIPT"
echo "[✓] 证书续期脚本就绪"

# --- 3. 执行续期 ---
# 新版 update-kube-cert 接口：--cri containerd（用 crictl 重启控制面）；
# 有效期用 KUBE_CERT_DAYS 环境变量指定（10年=3650天），--days 为兼容旧参数。
# 脚本用现有 CA 私钥经 openssl 重签所有叶子证书，并自动 crictl stopp 重启控制面 static pod。
echo ""
echo "--- 执行证书续期（叶子证书 ${CERT_DAYS} 天 ≈ 10 年）---"
echo "    ★ 10 年在此指定：KUBE_CERT_DAYS=${CERT_DAYS}（或 --days ${CERT_DAYS}）"
KUBE_CERT_DAYS=${CERT_DAYS} bash "$CERT_SCRIPT" --cri containerd --days ${CERT_DAYS}
echo "[✓] 证书已续期（脚本内部已用 crictl 重启控制面）"

# --- 4. 等待 API Server 恢复 ---
echo ""
echo "--- 等待 API Server 就绪 ---"
for i in $(seq 1 30); do
    if kubectl get --raw='/healthz' &>/dev/null; then
        echo "[✓] API Server 已就绪"
        break
    fi
    sleep 5
    echo "    等待中... [${i}/30]"
done

# --- 验证 ---
echo ""
echo "--- 续期后证书有效期 ---"
kubeadm certs check-expiration 2>/dev/null || {
    echo "使用 openssl 查看:"
    openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates
}

NEW_EXPIRE=$(openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate | cut -d= -f2)
echo ""
echo "[完成] apiserver 证书新到期时间: $NEW_EXPIRE"
echo ""
echo "> ⚠️ 注意: 所有 master 节点都需要执行本脚本"
echo ">    每执行一台后，确认 etcd 集群健康再执行下一台:"
echo ">    ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \\"
echo ">      --cacert=/etc/kubernetes/pki/etcd/ca.crt \\"
echo ">      --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \\"
echo ">      --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \\"
echo ">      endpoint health"
