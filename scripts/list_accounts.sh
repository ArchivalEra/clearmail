#!/bin/bash
# list_accounts.sh - 列出所有邮箱账户
# 列出 home 目录在 /var/mail/users/ 下的所有系统用户
#
# 用法: list_accounts.sh
# 退出码: 0=成功

set -uo pipefail

MAILDIR_ROOT="/var/mail/users"

# 通过 passwd 文件筛选 home 目录在 Maildir 根下的用户
# passwd 格式: username:x:uid:gid:comment:home:shell
# 匹配 home 以 /var/mail/users/ 开头的用户
# grep 无匹配时返回 1，用 || true 保证脚本退出码始终为 0
grep -E "^[^:]+:[^:]*:[^:]*:[^:]*:[^:]*:${MAILDIR_ROOT}/[^:]+:" /etc/passwd 2>/dev/null | cut -d: -f1 | sort || true

exit 0
