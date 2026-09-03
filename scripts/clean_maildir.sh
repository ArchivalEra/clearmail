#!/bin/bash
# clean_maildir.sh - FIFO 邮件清理脚本
# 当所有账户 Maildir 总占用超过阈值时，按 mtime 从老到新依次删除邮件
#
# 用法: clean_maildir.sh (无参数，由 cron 触发)
# 环境变量:
#   MAILDIR_ROOT  : Maildir 根目录 (默认 /var/mail/users)
#   THRESHOLD_GB  : 磁盘阈值 GB (默认 5)
#   LOG_FILE      : 日志路径 (默认 /var/log/mail-cleaner.log)
# 退出码: 0=成功

set -uo pipefail

# 配置 (可通过环境变量覆盖)
MAILDIR_ROOT="${MAILDIR_ROOT:-/var/mail/users}"
THRESHOLD_GB="${THRESHOLD_GB:-5}"
LOG_FILE="${LOG_FILE:-/var/log/mail-cleaner.log}"

# 转换为字节
THRESHOLD_BYTES=$((THRESHOLD_GB * 1024 * 1024 * 1024))

# 日志函数
log() {
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] $*" >> "$LOG_FILE"
}

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"

# 检查 Maildir 根目录是否存在
if [[ ! -d "$MAILDIR_ROOT" ]]; then
    log "ERROR: MAILDIR_ROOT $MAILDIR_ROOT 不存在"
    exit 0
fi

# 统计当前总占用 (字节)
CURRENT_SIZE=$(du -sb "$MAILDIR_ROOT" 2>/dev/null | cut -f1)
CURRENT_SIZE="${CURRENT_SIZE:-0}"

# 转换为 MB 用于日志显示
CURRENT_MB=$((CURRENT_SIZE / 1024 / 1024))
THRESHOLD_MB=$((THRESHOLD_BYTES / 1024 / 1024))

# 检查是否需要清理
if [[ $CURRENT_SIZE -le $THRESHOLD_BYTES ]]; then
    log "no_cleanup_needed total=${CURRENT_MB}MB threshold=${THRESHOLD_MB}MB"
    exit 0
fi

log "cleanup_started total=${CURRENT_MB}MB threshold=${THRESHOLD_MB}MB"

# 全局收集所有邮件文件并按 mtime 排序 (最老在前)
# -printf '%T@ %s %p\n': mtime(纪元秒) 大小(字节) 路径
# sort -n: 按 mtime 数值升序排序
# 仅扫描 cur/ 和 new/ 目录，不删除 tmp/ 中的临时文件
TMP_LIST=$(mktemp)
trap 'rm -f "$TMP_LIST"' EXIT

find "$MAILDIR_ROOT" -type f \
    \( -path "*/cur/*" -o -path "*/new/*" \) \
    -printf '%T@ %s %p\n' 2>/dev/null | \
    sort -n > "$TMP_LIST"

# 逐文件删除，直到总占用降到阈值以下
DELETED_COUNT=0
FREED_BYTES=0
WARN_COUNT=0

while IFS=' ' read -r timestamp size filepath; do
    # 检查是否已达到阈值
    if [[ $CURRENT_SIZE -le $THRESHOLD_BYTES ]]; then
        break
    fi

    # 跳过空行
    [[ -z "$filepath" ]] && continue

    # 尝试删除文件
    if rm -f "$filepath" 2>/dev/null; then
        DELETED_COUNT=$((DELETED_COUNT + 1))
        FREED_BYTES=$((FREED_BYTES + size))
        CURRENT_SIZE=$((CURRENT_SIZE - size))
    else
        WARN_COUNT=$((WARN_COUNT + 1))
        log "WARNING: cannot delete $filepath: Permission denied or file not found"
    fi
done < "$TMP_LIST"

# 计算清理后的总占用
AFTER_SIZE=$(du -sb "$MAILDIR_ROOT" 2>/dev/null | cut -f1)
AFTER_SIZE="${AFTER_SIZE:-0}"
AFTER_MB=$((AFTER_SIZE / 1024 / 1024))
FREED_MB=$((FREED_BYTES / 1024 / 1024))

# 记算清理后实际占用 (用于校验)
log "cleanup_completed deleted=${DELETED_COUNT} freed=${FREED_MB}MB total_after=${AFTER_MB}MB warnings=${WARN_COUNT}"

exit 0
