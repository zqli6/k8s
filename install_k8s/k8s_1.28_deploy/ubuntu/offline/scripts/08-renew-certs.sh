#!/bin/bash
# ============================================================
# 08-renew-certs.sh
# 执行节点：每个 master 节点（串行）
# 功能：使用 openssl 重签证书为 10 年
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config/cluster.env" 2>/dev/null || source /opt/k8s-deploy/config/cluster.env

echo "=========================================="
echo " 证书续期 10 年: $(hostname)"
echo "=========================================="
echo ""

if [ ! -f /etc/kubernetes/pki/ca.crt ]; then
    echo "[✗] 未找到 /etc/kubernetes/pki/ca.crt"
    exit 1
fi

echo "--- 当前证书有效期 ---"
kubeadm certs check-expiration 2>/dev/null || true
CURRENT_EXPIRE=$(openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate 2>/dev/null | cut -d= -f2)
echo "apiserver 到期: $CURRENT_EXPIRE"

EXPIRE_EPOCH=$(date -d "$CURRENT_EXPIRE" +%s 2>/dev/null || echo "0")
NOW_EPOCH=$(date +%s)
YEARS_LEFT=$(( (EXPIRE_EPOCH - NOW_EPOCH) / 86400 / 365 ))
[ "$YEARS_LEFT" -gt 9 ] && { echo "[=] 证书剩余 ${YEARS_LEFT} 年，跳过"; exit 0; }

# --- 备份 ---
BACKUP_DIR="/etc/kubernetes/pki-backup-$(date +%Y%m%d%H%M%S)"
cp -a /etc/kubernetes/pki "$BACKUP_DIR"
cp -a /etc/kubernetes/*.conf "${BACKUP_DIR}/" 2>/dev/null || true
echo "[✓] 已备份到 $BACKUP_DIR"

# --- 获取重签脚本（优先本地）---
CERT_SCRIPT="/tmp/update-kubeadm-cert.sh"
BUNDLED="${SCRIPT_DIR}/../tools/update-kubeadm-cert.sh"
if [ -f "$BUNDLED" ]; then
    cp "$BUNDLED" "$CERT_SCRIPT"
elif [ -f "${OFFLINE_DIR:-/opt/k8s-offline}/tools/update-kubeadm-cert.sh" ]; then
    cp "${OFFLINE_DIR:-/opt/k8s-offline}/tools/update-kubeadm-cert.sh" "$CERT_SCRIPT"
else
    echo "[✗] 未找到证书脚本 tools/update-kubeadm-cert.sh"
    exit 1
fi
grep -q "KUBE_CERT_DAYS" "$CERT_SCRIPT" || { echo "[✗] 证书脚本异常"; exit 1; }
chmod +x "$CERT_SCRIPT"

# --- 执行续期 ---
KUBE_CERT_DAYS=${CERT_DAYS} bash "$CERT_SCRIPT" --cri containerd --days ${CERT_DAYS}
echo "[✓] 证书已续期"

# --- 等待 API Server 恢复 ---
for i in $(seq 1 30); do
    kubectl get --raw='/healthz' &>/dev/null && { echo "[✓] API Server 就绪"; break; }
    sleep 5
done

NEW_EXPIRE=$(openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate | cut -d= -f2)
echo "[完成] apiserver 新到期: $NEW_EXPIRE"
echo "> ⚠️ 每台 master 执行后确认 etcd 健康再执行下一台"
