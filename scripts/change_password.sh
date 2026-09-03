#!/bin/bash
# change_password.sh - 修改邮箱账户密码
#
# 用法: change_password.sh <username> <newpassword>
# 退出码: 0=成功, 1=参数缺失, 2=用户不存在, 3=密码长度不足

set -uo pipefail

# 参数校验
if [[ $# -ne 2 ]]; then
    echo "用法: $0 <username> <newpassword>" >&2
    echo "  username    : 邮箱用户名" >&2
    echo "  newpassword : 新密码" >&2
    exit 1
fi

USERNAME="$1"
NEWPASSWORD="$2"

# 检查用户是否存在
if ! id "$USERNAME" >/dev/null 2>&1; then
    echo "错误: 用户 '$USERNAME' 不存在" >&2
    exit 2
fi

# 校验密码长度 >= 8
if [[ ${#NEWPASSWORD} -lt 8 ]]; then
    echo "错误: 密码长度不足，至少 8 个字符 (当前 ${#NEWPASSWORD})" >&2
    exit 3
fi

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo "错误: 需要 root 权限执行" >&2
    exit 4
fi

# 修改密码
echo "$USERNAME:$NEWPASSWORD" | chpasswd

echo "密码修改成功: $USERNAME"
echo "  旧密码已失效"
echo "  新密码已生效"

exit 0
