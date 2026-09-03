#!/bin/bash
# deploy-hook.sh - 证书续期后重载服务钩子
# 由 acme.sh 在证书续期成功后通过 --reloadcmd 调用
#
# 用法: deploy-hook.sh (无参数)
# 退出码: 0=成功

set -uo pipefail

# 重载 OpenSMTPD
if systemctl is-active --quiet opensmtpd 2>/dev/null; then
    systemctl reload opensmtpd 2>/dev/null || \
        systemctl restart opensmtpd 2>/dev/null
    echo "OpenSMTPD 已重载"
fi

# 重载 Dovecot
if systemctl is-active --quiet dovecot 2>/dev/null; then
    systemctl reload dovecot 2>/dev/null || \
        systemctl restart dovecot 2>/dev/null
    echo "Dovecot 已重载"
fi

exit 0
