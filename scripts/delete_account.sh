#!/bin/bash
# delete_account.sh - 删除邮箱账户
# 删除系统用户及其 Maildir 目录
#
# 用法: delete_account.sh <username>
# 退出码: 0=成功, 1=参数缺失, 2=用户不存在

set -euo pipefail

# 参数校验
if [[ $# -ne 1 ]]; then
    echo "用法: $0 <username>" >&2
    echo "  username : 邮箱用户名" >&2
    exit 1
fi

USERNAME="$1"

# 检查用户是否存在
if ! id "$USERNAME" >/dev/null 2>&1; then
    echo "错误: 用户 '$USERNAME' 不存在" >&2
    exit 2
fi

# 删除系统用户及其 home 目录 (即 Maildir)
# -r: 同时删除 home 目录
userdel -r "$USERNAME"

echo "账户删除成功: $USERNAME"
echo "  系统用户已移除"
echo "  Maildir 目录已删除"

exit 0
