#!/bin/bash
# create_account.sh - 创建邮箱账户
# 创建系统用户并初始化对应 Maildir
#
# 用法: create_account.sh <username> <password>
# 退出码: 0=成功, 1=参数缺失, 2=用户名格式不合法, 3=密码长度不足, 4=用户已存在

set -uo pipefail

# Maildir 根目录
MAILDIR_ROOT="/var/mail/users"

# 参数校验
if [[ $# -ne 2 ]]; then
    echo "用法: $0 <username> <password>" >&2
    echo "  username : 邮箱用户名 (localpart，不含域名)" >&2
    echo "  password : 邮箱密码" >&2
    exit 1
fi

USERNAME="$1"
PASSWORD="$2"

# 校验用户名格式: 小写字母/数字/./-，1-64 字符
if [[ ! "$USERNAME" =~ ^[a-z0-9.-]{1,64}$ ]]; then
    echo "错误: 用户名格式不合法: $USERNAME" >&2
    echo "  规则: 仅含小写字母、数字、点号(.)、连字符(-)，长度 1-64" >&2
    exit 2
fi

# 校验密码长度 >= 8
if [[ ${#PASSWORD} -lt 8 ]]; then
    echo "错误: 密码长度不足，至少 8 个字符 (当前 ${#PASSWORD})" >&2
    exit 3
fi

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo "错误: 需要 root 权限执行" >&2
    exit 5
fi

# 检查 Maildir 根目录存在
if [[ ! -d "$MAILDIR_ROOT" ]]; then
    mkdir -p "$MAILDIR_ROOT"
    chmod 755 "$MAILDIR_ROOT"
fi

# 检查用户是否已存在
if id "$USERNAME" >/dev/null 2>&1; then
    echo "错误: 用户 '$USERNAME' 已存在" >&2
    exit 4
fi

# 创建系统用户
# -m: 创建 home 目录
# -d: 指定 home 路径
# -s: 指定 shell 为 nologin (禁止 SSH 登录)
# -G: 加入 mail 组
useradd -m -d "$MAILDIR_ROOT/$USERNAME" -s /usr/sbin/nologin -G mail "$USERNAME"

# 设置密码
echo "$USERNAME:$PASSWORD" | chpasswd

# 创建 Maildir 三级目录
MAILDIR_HOME="$MAILDIR_ROOT/$USERNAME/Maildir"
mkdir -p "$MAILDIR_HOME"/{cur,new,tmp}

# 设置权限
# Maildir 目录属主为该用户，属组为 mail
# 权限 700: 仅用户本人可读写
chown -R "$USERNAME:mail" "$MAILDIR_ROOT/$USERNAME"
chmod 700 "$MAILDIR_HOME"
chmod 700 "$MAILDIR_HOME"/{cur,new,tmp}

echo "账户创建成功:"
echo "  用户名: $USERNAME"
echo "  Maildir: $MAILDIR_HOME"
echo "  可通过 IMAP/SMTP 认证收发邮件"

exit 0
