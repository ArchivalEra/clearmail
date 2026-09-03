#!/bin/bash
# install.sh - 极简邮件服务器一键部署脚本
# 在 Ubuntu 22.04 LTS 上幂等部署 OpenSMTPD + Dovecot + OpenDKIM + acme.sh
#
# 用法: install.sh --domain=<domain> --email=<email> --mx-hostname=<mx>
#   --domain      邮箱域名，如 baidu.com，最终邮箱为 xxx@baidu.com
#   --email       Let's Encrypt 注册邮箱，用于证书到期通知
#   --mx-hostname MX 主机名，如 mail.baidu.com 或 mx.xiaomi.com
# 退出码:
#   0 = 成功
#   1 = 参数错误
#   2 = 前置检查失败 (OS/端口/权限)
#   3 = 包安装失败
#   4 = 证书申请失败
#   5 = 服务启动失败

set -uo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# 项目根目录 (脚本所在目录)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# 默认参数
DOMAIN=""
EMAIL=""
MX_HOSTNAME=""

# 解析参数
for arg in "$@"; do
    case "$arg" in
        --domain=*)
            DOMAIN="${arg#*=}"
            ;;
        --email=*)
            EMAIL="${arg#*=}"
            ;;
        --mx-hostname=*)
            MX_HOSTNAME="${arg#*=}"
            ;;
        -h|--help)
            echo "用法: $0 --domain=<domain> --email=<email> --mx-hostname=<mx>"
            echo ""
            echo "参数:"
            echo "  --domain      邮箱域名，如 baidu.com，最终邮箱为 xxx@baidu.com"
            echo "  --email       Let's Encrypt 注册邮箱，用于证书到期通知"
            echo "  --mx-hostname MX 主机名，如 mail.baidu.com 或 mx.xiaomi.com"
            echo ""
            echo "退出码:"
            echo "  0 = 成功"
            echo "  1 = 参数错误"
            echo "  2 = 前置检查失败"
            echo "  3 = 包安装失败"
            echo "  4 = 证书申请失败"
            echo "  5 = 服务启动失败"
            exit 0
            ;;
        *)
            error "未知参数: $arg"
            exit 1
            ;;
    esac
done

# 校验必填参数
if [[ -z "$DOMAIN" ]]; then
    error "--domain 参数必填，如 --domain=baidu.com"
    exit 1
fi
if [[ -z "$EMAIL" ]]; then
    error "--email 参数必填"
    exit 1
fi
if [[ -z "$MX_HOSTNAME" ]]; then
    error "--mx-hostname 参数必填，如 --mx-hostname=mail.baidu.com"
    exit 1
fi

CERT_PATH="/etc/letsencrypt/live/$MX_HOSTNAME"
DKIM_SELECTOR="mail"
DKIM_KEY_DIR="/etc/opendkim/keys"

info "部署参数:"
info "  域名:        $DOMAIN"
info "  MX 主机名:   $MX_HOSTNAME"
info "  注册邮箱:    $EMAIL"
info "  证书路径:    $CERT_PATH"
echo ""

# ============================================================
# Phase 1: 前置检查
# ============================================================
info "Phase 1: 前置检查..."

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    error "需要 root 权限执行"
    exit 2
fi

# 检查 OS 版本
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]] || [[ "$VERSION_ID" != "22.04" ]]; then
        error "仅支持 Ubuntu 22.04 LTS，当前: $ID $VERSION_ID"
        exit 2
    fi
else
    error "无法确定操作系统版本"
    exit 2
fi

# 检查端口占用
PORTS=(25 465 587 993 995)
for port in "${PORTS[@]}"; do
    if ss -tlnp 2>/dev/null | grep -q ":${port} " ; then
        # 排除我们自己已部署的服务
        if ! ss -tlnp 2>/dev/null | grep ":${port} " | grep -qE 'opensmtpd|dovecot'; then
            error "端口 $port 被其他服务占用"
            ss -tlnp | grep ":${port} "
            exit 2
        fi
    fi
