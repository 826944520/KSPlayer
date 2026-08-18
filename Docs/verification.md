# KSPlayer 真机验证清单

分支 `ios26-ffmpeg-upgrade` 的改动已全部通过 GitHub Actions CI（编译验证）。
由于本环境无本地 Mac，**播放行为的正确性只能通过真机实测确认**。本文档是计划验证章节的真机执行清单。

## 1. 获取并侧载 demo app

1. 打开 [GitHub Actions](https://github.com/826944520/KSPlayer/actions)，选择最近一次绿色 run。
2. 在 **Build unsigned IPA (demo app)** job 的 Artifacts 中下载 `DemoApp-unsigned.ipa`。
3. 用免费 Apple ID + Xcode 对 IPA 自签，侧载到 iPhone / iPad（推荐 iPhone，demo 为 iPhone-only）。

## 2. 每项改动的真机检查点

### Stage 1 — 性能管线（无法用 CI 验证，优先级最高）

| 项 | 验证方法 | 预期 |
|---|---|---|
| 1.1 MetalRender 三缓冲 | 播放 `.vr` / `.vrBox` 全景视频，快速拖动进度条、切换画面 | 无画面撕裂/黑帧；播放中 UI 手势不卡顿（不再被 GPU 阻塞）；`displayFPS` 稳定接近源帧率 |
| 1.3 cache 协议 | 设置页打开「本地缓存」后播放一个 MP4，播放中途断网再切回 | 已下载部分仍可播；播放完成后退出重进同一 URL 秒开（命中磁盘缓存） |
| 1.5 A/V 时钟 | 播放视频后反复 seek（精确/非精确、正向/反向） | 无音画不同步；seek 后 1 秒内声音画面对齐；连续 seek 无卡死 |
| 1.6 IO buffer | 设置页打开「低延迟音频」后播放 | 声音跟手，无卡顿/爆音；播放正常 |

### Stage 2 — 播放器 UI/UX

| 项 | 验证方法 | 预期 |
|---|---|---|
| 2.1 双击分区 seek | 双击画面左/中/右三区 | 左 1/3 −10s、右 1/3 +10s、中间切播放/暂停；提示浮层显示 |
| 2.2 缓冲条 + 章节 | 播放流媒体，观察进度条 | 白条显示已缓冲范围；有章节的文件（MP4/TS 含章节）进度条上有刻度 |
| 2.3 缩略图预览 | 拖动进度条 | 出现约 160×90 的当前帧缩略图 + 时间标签；松手隐藏 |
| 2.4 错误/重试 | 播放一个失效 URL | 显示错误卡片（标题+详情+重试按钮），点重试后恢复 |
| 2.5a 音量滑块 | 横屏 | 工具栏出现音量滑块，拖动改变系统音量且无系统 HUD |
| 2.5b 设置齿轮 | 点齿轮 | 弹出菜单：双击 seek / 硬解 / 缩略图预览 / 双指缩放 / 字幕样式 / 章节列表 |
| 2.5c 旋转/镜像/缩放 | 横屏点旋转/镜像；双指捏合（plane 模式） | 画面 90° 循环旋转、水平镜像；双指缩放 1.0–4.0 |
| 2.6 PiP | 播放时点 PiP 按钮 | 按钮在真机出现，点按进入画中画（模拟器不支持，属预期） |
| 2.7 字幕样式/章节/AirPlay | 播放含字幕的片源；有 AirPlay 设备时 | 字幕大小/颜色生效；章节列表点击跳转；AirPlay 按钮常显 |

### Stage 3 — Demo app

| 项 | 验证方法 | 预期 |
|---|---|---|
| 首页历史 | 播放几个视频后回到首页 | 最近观看列表按时间倒序、可侧滑删除/拖动排序、点击续播 |
| 本地导入 | 选本地多文件 | 自动成为播放列表，底栏上一集/下一集可切换 |
| 播放列表导航 | 播放列表中点下一集/上一集 | `KSPlayerLayer.next()/previous()` 正常切换；`.playedToTheEnd` 自动续播 |
| 调试浮层 | 播放时打开 debug sheet | `.vr` 路径显示 FFmpeg DynamicInfo（FPS/丢帧/码率等）；`.plane` 路径显示 AVPlayer 指标 |
| 双击提示 | 首次进入播放页 | 一次性浮层「双击左侧/右侧快退/快进 10 秒」，关闭后不再出现 |

## 3. 已知约束（非缺陷）

- **`enableZoomGestures` 默认关**（库层），demo 设置页可开启。
- **`cache` 默认关**，需在设置页手动打开；仅在运行时探测到 FFmpeg `cache:` 协议且为 progressive 文件（非 `.m3u8`）时生效。
- **PiP 按钮**在模拟器隐藏（`isPictureInPictureSupported()` 返回 false），真机显示。
- **HDR tone-mapping（1.7）按计划延期**：HDR→SDR 调色 pass 设计为 `KSOptions.enableToneMapping = false`（默认关）的新 Metal fragment pass，未在本分支实现。
- 播放器的自动隐藏遮罩（2.5d）已达现有 `isMaskShow` 淡入淡出标准，未新增独立配置。

## 4. 完成标准

- 上表 2 中所有检查点通过。
- 若某项失败：在真机复现、抓取 `Console` 日志（FFmpeg `av_log` 输出在 KSPlayer 日志中），按 Stage 提交粒度回退对应提交后再排查。
