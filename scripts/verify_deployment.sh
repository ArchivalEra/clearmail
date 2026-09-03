#!/bin/bash
# verify_deployment.sh - 部署验证脚本
# 检查所有组件和服务状态是否正常
#
# 用法: verify_deployment.sh
# 退出码: 0=全部通过, 1=存在失败项

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() {
    echo -e "  ${GREEN}[PASS]${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

check_fail() {
    echo -e "  ${RED}[FAIL]${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

check_warn() {
    echo -e "  ${YELLOW}[WARN]${NC} $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

echo "============================================================"
echo "  部署验证"
echo "============================================================"
echo ""

# 1. 检查服务状态
echo "【1. 服务状态】"
for svc in opensmtpd dovecot opendkim; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        check_pass "$svc 服务运行中"
    else
        check_fail "$svc 服务未运行"
    fi

    if systemctl is-enabled "$svc" >/dev/null 2>&1; then
        check_pass "$svc 已设置开机自启"
    else
        check_fail "$svc 未设置开机自启"
    fi
done
echo ""

# 2. 检查端口监听
echo "【2. 端口监听】"
for port in 25 465 587 993 995; do
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        check_pass "端口 $port 正在监听"
    else
        check_fail "端口 $port 未监听"
    fi
done
echo ""

# 3. 检查配置文件
echo "【3. 配置文件】"
CONFIG_FILES=(
    "/etc/opensmtpd.conf"
    "/etc/dovecot/dovecot.conf"
    "/etc/dovecot/conf.d/10-auth.conf"
    "/etc/dovecot/conf.d/10-mail.conf"
    "/etc/dovecot/conf.d/10-ssl.conf"
    "/etc/dovecot/conf.d/10-master.conf"
    "/etc/opendkim.conf"
    "/etc/opendkim/KeyTable"
    "/etc/opendkim/SigningTable"
    "/etc/cron.d/clean-maildir"
)

for f in "${CONFIG_FILES[@]}"; do
    if [[ -f "$f" ]]; then
        if grep -q '{{' "$f" 2>/dev/null; then
            check_fail "$f 存在未替换的占位符"
        else
            check_pass "$f 存在且无占位符"
        fi
    else
        check_fail "$f 不存在"
    fi
done
echo ""

# 4. 检查 DKIM 密钥
echo "【4. DKIM 密钥】"
DKIM_KEY_DIR="/etc/opendkim/keys"
if [[ -d "$DKIM_KEY_DIR" ]]; then
    check_pass "DKIM 密钥目录存在"
    private_keys=$(find "$DKIM_KEY_DIR" -name "*.private" 2>/dev/null)
    if [[ -n "$private_keys" ]]; then
        check_pass "DKIM 私钥文件存在"
    else
        check_fail "DKIM 私钥文件不存在"
    fi
else
    check_fail "DKIM 密钥目录不存在"
fi
echo ""

# 5. 检查 TLS 证书
echo "【5. TLS 证书】"
CERT_DIR="/etc/letsencrypt/live"
if [[ -d "$CERT_DIR" ]]; then
    for cert_domain in "$CERT_DIR"/*/; do
        if [[ -f "${cert_domain}fullchain.pem" ]] && [[ -f "${cert_domain}privkey.pem" ]]; then
            if openssl x509 -in "${cert_domain}fullchain.pem" -checkend 86400 -noout 2>/dev/null; then
                check_pass "证书 $(basename "$cert_domain") 有效且未过期"
            else
                check_fail "证书 $(basename "$cert_domain") 已过期或即将过期"
            fi
        else
            check_fail "证书文件不完整: $cert_domain"
        fi
    done
else
    check_warn "证书目录不存在，可能尚未申请证书"
fi
echo ""

# 6. 检查 Maildir 根目录
echo "【6. Maildir 存储】"
MAILDIR_ROOT="/var/mail/users"
if [[ -d "$MAILDIR_ROOT" ]]; then
    check_pass "Maildir 根目录存在"
    # 统计当前占用
    CURRENT_SIZE=$(du -sb "$MAILDIR_ROOT" 2>/dev/null | cut -f1)
    CURRENT_MB=$((CURRENT_SIZE / 1024 / 1024))
    THRESHOLD_MB=$((5 * 1024))
    if [[ $CURRENT_MB -lt $THRESHOLD_MB ]]; then
        check_pass "Maildir 总占用 ${CURRENT_MB}MB < 5GB 上限"
    else
        check_warn "Maildir 总占用 ${CURRENT_MB}MB 接近或超过 5GB 上限"
    fi
else
    check_fail "Maildir 根目录不存在"
fi
echo ""

# 7. 检查 cron 清理任务
echo "【7. cron 清理任务】"
if [[ -f /etc/cron.d/clean-maildir ]]; then
    if grep -q "clean_maildir.sh" /etc/cron.d/clean-maildir; then
        check_pass "cron 清理任务已配置"
    else
        check_fail "cron 清理任务配置错误"
    fi
else
    check_fail "cron 清理任务文件不存在"
fi
echo ""

# 8. 检查内存占用
echo "【8. 内存占用】"
TOTAL_RSS=0
for svc in opensmtpd dovecot opendkim; do
    RSS=$(ps -C "$svc" -o rss --no-headers 2>/dev/null | awk '{s+=$1} END {print s+0}')
    TOTAL_RSS=$((TOTAL_RSS + RSS))
done
TOTAL_RSS_MB=$((TOTAL_RSS / 1024))
if [[ $TOTAL_RSS_MB -lt 200 ]]; then
    check_pass "总内存占用 ${TOTAL_RSS_MB}MB < 200MB 上限"
else
    check_warn "总内存占用 ${TOTAL_RSS_MB}MB 超过 200MB 上限"
fi
echo ""

# 汇总
echo "============================================================"
echo "  验证汇总"
echo "============================================================"
echo -e "  ${GREEN}通过: $PASS_COUNT${NC}"
echo -e "  ${RED}失败: $FAIL_COUNT${NC}"
echo -e "  ${YELLOW}警告: $WARN_COUNT${NC}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}部署验证通过！${NC}"
    exit 0
else
    echo -e "${RED}部署验证存在失败项，请检查上述 [FAIL] 项${NC}"
    exit 1
fi
