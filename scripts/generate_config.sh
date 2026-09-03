#!/bin/bash
# generate_config.sh - 配置生成脚本
# 根据用户输入参数替换所有模板中的占位符，输出到对应系统路径
#
# 用法: generate_config.sh --domain=<domain> --mx-hostname=<mx> --cert-path=<path>
# 退出码: 0=成功, 1=参数错误, 2=环境错误(root/模板目录)

set -uo pipefail

# 默认值
DOMAIN=""
MX_HOSTNAME=""
CERT_PATH=""
PROJECT_ROOT=""

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
        --project-root=*)
            PROJECT_ROOT="${arg#*=}"
            ;;
        -h|--help)
            echo "用法: $0 --domain=<domain> --mx-hostname=<mx> --cert-path=<path> [--project-root=<path>]"
            echo "  --domain        邮箱域名 (必填)"
            echo "  --mx-hostname   MX 主机名 (必填)"
            echo "  --cert-path     证书路径 (必填)"
            echo "  --project-root  项目根目录 (默认: 自动检测)"
            exit 0
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
    exit 1
fi
if [[ -z "$MX_HOSTNAME" ]]; then
    echo "错误: --mx-hostname 参数必填" >&2
    exit 1
fi
if [[ -z "$CERT_PATH" ]]; then
    echo "错误: --cert-path 参数必填" >&2
    exit 1
fi

# 域名格式校验
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
    echo "错误: 域名格式不合法: $DOMAIN" >&2
    exit 1
fi
if [[ ! "$MX_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
    echo "错误: MX 主机名格式不合法: $MX_HOSTNAME" >&2
    exit 1
fi

# 检查 root 权限 (需要写入 /etc)
if [[ $EUID -ne 0 ]]; then
    echo "错误: 需要 root 权限执行" >&2
    exit 2
fi

# 检查模板目录存在
if [[ ! -d "$CONFIG_DIR" ]]; then
    echo "错误: 配置模板目录不存在: $CONFIG_DIR" >&2
    exit 2
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
    if ! mkdir -p "$(dirname "$target")"; then
        echo "错误: 无法创建目录 $(dirname "$target")" >&2
        return 1
    fi

    # 替换占位符
    if ! sed \
        -e "s|{{DOMAIN}}|${DOMAIN}|g" \
        -e "s|{{MX_HOSTNAME}}|${MX_HOSTNAME}|g" \
        -e "s|{{CERT_PATH}}|${CERT_PATH}|g" \
        -e "s|{{PROJECT_ROOT}}|${PROJECT_ROOT}|g" \
        "$tmpl" > "$target"; then
        echo "错误: 模板渲染失败: $tmpl" >&2
        return 1
    fi

    echo "  生成: $target"
    return 0
}

echo "生成配置文件..."

# 1. OpenSMTPD 配置
render_template "$CONFIG_DIR/opensmtpd.conf.tmpl" "/etc/opensmtpd.conf" || exit 2

# 2. Dovecot 配置
render_template "$CONFIG_DIR/dovecot/dovecot.conf.tmpl" "/etc/dovecot/dovecot.conf" || exit 2
render_template "$CONFIG_DIR/dovecot/conf.d/10-auth.conf.tmpl" "/etc/dovecot/conf.d/10-auth.conf" || exit 2
render_template "$CONFIG_DIR/dovecot/conf.d/10-mail.conf.tmpl" "/etc/dovecot/conf.d/10-mail.conf" || exit 2
render_template "$CONFIG_DIR/dovecot/conf.d/10-ssl.conf.tmpl" "/etc/dovecot/conf.d/10-ssl.conf" || exit 2
render_template "$CONFIG_DIR/dovecot/conf.d/10-master.conf.tmpl" "/etc/dovecot/conf.d/10-master.conf" || exit 2

# 3. OpenDKIM 配置
render_template "$CONFIG_DIR/opendkim.conf.tmpl" "/etc/opendkim.conf" || exit 2
render_template "$CONFIG_DIR/KeyTable.tmpl" "/etc/opendkim/KeyTable" || exit 2
render_template "$CONFIG_DIR/SigningTable.tmpl" "/etc/opendkim/SigningTable" || exit 2

# 4. cron 清理任务
render_template "$CONFIG_DIR/cron-clean.tmpl" "/etc/cron.d/clean-maildir" || exit 2
chmod 644 /etc/cron.d/clean-maildir

# 5. 创建 OpenDKIM 密钥目录
mkdir -p /etc/opendkim/keys

# 6. 创建 Maildir 根目录
mkdir -p /var/mail/users
chmod 755 /var/mail/users

echo ""
echo "配置文件生成完成。"
exit 0
