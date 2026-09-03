# clearmail

Oracle Cloud VPS 上的极简邮件服务器。OpenSMTPD + Dovecot + OpenDKIM + acme.sh，单域名数百账户，共享 5GB FIFO 存储，全程 TLS。

## 技术栈

| 组件 | 作用 | 端口 |
|------|------|------|
| OpenSMTPD | MTA，SMTP 收发 | 25 / 465 / 587 |
| Dovecot | IMAP / POP3 / SASL 认证后端 | 993 / 995 |
| OpenDKIM | DKIM 签名与验证（milter） | 8891（内部） |
| acme.sh | Let's Encrypt 证书申请与自动续期 | — |

不使用 Postfix、数据库、Redis、Web 界面、反垃圾组件。内存占用 < 200MB。

## 部署

### 前置条件

- Oracle Cloud VPS，Ubuntu 22.04 LTS，ARM 或 x86 均可
- 域名已注册，A 记录已指向 VPS IP
- root 权限

### Oracle Cloud 端口放行

Oracle Cloud 有两层防火墙，都要放行 25 / 465 / 587 / 993 / 995：

**1. VCN 安全列表（Security List）**

Networking → Virtual Cloud Networks → 你的 VCN → Security Lists → Default Security List → Add Ingress Rules：

| Source CIDR | Protocol | Dest Port | 说明 |
|-------------|----------|-----------|------|
| 0.0.0.0/0 | TCP | 25 | SMTP 入站收信 |
| 0.0.0.0/0 | TCP | 465 | SMTPS 客户端提交 |
| 0.0.0.0/0 | TCP | 587 | SMTP STARTTLS 提交 |
| 0.0.0.0/0 | TCP | 993 | IMAPS |
| 0.0.0.0/0 | TCP | 995 | POP3S |

**2. iptables（VPS 本机）**

Oracle Cloud 的 Ubuntu 镜像自带 iptables 规则，默认只放行 22。需要手动放行：

```bash
iptables -I INPUT 1 -p tcp --dport 25  -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 465 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 587 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 993 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 995 -j ACCEPT
# 持久化
netfilter-persistent save
```

> **注意**：Oracle Cloud 的 25 端口出站（egress）默认是放行的，不需要提交工单。如果出站邮件发不出去，检查 iptables 的 OUTPUT 链和 VCN Security List 的 Egress Rules。

### PTR 反向 DNS

Oracle Cloud 控制台 → Compute → Instances → 你的实例 → 左下角 Resources → Attached VNICs → 点击 VNIC → Edit → **Hostname** 填写 MX 主机名（如 `mail.example.com`），保存后 Oracle 会自动设置 PTR。

### 一键部署

```bash
# 在 VPS 上
git clone git@github.com:ArchivalEra/clearmail.git /opt/mail-server
cd /opt/mail-server
chmod +x install.sh scripts/*.sh acme/*.sh

./install.sh --domain=baidu.com --email=admin@baidu.com --mx-hostname=mail.baidu.com
```

三个参数完全独立：
- `--domain`：邮箱域名，填 `baidu.com` 邮箱就是 `xxx@baidu.com`
- `--mx-hostname`：MX 主机名，通常 `mail.<domain>`，但也可以是任意主机名如 `mx.xiaomi.com`
- `--email`：Let's Encrypt 注册邮箱，仅用于证书到期通知

脚本会：
1. 安装 OpenSMTPD、Dovecot、OpenDKIM、acme.sh
2. 生成全部配置文件
3. 生成 DKIM 密钥对
4. 申请 Let's Encrypt 证书
5. 启动并 enable 三个服务
6. 输出 DNS 记录值和客户端配置参数

幂等，重复执行不会出错。

### DNS 记录

部署完成后脚本会打印 DNS 记录值，去你的 DNS 服务商手动添加：

