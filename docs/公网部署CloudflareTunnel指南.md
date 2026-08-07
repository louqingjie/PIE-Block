# keil_server 公网部署指南（本机 + Cloudflare Tunnel）

目标：让 `https://build.pieblock.asia` 全球可访问。编译服务器跑在本机，通过
**Cloudflare Tunnel** 穿透到公网（免费、自动 HTTPS、无需开放端口）。

```
                 HTTPS                Cloudflare 边缘        Tunnel 隧道
  客户端 ──────▶ build.pieblock.asia ──────────────▶ cloudflared ──▶ http://127.0.0.1:8000
 (MCP/CLI)     (DNS: CNAME -> tunnel)                 (本机)          keil_server
```

全程约 20~40 分钟，一次性配置，之后本机开机即可自动提供云端编译。

## 一、域名托管到 Cloudflare（一次）

1. 注册 Cloudflare 账号：<https://dash.cloudflare.com/sign-up>
2. Dashboard → **Add a site** → 输入 `pieblock.asia` → 选 **Free** 计划
3. Cloudflare 会给出两个 **NS 服务器地址**（如 `xxx.ns.cloudflare.com`）
4. 去域名注册商后台，把域名的 **NS 记录改成 Cloudflare 给的那两个**
5. 等待几分钟到几小时，Cloudflare 显示站点 **Active** 即完成

## 二、安装 cloudflared（一次）

下载 Windows 版（选 `cloudflared-windows-amd64.exe`）：
<https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/>

重命名为 `cloudflared.exe`，放到 `C:\cloudflared\cloudflared.exe`
（下文按此路径写，可自定义）。

## 三、登录并创建隧道（一次）

```powershell
cd C:\cloudflared
.\cloudflared.exe tunnel login          # 浏览器授权，选 pieblock.asia 所在账号
.\cloudflared.exe tunnel create pieblock   # 输出 TUNNEL-UUID 并生成凭证 json
# 记下 TUNNEL-UUID；凭证文件在 C:\Users\<你>\.cloudflared\<TUNNEL-UUID>.json
```

## 四、填写配置并启动

1. 把 `keil_server/deploy/cloudflared-config.yml.example` 复制为
   `cloudflared-config.yml`，填写两处：
   - `tunnel: <TUNNEL-UUID>` → 上一步得到的 UUID
   - `credentials-file:` → 凭证 json 的完整路径

   ingress 已写好：`build.pieblock.asia` → `http://127.0.0.1:8000`，
   其余请求返回 404（关闭外网直接访问内网其它端口）。

2. 把域名解析到隧道（一次）：

```powershell
.\cloudflared.exe tunnel route dns pieblock build.pieblock.asia
```

3. 一键启动（每次开机用这个）：

```powershell
.\keil_server\deploy\start_public.ps1
```

脚本会检查 `.venv` 与 Keil → 启动 `keil_server`（监听 127.0.0.1:8000，带鉴权）→
等 2 秒启动 `cloudflared tunnel run` → 打印访问地址。

> 想开机自启 + 崩溃自动重启 + 日志监控：用 `keil_server/deploy/` 下的 NSSM 托管
> 脚本（`install_nssm.ps1` + `install_scheduled_tasks.ps1`），比 `shell:startup`
> 可靠得多，见 `keil_server/deploy/README.md`。上面的前台一键启动仅用于临时验证。

## 五、验证

```powershell
# 浏览器打开（应看到 JSON，keil.available=true）
https://build.pieblock.asia/health

# 客户端云端编译（其他机器也能用，把地址换成公网域名）
$env:PIEBLOCK_KEIL_SERVER_URL="https://build.pieblock.asia"
$env:PIEBLOCK_KEIL_API_KEY="你的密钥"
python -m keil_server.client build --kind infantry --config x.json --out-hex f.hex
```

## 六、给队员分配 key（每用户一把）

鉴权是**每个用户一把 key**（管理员 key 负责管理）。启动时用 `-ApiKeys` 播种，
之后用管理接口或 CLI 增删：

```powershell
# 列出 / 新增 / 吊销（读写同一 key 表）
python -m keil_server.keys list
python -m keil_server.keys add 张三
python -m keil_server.keys remove 张三

# 或者用 HTTP 管理接口（需要管理员 key）
#   GET    /keys               列用户
#   POST   /keys  {"user":"张三"}    新增（自动生成 key）
#   DELETE /keys/张三           吊销
```

每个队员拿自己的 key，编译记录能看出是谁；有人不配合就单独吊销他的 key，
不影响其他人。详见 `keil_server/README.md` 的「用户管理」。

## 七、安全提醒（重要）

- **必须**设 API Key（本方案脚本默认要求填写），否则公网任何人都能白嫖编译、
  看源码路径
- `GET /tasks/{id}/log` 含编译日志（可能带源码路径），日志只对持有 API Key 者开放
- 本机 24h 开机才能提供服务；关机会断网（提示队友即可）
- 免费计划约 100 请求/天有速率提示，编译服务用量小，够用

## 八、替代方案

| 方案 | 评价 |
| --- | --- |
| ngrok | 免费版域名随机、不稳定，自定义域名要付费 → 不推荐 |
| frp | 需要一台有公网 IP 的服务器当 frps → 等于云服务器方案 |
| 仅局域网 | 不穿透，直接用 `http://<本机IP>:8000` + `start_server.ps1 -HostAll`（0 成本，最快） |
