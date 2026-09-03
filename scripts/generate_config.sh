#!/bin/bash
# generate_config.sh - 配置生成脚本
# 根据用户输入参数替换所有模板中的占位符，输出到对应系统路径
#
# 用法: generate_config.sh --domain=<domain> --mx-hostname=<mx> --cert-path=<path>
# 退出码: 0=成功, 1=参数错误

set -euo pipefail

# 默认值
DOMAIN=""
MX_HOSTNAME=""
CERT_PATH=""

# 项目根目录 (脚本所在目录的上一级)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"

# 解析参数
for arg in "$@"; do
    case "$arg" in
        --domain=*)
            DOMAIN="${arg#*=}"
            ;;
        --mx-hostname=*)
            MX_HOSTNAME="${arg#*=}"
            ;;
        --cert-path=*)
            CERT_PATH="${arg#*=}"
            ;;
        *)
            echo "错误: 未知参数 '$arg'" >&2
            exit 1
            ;;
    esac
done

# 校验必填参数
if [[ -z "$DOMAIN" ]]; then
    echo "错误: --domain 参数必填" >&2
    echo "用法: $0 --domain=<domain> --mx-hostname=<mx> --cert-path=<path>" >&2
    exit 1
fi
if [[ -z "$MX_HOSTNAME" ]]; then
    MX_HOSTNAME="mail.$DOMAIN"
fi
if [[ -z "$CERT_PATH" ]]; then
    CERT_PATH="/etc/letsencrypt/live/$MX_HOSTNAME"
fi

echo "配置生成参数:"
echo "  域名:        $DOMAIN"
echo "  MX 主机名:   $MX_HOSTNAME"
echo "  证书路径:    $CERT_PATH"
echo ""

# 替换模板中的占位符并输出到目标路径
# 参数: <模板文件> <目标文件>
render_template() {
    local tmpl="$1"
    local target="$2"

    if [[ ! -f "$tmpl" ]]; then
        echo "错误: 模板文件不存在: $tmpl" >&2
        return 1
    fi

    # 创建目标目录
    mkdir -p "$(dirname "$target")"

    # 替换占位符
    sed \
        -e "s|{{DOMAIN}}|${DOMAIN}|g" \
        -e "s|{{MX_HOSTNAME}}|${MX_HOSTNAME}|g" \
        -e "s|{{CERT_PATH}}|${CERT_PATH}|g" \
        "$tmpl" > "$target"

    echo "  生成: $target"
}

echo "生成配置文件..."

# 1. OpenSMTPD 配置
render_template "$CONFIG_DIR/opensmtpd.conf.tmpl" "/etc/opensmtpd.conf"

# 2. Dovecot 配置
render_template "$CONFIG_DIR/dovecot/dovecot.conf.tmpl" "/etc/dovecot/dovecot.conf"
render_template "$CONFIG_DIR/dovecot/conf.d/10-auth.conf.tmpl" "/etc/dovecot/conf.d/10-auth.conf"
render_template "$CONFIG_DIR/dovecot/conf.d/10-mail.conf.tmpl" "/etc/dovecot/conf.d/10-mail.conf"
render_template "$CONFIG_DIR/dovecot/conf.d/10-ssl.conf.tmpl" "/etc/dovecot/conf.d/10-ssl.conf"
render_template "$CONFIG_DIR/dovecot/conf.d/10-master.conf.tmpl" "/etc/dovecot/conf.d/10-master.conf"

# 3. OpenDKIM 配置
render_template "$CONFIG_DIR/opendkim.conf.tmpl" "/etc/opendkim.conf"
render_template "$CONFIG_DIR/KeyTable.tmpl" "/etc/opendkim/KeyTable"
render_template "$CONFIG_DIR/SigningTable.tmpl" "/etc/opendkim/SigningTable"

# 4. cron 清理任务
render_template "$CONFIG_DIR/cron-clean.tmpl" "/etc/cron.d/clean-maildir"
chmod 644 /etc/cron.d/clean-maildir

# 5. 创建 OpenDKIM 密钥目录
mkdir -p /etc/opendkim/keys

# 6. 创建 Maildir 根目录
mkdir -p /var/mail/users
chmod 755 /var/mail/users

echo ""
echo "配置文件生成完成。"
echo ""
echo "生成的文件列表:"
echo "  /etc/opensmtpd.conf"
echo "  /etc/dovecot/dovecot.conf"
echo "  /etc/dovecot/conf.d/10-auth.conf"
echo "  /etc/dovecot/conf.d/10-mail.conf"
echo "  /etc/dovecot/conf.d/10-ssl.conf"
echo "  /etc/dovecot/conf.d/10-master.conf"
echo "  /etc/opendkim.conf"
echo "  /etc/opendkim/KeyTable"
echo "  /etc/opendkim/SigningTable"
echo "  /etc/cron.d/clean-maildir"

exit 0
