#!/bin/bash
# ============================================================
# 08-renew-certs.sh
# 执行节点：每个 master 节点（串行，一次一个）
# 功能：使用 openssl 重签证书为 10 年
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

echo "=========================================="
echo " 证书续期 10 年: $(hostname)"
echo "=========================================="
echo ""
echo "  证书 10 年通过 openssl 重签实现（方法 A）：--days ${CERT_DAYS}"
echo "  脚本: yuyicai/update-kube-cert，用现有 CA 私钥重签所有叶子证书"
echo ""

# --- 前置检查 ---
if [ ! -f /etc/kubernetes/pki/ca.crt ]; then
    echo "[✗] 未找到 /etc/kubernetes/pki/ca.crt，本节点非控制平面"
    exit 1
fi

echo "--- 当前证书有效期 ---"
kubeadm certs check-expiration 2>/dev/null || true
echo ""

CURRENT_EXPIRE=$(openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate 2>/dev/null | cut -d= -f2)
echo "apiserver 证书到期: $CURRENT_EXPIRE"

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

# --- 2. 获取重签脚本 ---
CERT_SCRIPT="/tmp/update-kubeadm-cert.sh"
BUNDLED="${SCRIPT_DIR}/../tools/update-kubeadm-cert.sh"
if [ -f "$BUNDLED" ]; then
    cp "$BUNDLED" "$CERT_SCRIPT"
    echo "[=] 使用仓库内置证书脚本: tools/update-kubeadm-cert.sh"
elif [ -f "${OFFLINE_DIR:-/opt/k8s-offline}/tools/update-kubeadm-cert.sh" ]; then
    cp "${OFFLINE_DIR:-/opt/k8s-offline}/tools/update-kubeadm-cert.sh" "$CERT_SCRIPT"
    echo "[=] 使用离线介质证书脚本"
else
    echo "下载证书续期脚本..."
    curl -sSL --connect-timeout 15 https://raw.githubusercontent.com/yuyicai/update-kube-cert/master/update-kubeadm-cert.sh -o "$CERT_SCRIPT" || {
        echo "[✗] 脚本下载失败，改用 kubeadm 内置续期（仅 1 年）"
        kubeadm certs renew all
        kubeadm certs check-expiration
        exit 0
    }
fi
if ! grep -q "KUBE_CERT_DAYS" "$CERT_SCRIPT"; then
    echo "[✗] 证书脚本内容异常（缺少 KUBE_CERT_DAYS），中止"
    exit 1
fi
chmod +x "$CERT_SCRIPT"
echo "[✓] 证书续期脚本就绪"

# --- 3. 执行续期 ---
echo ""
echo "--- 执行证书续期（叶子证书 ${CERT_DAYS} 天 ≈ 10 年）---"
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
kubeadm certs check-expiration 2>/dev/null || openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates
NEW_EXPIRE=$(openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate | cut -d= -f2)
echo ""
echo "[完成] apiserver 证书新到期时间: $NEW_EXPIRE"
echo ""
echo "> ⚠️ 所有 master 节点都需执行本脚本；每台执行后确认 etcd 健康再执行下一台"