done

success "前置检查通过"
echo ""

# ============================================================
# Phase 2: 安装软件包 (幂等)
# ============================================================
info "Phase 2: 安装软件包..."

# 检查并安装包
install_package() {
    local pkg="$1"
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        info "  $pkg 已安装，跳过"
    else
        info "  安装 $pkg..."
        if ! apt-get install -y "$pkg" >/dev/null 2>&1; then
            error "安装 $pkg 失败"
            exit 3
        fi
    fi
}

# 更新包索引 (幂等: 仅当缓存超过 1 小时才更新)
if [[ ! -f /var/cache/apt/pkgcache.bin ]] || \
   [[ $(find /var/cache/apt/pkgcache.bin -mmin +60 2>/dev/null) ]]; then
    info "  更新包索引..."
    apt-get update >/dev/null 2>&1
fi

install_package "opensmtpd"
install_package "dovecot-imapd"
install_package "dovecot-pop3d"
install_package "opendkim"
install_package "opendkim-tools"

# 安装 acme.sh (幂等)
ACME_HOME="/root/.acme.sh"
if [[ ! -f "$ACME_HOME/acme.sh" ]]; then
    info "  安装 acme.sh..."
    if [[ ! -d /tmp/acme.sh ]]; then
        git clone https://github.com/acmesh-official/acme.sh.git /tmp/acme.sh >/dev/null 2>&1 || \
        curl -sL https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh -o /tmp/acme.sh-install.sh
    fi
    if [[ -d /tmp/acme.sh ]]; then
        cd /tmp/acme.sh
        ./acme.sh --install --home "$ACME_HOME" --accountemail "$EMAIL" >/dev/null 2>&1
        cd "$PROJECT_ROOT"
    fi
fi

success "软件包安装完成"
echo ""

# ============================================================
# Phase 3: 生成配置
# ============================================================
info "Phase 3: 生成配置文件..."

if ! "$PROJECT_ROOT/scripts/generate_config.sh" \
    --domain="$DOMAIN" \
    --mx-hostname="$MX_HOSTNAME" \
    --cert-path="$CERT_PATH"; then
    error "配置生成失败"
    exit 2
fi

success "配置文件生成完成"
echo ""

# ============================================================
# Phase 4: DKIM 密钥生成
# ============================================================
info "Phase 4: DKIM 密钥生成..."

DKIM_PRIVATE="$DKIM_KEY_DIR/$DOMAIN.private"
DKIM_PUBLIC="$DKIM_KEY_DIR/$DOMAIN.txt"

if [[ -f "$DKIM_PRIVATE" ]]; then
    info "  DKIM 密钥已存在，跳过生成"
else
    mkdir -p "$DKIM_KEY_DIR"
    if opendkim-genkey -D "$DKIM_KEY_DIR" -d "$DOMAIN" -s "$DKIM_SELECTOR" 2>/dev/null; then
        # opendkim-genkey 生成 <selector>.private 和 <selector>.txt
        mv "$DKIM_KEY_DIR/$DKIM_SELECTOR.private" "$DKIM_PRIVATE" 2>/dev/null || true
        mv "$DKIM_KEY_DIR/$DKIM_SELECTOR.txt" "$DKIM_PUBLIC" 2>/dev/null || true
    elif command -v opendkim-genkey >/dev/null 2>&1; then
        # 某些系统使用不同语法
        opendkim-genkey -d "$DOMAIN" -s "$DKIM_SELECTOR" -D "$DKIM_KEY_DIR"
        mv "$DKIM_KEY_DIR/$DKIM_SELECTOR.private" "$DKIM_PRIVATE" 2>/dev/null || true
        mv "$DKIM_KEY_DIR/$DKIM_SELECTOR.txt" "$DKIM_PUBLIC" 2>/dev/null || true
    else
        warn "  opendkim-genkey 不可用，请手动生成 DKIM 密钥"
    fi

    # 设置密钥文件权限
    if [[ -f "$DKIM_PRIVATE" ]]; then
        chown opendkim:opendkim "$DKIM_PRIVATE" 2>/dev/null || chown root:root "$DKIM_PRIVATE"
        chmod 600 "$DKIM_PRIVATE"
        success "  DKIM 密钥生成完成"
    fi
