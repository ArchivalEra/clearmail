# 端到端功能验证清单

部署完成后，按以下清单逐项验证功能是否正常。

## 1. SMTP 入站收信验证

**操作**：从外部邮箱（如 Gmail）发送邮件至 `test@<domain>`

**预期结果**：
- 邮件成功送达
- 在服务器上检查：`ls /var/mail/users/test/Maildir/new/` 应有新邮件文件
- 查看日志：`journalctl -u opensmtpd -f` 应显示投递成功

---

## 2. SMTP 出站发信验证

**操作**：使用 swaks 或 K-9 Mail 通过 465 端口发送邮件至外部地址

```bash
# 使用 swaks 测试
swaks --to external@gmail.com \
      --from test@<domain> \
      --server mail.<domain> \
      --port 465 \
      --tls \
      --auth PLAIN \
      --auth-user test@<domain> \
      --auth-password <password>
```

**预期结果**：
- 邮件发送成功，返回 250 OK
- 外部邮箱收到邮件
- 邮件头包含 `DKIM-Signature` 字段

---

## 3. SASL 认证验证

**操作**：未认证客户端尝试通过 587 端口发信

```bash
swaks --to external@gmail.com \
      --from test@<domain> \
      --server mail.<domain> \
      --port 587 \
      --tls
```

**预期结果**：
- 服务器返回 535 Authentication failed
- 邮件被拒绝发送

---

## 4. IMAP 拉取验证

**操作**：通过 K-9 Mail 或 openssl 连接 993 端口

```bash
openssl s_client -connect mail.<domain>:993 -crlf
# 输入:
# a1 LOGIN test@<domain> <password>
# a2 LIST "" "*"
# a3 SELECT INBOX
# a4 FETCH 1:* (BODY[HEADER.FIELDS (SUBJECT FROM DATE)])
# a5 LOGOUT
```

**预期结果**：
- 认证成功
- 可列出邮件
- 可读取邮件内容

---

## 5. POP3 拉取验证

**操作**：通过 openssl 连接 995 端口

```bash
openssl s_client -connect mail.<domain>:995 -crlf
# 输入:
# USER test@<domain>
# PASS <password>
# LIST
# RETR 1
# QUIT
```

**预期结果**：
- 认证成功
- 可列出邮件
- 可下载邮件内容

---

## 6. TLS 强制验证

**操作**：尝试明文连接 465/993/995 端口

```bash
# 尝试明文连接 465 (应失败)
nc mail.<domain> 465
# 预期: 连接被拒绝或无响应

# 尝试明文连接 993 (应失败)
nc mail.<domain> 993
# 预期: 连接被拒绝或无响应
```

**预期结果**：
- 明文连接被拒绝
- 仅 TLS 连接可建立

---

## 7. DKIM 验证

**操作**：发送邮件至 Gmail 或 mail-tester.com

**预期结果**：
- 在 Gmail 中查看邮件原始内容：`Authentication-Results: dkim=pass`
- 或在 mail-tester.com 检查 DKIM 签名状态为 pass

---

## 8. FIFO 清理验证

**操作**：
```bash
# 1. 填充邮件至超过 5GB (创建大附件邮件或批量发送)
# 2. 检查当前占用
du -sh /var/mail/users/

# 3. 手动触发清理
./scripts/clean_maildir.sh

# 4. 检查清理后占用
du -sh /var/mail/users/

# 5. 查看清理日志
tail -f /var/log/mail-cleaner.log
```

**预期结果**：
- 清理前总占用 > 5GB
- 清理后总占用 ≤ 5GB
- 最老的邮件被优先删除
- 日志记录删除数量和释放空间

---

## 9. 账户管理验证

**操作**：
```bash
# 创建账户
./scripts/create_account.sh testuser password123
# 预期: 账户创建成功

# 列出账户
./scripts/list_accounts.sh
# 预期: 输出包含 testuser

# 验证账户可认证 (通过 IMAP 登录测试)

# 修改密码
./scripts/change_password.sh testuser newpass456
# 预期: 密码修改成功

# 验证新密码可认证，旧密码失效

# 删除账户
./scripts/delete_account.sh testuser
# 预期: 账户删除成功

# 验证账户无法再认证
```

**预期结果**：
- 所有操作成功执行
- 退出码符合预期
- 账户状态正确变更

---

## 10. 幂等部署验证

**操作**：
```bash
# 在已部署系统上再次执行部署脚本
./install.sh --domain=<domain> --email=<email>
```

**预期结果**：
- 脚本正常完成，无错误
- 无重复配置
- 服务保持正常运行

---

## 11. 服务自启动验证

**操作**：
```bash
# 重启 VPS
sudo reboot

# 重启后检查服务状态
systemctl is-active opensmtpd
systemctl is-active dovecot
systemctl is-active opendkim
```

**预期结果**：
- 三个服务均为 active(running)
- 邮件收发功能正常

---

## 12. 证书续期验证

**操作**：
```bash
# 检查 acme.sh 续期 cron 任务
crontab -l | grep acme

# 检查证书有效期
openssl x509 -in /etc/letsencrypt/live/mail.<domain>/fullchain.pem -dates -noout
```

**预期结果**：
- acme.sh 续期 cron 任务存在
- 证书有效期 > 30 天
- 续期任务会自动执行
