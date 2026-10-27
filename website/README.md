# 拾影官网

正式地址：https://framelet.slnt.dev

中文静态官网。源码位于此目录；仅公开页面和下载文件被复制到 `dist/website`，部署配置不会作为网站资源上传。

## 本地预览

```sh
python3 -m http.server 8886 --bind 127.0.0.1 --directory website
```

`release.json` 集中保存版本、下载地址、SHA-256 与公证状态。更新发布时，先完成签名、公证、附加票据，再填写元数据。准备脚本会校验安装包与元数据的 SHA-256 一致；首页只有 available 和 notarized 同时为 true 才启用下载。
本地直接预览源码页面时，下载文件不会自动提供；准备部署前请将 `release.json` 列出的现版和历史 DMG 放入 `dist/`。

## 部署

```sh
python3 website/prepare-deploy.py
wrangler deploy --config website/wrangler.jsonc
```

使用已有 Cloudflare 登录；独立 Worker `framelet-website` 绑定 `framelet.slnt.dev`，不会部署或覆盖主域 `slnt.dev` 的 Worker。安装包放在项目 dist/ 下，不提交二进制进 Git。

## 验证

本地资源存在性、JS 语法、桌面与移动视口、两种下载状态、演示 Tab 和下载文件 SHA-256 均应在发布时检查。