fi

echo ""

# ============================================================
# Phase 5: TLS 证书申请
# ============================================================
info "Phase 5: TLS 证书申请..."

CERT_FULLCHAIN="$CERT_PATH/fullchain.pem"
CERT_PRIVKEY="$CERT_PATH/privkey.pem"

# 检查证书是否已存在且未过期
CERT_EXISTS=false
if [[ -f "$CERT_FULLCHAIN" ]] && [[ -f "$CERT_PRIVKEY" ]]; then
    if openssl x509 -in "$CERT_FULLCHAIN" -checkend 2592000 -noout 2>/dev/null; then
        CERT_EXISTS=true
        info "  证书已存在且未过期，跳过申请"
    else
        warn "  证书已过期，将重新申请"
    fi
fi

if [[ "$CERT_EXISTS" == "false" ]]; then
    # 临时放行 80 端口 (用于 ACME HTTP-01 验证)
    IPTABLES_RULE_ADDED=false
    if iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null; then
        :
    else
        iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
        IPTABLES_RULE_ADDED=true
    fi

    # 使用 acme.sh 申请证书
    ACME_BIN="$ACME_HOME/acme.sh"
    if [[ -f "$ACME_BIN" ]]; then
        info "  使用 acme.sh 申请证书..."
        if "$ACME_BIN" --issue -d "$MX_HOSTNAME" --standalone --server letsencrypt 2>&1; then
            mkdir -p "$CERT_PATH"
            "$ACME_BIN" --install-cert -d "$MX_HOSTNAME" \
                --key-file "$CERT_PRIVKEY" \
                --fullchain-file "$CERT_FULLCHAIN" \
                --reloadcmd "systemctl reload opensmtpd 2>/dev/null; systemctl reload dovecot 2>/dev/null" \
                2>&1
            success "  证书申请成功"
        else
            warn "  证书申请失败，请检查域名是否正确指向本服务器"
            warn "  可稍后手动执行: $ACME_BIN --issue -d $MX_HOSTNAME --standalone"
        fi
    else
        warn "  acme.sh 未安装，请手动申请证书"
    fi

    # 恢复防火墙规则
    if [[ "$IPTABLES_RULE_ADDED" == "true" ]]; then
        iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    fi
fi

echo ""

# ============================================================
# Phase 6: 创建 Maildir 根目录
# ============================================================
info "Phase 6: 创建 Maildir 根目录..."

MAILDIR_ROOT="/var/mail/users"
mkdir -p "$MAILDIR_ROOT"
chmod 755 "$MAILDIR_ROOT"
chown root:mail "$MAILDIR_ROOT"

success "Maildir 根目录就绪"
echo ""

# ============================================================
# Phase 7: 启动服务
# ============================================================
info "Phase 7: 启动服务..."

start_service() {
    local svc="$1"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        info "  $svc 已运行，重载配置..."
        systemctl reload "$svc" 2>/dev/null || systemctl restart "$svc" 2>/dev/null
    else
        info "  启动 $svc..."
        systemctl enable "$svc" >/dev/null 2>&1
        systemctl start "$svc" 2>/dev/null
    fi

    if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
        error "  $svc 启动失败"
        return 1
    fi
    success "  $svc 运行中"
    return 0
}

SERVICE_FAILED=false
start_service "opendkim" || SERVICE_FAILED=true
start_service "dovecot" || SERVICE_FAILED=true
start_service "opensmtpd" || SERVICE_FAILED=true

if [[ "$SERVICE_FAILED" == "true" ]]; then
    error "部分服务启动失败，请检查日志: journalctl -u <service-name>"
    exit 5
fi

echo ""