| 类型 | 名称 | 值 |
|------|------|-----|
| MX | `example.com.` | `10 mail.example.com.` |
| TXT | `example.com.` | `v=spf1 ip4:<VPS_IP> -all` |
| TXT | `mail._domainkey.example.com.` | `v=DKIM1; k=rsa; p=<部署输出>` |
| TXT | `_dmarc.example.com.` | `v=DMARC1; p=reject; rua=mailto:admin@example.com` |

## 邮箱账户管理

```bash
cd /opt/mail-server

# 创建账户（立即生效，可收发邮件）
./scripts/create_account.sh alice MyPassword123

# 改密码
./scripts/change_password.sh alice NewPassword456

# 列出所有账户
./scripts/list_accounts.sh

# 删除账户（同时删除其所有邮件）
./scripts/delete_account.sh alice
```

用户名规则：小写字母、数字、`.`、`-`，1-64 字符。密码至少 8 字符。

## 邮件存储与清理

- 格式：Maildir，路径 `/var/mail/users/<username>/Maildir/{cur,new,tmp}/`
- **所有账户共享 5GB 上限**，不设单账户配额
- cron 每 10 分钟检查总占用，超过 5GB 时按邮件 mtime 从老到新**全局跨账户**删除，直到降到 5GB 以下
- 清理日志：`/var/log/mail-cleaner.log`

## K-9 Mail 客户端配置

**IMAP（收信）**

| 项目 | 值 |
|------|-----|
| 服务器 | `mail.example.com` |
| 端口 | 993 |
| 安全 | SSL/TLS |
| 用户名 | `alice@example.com` |
| 密码 | 账户密码 |

**SMTP（发信）**

| 项目 | 值 |
|------|-----|
| 服务器 | `mail.example.com` |
| 端口 | 465 |
| 安全 | SSL/TLS |
| 用户名 | `alice@example.com` |
| 密码 | 账户密码 |

端口 587（STARTTLS）也可用。POP3 用 995 端口，SSL/TLS。

K-9 Mail 操作：添加账户 → 输入邮箱地址和密码 → 选"手动配置" → 选 IMAP → 填上面的参数 → 填 SMTP 参数 → 完成。

## 验证

```bash
# 部署验证（检查服务、端口、配置、证书、内存）
./scripts/verify_deployment.sh

# 端到端功能验证清单
cat scripts/TEST-CHECKLIST.md
```

## 故障排查

```bash
# 服务状态
systemctl status opensmtpd dovecot opendkim

# 实时日志
journalctl -u opensmtpd -f
journalctl -u dovecot -f
journalctl -u opendkim -f

# 清理日志
tail -f /var/log/mail-cleaner.log

# 端口监听
ss -tlnp | grep -E ':(25|465|587|993|995)'

# 证书有效期
openssl x509 -in /etc/letsencrypt/live/mail.example.com/fullchain.pem -dates -noout

# 测试 SMTP 发信（需要 swaks）
swaks --to target@gmail.com --from alice@example.com \
      --server mail.example.com --port 465 --tls \
      --auth PLAIN --auth-user alice@example.com --auth-password MyPassword123
```

## 项目结构

```
├── install.sh                 # 一键部署
├── config/                    # 配置模板（{{占位符}} 由 generate_config.sh 替换）
│   ├── opensmtpd.conf.tmpl
│   ├── dovecot/               # Dovecot 主配置 + conf.d/
│   ├── opendkim.conf.tmpl
│   ├── KeyTable.tmpl
│   ├── SigningTable.tmpl
│   └── cron-clean.tmpl
├── scripts/
│   ├── generate_config.sh     # 配置生成
│   ├── create_account.sh      # 创建账户
│   ├── delete_account.sh      # 删除账户
│   ├── change_password.sh     # 改密码
│   ├── list_accounts.sh       # 列出账户
│   ├── clean_maildir.sh       # FIFO 清理（cron 每 10 分钟）
│   ├── verify_deployment.sh   # 部署验证
│   └── TEST-CHECKLIST.md      # 端到端测试清单
├── acme/
│   └── deploy-hook.sh         # 证书续期后重载服务
└── README.md
```
