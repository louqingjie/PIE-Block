# keil_server 公网部署指南（本机 + Cloudflare Tunnel）

目标：让 `https://build.pieblock.asia` 全球可访问，编译服务器跑在本机，
通过 **Cloudflare Tunnel** 穿透到公网（免费、自动 HTTPS、无需开放端口）。

```
                 HTTPS                Cloudflare 边缘        Tunnel 隧道
 客户端 ──────▶ build.pieblock.asia ──────────────▶ cloudflared ──▶ http://127.0.0.1:8000
 (MCP/CLI)     (DNS: CNAME -> tunnel)                 (本机)          keil_server
```

---

## 一、你需要手动做的（涉及账号/凭证，必须自己操作）

> 全程约 20~40 分钟，一次性配置，之后本机开机即可自动提供云端编译。

### 1. 把 pieblock.asia 托管到 Cloudflare（一次）
1. 注册 Cloudflare 账号：https://dash.cloudflare.com/sign-up
2. 添加站点：Dashboard → **Add a site** → 输入 `pieblock.asia` → 选 **Free** 计划
3. Cloudflare 会给你两个 **NS 服务器地址**（如 `xxx.ns.cloudflare.com`）
4. 去你买域名的注册商后台，把域名的 **NS 记录改成 Cloudflare 给的那两个**
5. 等几分钟到几小时，Cloudflare 显示站点 **Active**（域名才算归它管）

### 2. 本机安装 cloudflared（一次）
下载 Windows 版：https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/
（选 `cloudflared-windows-amd64.exe`），重命名为 `cloudflared.exe`，放到
`C:\cloudflared\cloudflared.exe`（下文按此路径写，可自定义）。

### 3. 登录并创建隧道（一次，拿到 TUNNEL-UUID）
```powershell
cd C:\cloudflared
.\cloudflared.exe tunnel login          # 会打开浏览器授权，选 pieblock.asia 那个账号
.\cloudflared.exe tunnel create pieblock   # 创建隧道，输出 TUNNEL-UUID 并生成凭证 json
# 记下 TUNNEL-UUID，凭证文件在 C:\Users\<你>\.cloudflared\<TUNNEL-UUID>.json
```

### 4. 把下面文件按提示填好后，启动
见本文件下方「三、一键启动」。

---

## 二、我准备好的文件（改好即可用）

| 文件 | 作用 |
|---|---|
| `keil_server/deploy/cloudflared-config.yml.example` | cloudflared 隧道配置模板 |
| `keil_server/deploy/start_public.ps1` | 一键启动：先起 keil_server（带 API Key），再起 cloudflared |
| 本文件 | 完整步骤说明 |

### 配置模板要点

把 `cloudflared-config.yml.example` 复制为 `cloudflared-config.yml`，填两处：
- `tunnel: <TUNNEL-UUID>` → 上一步得到的 UUID
- `credentials-file:` → 凭证 json 的完整路径

ingress 已写好：`build.pieblock.asia` → `http://127.0.0.1:8000`，
其余请求返回 404（关闭外网直接访问内网其它端口）。

### DNS 自动添加

cloudflared 配置好后，用下面命令自动把 `build.pieblock.asia` 的 CNAME 加进 Cloudflare：
```powershell
.\cloudflared.exe tunnel route dns pieblock build.pieblock.asia
```

---

## 三、一键启动（每次开机用这个）

```powershell
# 编辑 start_public.ps1 顶部变量后运行：
.\keil_server\deploy\start_public.ps1
```

它会：
1. 检查 `.venv` 与 Keil 可用
2. 启动 `keil_server`（监听 127.0.0.1:8000，带 `-ApiKey` 鉴权）
3. 等 2 秒后启动 `cloudflared tunnel run`
4. 打印访问地址 `https://build.pieblock.asia/health`

> 想开机自启：把 `start_public.ps1` 的快捷方式放进 `Win+R → shell:startup`。

---

## 四、验证

```powershell
# 浏览器打开（应看到 JSON，keil.available=true）
https://build.pieblock.asia/health

# 客户端云端编译（其他机器也能用，把地址换成公网域名）
$env:PIEBLOCK_KEIL_SERVER_URL="https://build.pieblock.asia"
$env:PIEBLOCK_KEIL_API_KEY="你的密钥"
python -m keil_server.client build --kind infantry --config x.json --out-hex f.hex
```

---

## 五、安全提醒（重要）

- **必须**设 `KEIL_API_KEY`（本方案脚本默认要求填写），否则公网任何人都能白嫖编译、看源码路径
- `GET /tasks/{id}/log` 含编译日志（可能带源码路径），日志只对持有 API Key 者开放
- 本机 24h 开机才能提供服务；关机会断网（提示队友即可）
- 免费计划 100 个请求/天左右有速率提示，编译服务用量小，够用

## 六、如果不想用 Cloudflare Tunnel

- **ngrok**：免费版域名随机、不稳定，自定义域名要付费 → 不推荐
- **frp**：需要一台有公网 IP 的服务器当 frps → 那就等于云服务器方案了
- **只给局域网队友用**：不穿透，直接用 `http://<本机IP>:8000` + `start_server.ps1 -HostAll`（0 成本，最快）