# ============================================================
# Phase 8: 输出部署摘要
# ============================================================
info "Phase 8: 部署摘要"

# 获取服务器 IP
SERVER_IP=$(curl -s4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo ""
echo "============================================================"
echo "  极简邮件服务器部署完成"
echo "============================================================"
echo ""
echo "【服务器信息】"
echo "  域名:        $DOMAIN"
echo "  MX 主机名:   $MX_HOSTNAME"
echo "  服务器 IP:   $SERVER_IP"
echo ""

echo "【DNS 记录配置 (请手动配置)】"
echo ""
echo "  1. MX 记录:"
echo "     $DOMAIN. IN MX 10 $MX_HOSTNAME."
echo ""
echo "  2. SPF 记录 (TXT):"
echo "     $DOMAIN. IN TXT \"v=spf1 ip4:$SERVER_IP -all\""
echo ""

if [[ -f "$DKIM_PUBLIC" ]]; then
    echo "  3. DKIM 记录 (TXT):"
    # 读取 DKIM 公钥文件并格式化输出
    while IFS= read -r line; do
        echo "     $line"
    done < "$DKIM_PUBLIC"
    echo ""
fi

echo "  4. DMARC 记录 (TXT):"
echo "     _dmarc.$DOMAIN. IN TXT \"v=DMARC1; p=reject; rua=mailto:$EMAIL\""
echo ""

echo "  5. PTR 反向 DNS:"
echo "     在 Oracle Cloud 控制台设置 $SERVER_IP 的反向 DNS 为 $MX_HOSTNAME"
echo "     路径: Networking > Virtual Cloud Networks > VCN > Subnet > VNIC > Edit Reverse DNS"
echo ""

echo "【Oracle Cloud 安全列表配置】"
echo "  在 VCN 的 Security List 中添加以下 Ingress 规则:"
echo "    - 端口 25  (TCP) 源 0.0.0.0/0  # SMTP 入站"
echo "    - 端口 465 (TCP) 源 0.0.0.0/0  # SMTPS 提交"
echo "    - 端口 587 (TCP) 源 0.0.0.0/0  # SMTP STARTTLS 提交"
echo "    - 端口 993 (TCP) 源 0.0.0.0/0  # IMAPS"
echo "    - 端口 995 (TCP) 源 0.0.0.0/0  # POP3S"
echo ""

echo "【K-9 Mail 客户端配置】"
echo "  IMAP 收信:"
echo "    服务器: $MX_HOSTNAME"
echo "    端口:   993"
echo "    安全:   SSL/TLS"
echo "    用户名: <username>@$DOMAIN"
echo ""
echo "  SMTP 发信:"
echo "    服务器: $MX_HOSTNAME"
echo "    端口:   465"
echo "    安全:   SSL/TLS"
echo "    用户名: <username>@$DOMAIN"
echo ""
echo "  POP3 收信 (可选):"
echo "    服务器: $MX_HOSTNAME"
echo "    端口:   995"
echo "    安全:   SSL/TLS"
echo ""

echo "【邮箱账户管理】"
echo "  创建账户: $PROJECT_ROOT/scripts/create_account.sh <username> <password>"
echo "  删除账户: $PROJECT_ROOT/scripts/delete_account.sh <username>"
echo "  修改密码: $PROJECT_ROOT/scripts/change_password.sh <username> <newpassword>"
echo "  列出账户: $PROJECT_ROOT/scripts/list_accounts.sh"
echo ""

echo "【后续步骤】"
echo "  1. 在 DNS 服务商配置上述 DNS 记录"
echo "  2. 在 Oracle Cloud 控制台配置 PTR 反向 DNS"
echo "  3. 在 Oracle Cloud 安全列表放行 5 个端口"
echo "  4. 创建邮箱账户: $PROJECT_ROOT/scripts/create_account.sh testuser yourpassword"
echo "  5. 在 K-9 Mail 中按上述配置添加账户"
echo ""

success "部署完成！"
exit 0
