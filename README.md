# 极简邮件服务器

在 Oracle Cloud VPS 上部署极简邮件服务器，基于 OpenSMTPD + Dovecot + OpenDKIM + acme.sh，支持单域名下数百个邮箱账户，5GB FIFO 邮件清理，内存占用 < 200MB。

## 功能特性

- SMTP 收发邮件（25 端口收信，465/587 端口发信）
- IMAP（993）和 POP3（995）服务
- 全程 SSL/TLS 加密
- DKIM 签名/验证
- SPF / DMARC 支持
- Maildir 格式存储，5GB 上限 FIFO 自动清理
- 单域名下数百个邮箱账户
- 一键幂等部署

## 前置条件

1. **Oracle Cloud VPS**：美国节点，Ubuntu 22.04 LTS
2. **25 端口已开放**：Oracle Cloud 默认屏蔽 25 端口出站流量，需申请解除
3. **域名已注册**：已指向 VPS 的 IP 地址
4. **root 权限**：部署脚本需以 root 身份执行
5. **内存**：VPS 至少 1GB RAM

## Oracle Cloud 25 端口开放说明

Oracle Cloud 默认屏蔽 25 端口的出站流量，需手动申请解除：

1. 登录 Oracle Cloud 控制台
2. 提交工单（Service Request）申请解除 25 端口出站限制
   - 路径：Support > Create Service Request
   - 说明用途：邮件服务器
   - 通常 24-48 小时内处理
3. 在 VCN 的 Security List 中添加 Ingress 规则放行入站端口

## 一键部署

```bash
# 1. 上传项目文件至 VPS
scp -r mail-server/ root@your-vps:/opt/mail-server/

# 2. 执行部署脚本
ssh root@your-vps
cd /opt/mail-server
chmod +x install.sh scripts/*.sh
./install.sh --domain=example.com --email=admin@example.com

# 3. 按部署摘要输出配置 DNS 记录
# 4. 创建邮箱账户
./scripts/create_account.sh testuser yourpassword123
```

## DNS 记录配置

部署完成后，脚本会输出所有需要配置的 DNS 记录。以下为配置说明：

### MX 记录
```
example.com. IN MX 10 mail.example.com.
```

### SPF 记录（TXT）
```
example.com. IN TXT "v=spf1 ip4:YOUR_VPS_IP -all"
```

### DKIM 记录（TXT）
部署脚本会输出 DKIM 公钥，格式如：
```
mail._domainkey.example.com. IN TXT "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQ..."
```

### DMARC 记录（TXT）
```
_dmarc.example.com. IN TXT "v=DMARC1; p=reject; rua=mailto:admin@example.com"
```

## PTR 反向 DNS 设置

在 Oracle Cloud 控制台设置反向 DNS：

1. 路径：Networking > Virtual Cloud Networks > 选择 VCN > Subnets > 选择 Subnet
2. 点击 VNIC 的 "Edit" > "Edit Reverse DNS"
3. 设置为 MX 主机名（如 `mail.example.com`）

## 防火墙配置

### iptables 规则
```bash
iptables -I INPUT -p tcp --dport 25  -j ACCEPT  # SMTP 入站
iptables -I INPUT -p tcp --dport 465 -j ACCEPT  # SMTPS 提交
iptables -I INPUT -p tcp --dport 587 -j ACCEPT  # SMTP STARTTLS 提交
iptables -I INPUT -p tcp --dport 993 -j ACCEPT  # IMAPS
iptables -I INPUT -p tcp --dport 995 -j ACCEPT  # POP3S
```

### Oracle Cloud 安全列表
在 VCN 的 Security List 中添加以下 Ingress 规则：

| 端口 | 协议 | 源 | 用途 |
|------|------|-----|------|
| 25 | TCP | 0.0.0.0/0 | SMTP 入站收信 |
| 465 | TCP | 0.0.0.0/0 | SMTPS 客户端提交 |
| 587 | TCP | 0.0.0.0/0 | SMTP STARTTLS 客户端提交 |
| 993 | TCP | 0.0.0.0/0 | IMAPS |
| 995 | TCP | 0.0.0.0/0 | POP3S |

## 邮箱账户管理

```bash
# 创建账户
./scripts/create_account.sh <username> <password>

# 删除账户
./scripts/delete_account.sh <username>

# 修改密码
./scripts/change_password.sh <username> <newpassword>

# 列出所有账户
./scripts/list_accounts.sh
```

**用户名规则**：仅含小写字母、数字、点号(.)、连字符(-)，长度 1-64 字符
**密码规则**：至少 8 个字符

## K-9 Mail 客户端配置

### IMAP 收信配置
| 项目 | 值 |
|------|-----|
| 服务器 | `mail.example.com`（MX 主机名） |
| 端口 | 993 |
| 安全类型 | SSL/TLS |
| 用户名 | `testuser@example.com`（完整邮箱地址） |
| 密码 | 账户密码 |

### SMTP 发信配置
| 项目 | 值 |
|------|-----|
| 服务器 | `mail.example.com`（MX 主机名） |
| 端口 | 465 |
| 安全类型 | SSL/TLS |
| 用户名 | `testuser@example.com` |
| 密码 | 账户密码 |
| 备选端口 | 587（STARTTLS） |

### POP3 收信配置（可选）
| 项目 | 值 |
|------|-----|
| 服务器 | `mail.example.com` |
| 端口 | 995 |
| 安全类型 | SSL/TLS |
| 用户名 | `testuser@example.com` |
| 密码 | 账户密码 |

### K-9 Mail 配置步骤

1. 打开 K-9 Mail，点击"添加账户"
2. 输入完整邮箱地址和密码
3. 选择"手动配置"
4. 选择"IMAP"或"POP3"作为收信方式
5. 按上述表格填写服务器配置
6. 按上述表格填写 SMTP 发信配置
7. 点击"下一步"完成配置

## 邮件存储与清理

- **存储格式**：Maildir，路径 `/var/mail/users/<username>/Maildir/`
- **总容量上限**：5GB（所有账户共享）
- **清理策略**：FIFO 淘汰，按邮件 mtime 从老到新删除
- **清理频率**：cron 每 10 分钟检查一次
- **清理日志**：`/var/log/mail-cleaner.log`

## 技术架构

| 组件 | 用途 | 端口 |
|------|------|------|
| OpenSMTPD | MTA，SMTP 收发 | 25, 465, 587 |
| Dovecot | IMAP/POP3 + SASL 认证 | 993, 995 |
| OpenDKIM | DKIM 签名/验证 | 8891 (内部 milter) |
| acme.sh | TLS 证书管理 | - (定时任务) |

## 故障排查

```bash
# 查看服务状态
systemctl status opensmtpd
systemctl status dovecot
systemctl status opendkim

# 查看日志
journalctl -u opensmtpd -f
journalctl -u dovecot -f
journalctl -u opendkim -f

# 查看清理日志
tail -f /var/log/mail-cleaner.log

# 检查端口监听
ss -tlnp | grep -E ':(25|465|587|993|995)'

# 检查证书
openssl x509 -in /etc/letsencrypt/live/mail.example.com/fullchain.pem -dates -noout
```
