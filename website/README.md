# 拾影官网

正式地址：https://framelet.slnt.dev

中文静态官网，由 Orca 中的 AGY 制作，主代理验收、集成与发布。源码位于此目录；仅 public allowlist 被复制到 `dist/website`，内部交接与部署文件不上传。

## 本地预览

```sh
python3 website/prepare-deploy.py
python3 -m http.server 8886 --bind 127.0.0.1 --directory dist/website
```

`release.json` 集中保存版本、下载地址、SHA-256 与公证状态。更新发布时，先完成签名、公证、附加票据，再填写元数据。准备脚本会校验安装包与元数据的 SHA-256 一致；首页只有 available 和 notarized 同时为 true 才启用下载。

## 部署

```sh
python3 website/prepare-deploy.py
wrangler deploy --config website/wrangler.jsonc
```

使用已有 Cloudflare 登录；独立 Worker `framelet-website` 绑定 `framelet.slnt.dev`，不会部署或覆盖主域 `slnt.dev` 的 Worker。安装包放在项目 dist/ 下，不提交二进制进 Git。

## 验证

本地资源存在性、JS 语法、Chrome 桌面与 375px 移动视口、两种下载状态、演示 Tab、下载文件 SHA-256 已检查。全量实际发布记录见 `../docs/发布检查.md`。`HANDOFF.md` 保留 AGY 原始交接信息，不代表当前发布状态。
