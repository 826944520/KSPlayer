# KSPlayer 构建失败分析

**Run:** #81 (run_id `33138437150`) · **Job:** `98743636942` (Build iOS Simulator + FFmpeg version gate)
**Branch:** `ios26-ffmpeg-upgrade` · **SHA:** `112c21a` · **结论:** failure

---

## 1. 错误类型统计

| 类型 | 数量 | 说明 |
|------|------|------|
| 编译错误（Swift 源码错误） | 0 | 编译器尚未执行到类型检查就被构建系统中止 |
| 链接错误 | 0 | 未进入链接阶段 |
| 构建系统错误（其他） | 1 | SwiftPM「multiple producers」构建图冲突（**本次失败的直接原因**） |
| 潜在类型重声明错误（源码分析发现） | 2 | 修复构建系统错误后才会暴露的 `invalid redeclaration` |

> 关键结论：**日志中的唯一 error 不是源码编译错误，而是 SwiftPM 构建图冲突**。FFmpeg 版本门禁（step 5）已通过：avcodec=60、avformat=60、avfilter=9，均符合预期。

---

## 2. 详细错误列表（按文件分组）

### 🔴 错误 #1 —— 「multiple producers」构建图冲突（阻断性，日志中唯一错误）

- **错误消息（日志原文）：**
  ```
  error: couldn't build /Users/runner/work/KSPlayer/KSPlayer/.build/arm64-apple-macosx/debug/KSPlayer.build/PlayerView.swift.o
  because of multiple producers: Compiling Swift Module 'KSPlayer' (71 sources), Compiling Swift Module 'KSPlayer' (71 sources)
  ```
- **错误类型：** SwiftPM / llbuild 构建图冲突（其他错误，非编译/链接错误）
- **直接触发文件：** `PlayerView.swift.o`（KSPlayer 模块中**唯一**重名的源文件）
- **根因：** KSPlayer target 内存在**两个同名文件 `PlayerView.swift`**：
  - `Sources/KSPlayer/Core/PlayerView.swift`（既有：`open class PlayerView: UIView`）
  - `Sources/KSPlayer/Feature/Player/Presentation/View/PlayerView.swift`（重构新增：`struct PlayerView: View`）
  SwiftPM 在交叉编译下将对象文件路径扁平化为 basename，两个同名源文件映射到同一个 `PlayerView.swift.o`，导致构建图产生「multiple producers」冲突。
- **修复建议：** 将 `Feature/Player/Presentation/View/PlayerView.swift` 重命名为唯一文件名（例如 `FeaturePlayerView.swift`），并把其中的类型一并改名（见错误 #2）。

### 🟠 错误 #2 —— `PlayerView` 类型重声明（修复 #1 后暴露）

- **错误类型：** 编译错误（`invalid redeclaration of 'PlayerView'`）
- **冲突位置：**
  - `Sources/KSPlayer/Core/PlayerView.swift:40` — `open class PlayerView: UIView, KSPlayerLayerDelegate, KSSliderDelegate`
  - `Sources/KSPlayer/Feature/Player/Presentation/View/PlayerView.swift:11` — `struct PlayerView: View`
- **修复建议：** 将 SwiftUI 侧的 `struct PlayerView` 重命名为不与 UIKit 侧冲突的名称（如 `FeaturePlayerView` / `PlayerFeatureView` / `KSPlayerRootView`），并同步更新引用它的代码（`PlayerViewModel.swift` 及 Demo/App 入口）。

### 🟠 错误 #3 —— `LogLevel` 类型重声明（修复 #1 后暴露）

- **错误类型：** 编译错误（`invalid redeclaration of 'LogLevel'`）
- **冲突位置：**
  - `Sources/KSPlayer/AVPlayer/KSOptions.swift:556` — `public enum LogLevel: Int32, CustomStringConvertible`（FFmpeg 风格日志级别，既有）
  - `Sources/KSPlayer/Core/Logger.swift:13` — `enum LogLevel: Int, CaseIterable`（重构新增的结构化日志级别）
- **修复建议：** 将 `Logger.swift` 中的 `LogLevel` 重命名为 `LoggerLevel`（或直接复用/映射既有的 `KSOptions.LogLevel`），避免与 FFmpeg 日志级别冲突。

---

## 3. 优先级排序

| 优先级 | 问题 | 影响 | 修复动作 |
|--------|------|------|----------|
| **P0（阻断）** | `PlayerView.swift` 文件名重复 → 「multiple producers」 | 构建图直接报错，编译无法开始 | 重命名 `Feature/.../View/PlayerView.swift` |
| **P1** | `PlayerView` 类型重声明 | P0 修复后立即编译失败 | 重命名 `struct PlayerView`（与 P0 同一文件一并处理） |
| **P1** | `LogLevel` 类型重声明 | 同上 | 重命名 `Logger.swift` 中的 `enum LogLevel` |

> 三个问题均由重构提交 `586fd78`（"refactor: 实现三层架构和功能分包重构"）引入：新增的 `Feature/.../PlayerView.swift` 与 `Core/Logger.swift` 分别撞上了既有的文件名/类型名。

---

## 附：证据链（为什么是重构引入，而非交叉编译命令）

- 同一 `build.yml` 的交叉编译命令（`swift build --sdk iphonesimulator -Xswiftc -target arm64-apple-ios26.0-simulator`）自 `a51178e` 起未变，且在 run #77（`f74fe23`）**构建成功**。
- 运行历史：
  | Run | SHA | 结果 |
  |-----|-----|------|
  | #77 | f74fe23 | ✅ success |
  | #79 | 586fd78（重构） | ❌ failure — multiple producers (70 sources) |
  | #80 | c35cf69（"修复编译错误"） | ❌ failure — multiple producers (71 sources) |
  | #81 | 112c21a（HEAD） | ❌ failure — multiple producers (71 sources) |
- 全 target 内重名 basename 扫描结果：**仅 `PlayerView.swift` 重复**，与日志报错的 `PlayerView.swift.o` 完全对应。
- 全 target 内类型重名扫描结果：`PlayerView`（class vs struct）、`LogLevel`（Int32 vs Int）两处重复，均由重构引入。
- 日志中的 `sdl2` warning 与 `Node 20 deprecation` warning 均为无害提示，与失败无关；日志中 `.build/arm64-apple-macosx` 路径为交叉编译的既有表现，非根因。
