# KSPlayer 重构计划 - 三层架构 + 功能分包

## 一、当前结构分析

### 现有目录结构
```
Sources/KSPlayer/
├── Audio/                    # 音频相关 UI
├── AVPlayer/                 # AVPlayer 实现
├── Core/                     # 核心工具类（混放）
├── Logging/                  # 日志工具
├── MEPlayer/                 # FFmpeg 解码实现（核心逻辑与 UI 混杂）
├── Metal/                    # Metal 渲染（核心逻辑）
├── Subtitle/                 # 字幕解析（核心逻辑）
├── SwiftUI/                  # SwiftUI 视图
└── Video/                    # 视频相关 UI
```

### 核心问题
1. **MEPlayer/** - 核心播放逻辑与 UI 混杂，违反单一职责
2. **Metal/** - 渲染逻辑与业务耦合，难以复用
3. **Audio/**、**Video/** - UI 层直接依赖底层实现
4. **无 Repository 层** - 数据源直接在 ViewModel/View 中处理
5. **无 UseCase 层** - 业务逻辑散落在各处

---

## 二、目标架构设计

### 2.1 新目录结构
```
Sources/KSPlayer/
├── App/                      # 应用组装层（仅作为壳）
│   ├── AppDelegate.swift
│   └── AppRouter.swift
│
├── Core/                     # 核心公共能力（无业务逻辑）
│   ├── DependencyContainer.swift     # DI 容器
│   ├── KSRouter.swift               # 路由接口
│   ├── EventBus.swift               # 事件总线
│   ├── FileSystem/                   # 文件系统封装
│   ├── Network/                      # 网络层封装
│   ├── Analytics/                    # 统计分析
│   └── Shared/                       # 共享工具
│       ├── Extensions/
│       ├── Constants/
│       └── Utils/
│
├── Feature/                 # 功能模块（垂直切割）
│   ├── Player/                        # 播放器核心
│   │   ├── Data/                      # Data Layer
│   │   │   ├── Repository/
│   │   │   │   ├── MediaRepository.swift
│   │   │   │   ├── CacheRepository.swift
│   │   │   │   └── SubtitleRepository.swift
│   │   │   ├── DataSource/
│   │   │   │   ├── FFmpegDataSource.swift
│   │   │   │   ├── AVPlayerDataSource.swift
│   │   │   │   └── LocalFileDataSource.swift
│   │   │   └── Model/
│   │   │       ├── MediaItem.swift
│   │   │       ├── PlaybackState.swift
│   │   │       └── SubtitleItem.swift
│   │   ├── Domain/                    # Domain Layer
│   │   │   ├── UseCase/
│   │   │   │   ├── LoadMediaUseCase.swift
│   │   │   │   ├── PlayUseCase.swift
│   │   │   │   ├── SeekUseCase.swift
│   │   │   │   ├── CacheUseCase.swift
│   │   │   │   └── SubtitleUseCase.swift
│   │   │   ├── Entity/
│   │   │   │   └── VideoTrack.swift
│   │   │   └── RepositoryProtocol.swift
│   │   └── Presentation/             # Presentation Layer
│   │       ├── ViewModel/
│   │       │   └── PlayerViewModel.swift
│   │       ├── View/
│   │       │   ├── PlayerView.swift
│   │       │   ├── ControlsView.swift
│   │       │   └── ProgressView.swift
│   │       ├── Coordinator/
│   │       │   └── PlayerCoordinator.swift
│   │       └── State/
│   │           └── PlayerState.swift
│   │
│   ├── Settings/                     # 设置
│   │   ├── Data/
│   │   ├── Domain/
│   │   │   └── UseCase/
│   │   └── Presentation/
│   │
│   ├── Subtitle/                     # 字幕
│   │   ├── Data/
│   │   ├── Domain/
│   │   └── Presentation/
│   │
│   ├── Cache/                        # 缓存
│   │   ├── Data/
│   │   ├── Domain/
│   │   └── Presentation/
│   │
│   └── Download/                     # 下载
│       ├── Data/
│       ├── Domain/
│       └── Presentation/
│
└── Infrastructure/          # 基础设施层
    ├── Rendering/                    # 渲染引擎
    │   ├── Metal/
    │   │   ├── MetalRenderer.swift
    │   │   ├── MetalShaders.metal
    │   │   └── PixelBuffer.swift
    │   ├── AVFoundation/
    │   │   └── AVPlayerRenderer.swift
    │   └── RenderProtocol.swift
    ├── Decoding/                      # 解码引擎
    │   ├── FFmpeg/
    │   │   ├── FFmpegDecoder.swift
    │   │   ├── FFmpegAudioDecoder.swift
    │   │   ├── FFmpegVideoDecoder.swift
    │   │   └── Hardware/
    │   │       ├── VideoToolboxDecoder.swift
    │   │       └── AudioToolboxDecoder.swift
    │   └── Decodable.swift
    ├── Audio/                         # 音频处理
    │   ├── AudioEngine/
    │   ├── AudioQueue/
    │   └── AudioProtocol.swift
    └── ThirdParty/                    # 第三方适配
        └── FFmpegKitAdapter.swift
```

### 2.2 三层架构职责

#### Data Layer
```swift
// RepositoryProtocol - 抽象接口
protocol MediaRepositoryProtocol {
    func fetchMedia(url: URL) async throws -> MediaItem
    func cacheMedia(_ item: MediaItem) async throws
    func getCachedMedia(url: URL) async -> MediaItem?
}

// Repository - 具体实现
class MediaRepository: MediaRepositoryProtocol {
    private let dataSource: MediaDataSourceProtocol
    private let cacheDataSource: CacheDataSourceProtocol

    func fetchMedia(url: URL) async throws -> MediaItem {
        // 1. 先查缓存
        if let cached = try? await cacheDataSource.get(url: url) {
            return cached
        }
        // 2. 从数据源获取
        let item = try await dataSource.fetch(url: url)
        // 3. 写入缓存
        try? await cacheDataSource.set(item, for: url)
        return item
    }
}

// DataSource - 数据源接口
protocol MediaDataSourceProtocol {
    func fetch(url: URL) async throws -> MediaItem
}

class FFmpegDataSource: MediaDataSourceProtocol {
    func fetch(url: URL) async throws -> MediaItem {
        // FFmpeg 解析逻辑
    }
}
```

#### Domain Layer
```swift
// UseCase - 业务逻辑（纯函数，无 UI 依赖）
class LoadMediaUseCase {
    private let repository: MediaRepositoryProtocol
    private let logger: LoggerProtocol

    func execute(url: URL) async throws -> MediaItem {
        // 业务逻辑：加载媒体、验证、错误处理
        let startTime = Date()

        let item = try await repository.fetchMedia(url: url)

        let loadTime = Date().timeIntervalSince(startTime)
        if loadTime > 2.0 {
            logger.warn("Media load took \(loadTime)s")
        }

        return item
    }
}

// Entity - 领域模型（无框架依赖）
struct MediaItem: Identifiable, Equatable {
    let id: String
    let url: URL
    let duration: TimeInterval
    let title: String?
    let thumbnail: URL?

    // 依赖倒置：转换为 ViewModel 所需的模型
    func toViewModel() -> MediaItemViewModel {
        MediaItemViewModel(
            id: id,
            title: title ?? url.lastPathComponent,
            duration: formatDuration(duration)
        )
    }
}
```

#### Presentation Layer
```swift
// ViewModel - 状态管理（UI 相关）
@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var state: PlayerState = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var error: PlayerError?

    private let loadUseCase: LoadMediaUseCase
    private let playUseCase: PlayUseCase

    func load(url: URL) async {
        state = .loading

        do {
            let item = try await loadUseCase.execute(url: url)
            state = .loaded(item)
        } catch {
            state = .error(error)
            self.error = PlayerError.from(error)
        }
    }
}

// State - UI 状态（纯数据）
enum PlayerState: Equatable {
    case idle
    case loading(progress: Double)
    case loaded(MediaItem)
    case playing
    case paused
    case error(PlayerError)
}

// View - SwiftUI 视图
struct PlayerView: View {
    @StateObject private var viewModel: PlayerViewModel

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .idle:
                IdleView(onLoad: viewModel.load)
            case .loading(let progress):
                LoadingView(progress: progress)
            case .loaded(let item):
                MediaItemView(item: item)
            case .playing:
                PlayingView()
            case .paused:
                PausedView()
            case .error(let error):
                ErrorView(error: error, onRetry: viewModel.retry)
            }
        }
    }
}
```

---

## 三、功能模块划分

### 3.1 Feature 模块清单

| 模块 | 职责 | Data | Domain | Presentation |
|------|------|------|--------|--------------|
| Player | 核心播放 | MediaRepo, CacheRepo | LoadMedia, Play, Seek, Subtitle | PlayerViewModel, PlayerView |
| Settings | 播放器设置 | SettingsRepo | UpdateSettings, ResetSettings | SettingsViewModel, SettingsView |
| Subtitle | 字幕管理 | SubtitleRepo, LocalFileRepo | LoadSubtitle, SearchSubtitle, ToggleSubtitle | SubtitleViewModel, SubtitleView |
| Cache | 缓存管理 | DiskCacheRepo, MemoryCacheRepo | GetCacheSize, ClearCache, PreloadCache | CacheViewModel, CacheView |
| Download | 下载管理 | DownloadRepo, NetworkMonitor | StartDownload, PauseDownload, CancelDownload | DownloadViewModel, DownloadView |
| History | 播放历史 | HistoryRepo | GetHistory, ClearHistory, AddToHistory | HistoryViewModel, HistoryView |

### 3.2 依赖倒置示例

```swift
// Core/Interfaces/PlayerService.swift
protocol PlayerServiceProtocol {
    func play(url: URL)
    func pause()
    func seek(to time: TimeInterval)
    var isPlaying: Bool { get }
}

// Infrastructure/Rendering/AVFoundation/AVPlayerService.swift
class AVPlayerService: PlayerServiceProtocol {
    private let player: AVPlayer

    func play(url: URL) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()
    }
}

// Infrastructure/Rendering/FFmpeg/FFmpegPlayerService.swift
class FFmpegPlayerService: PlayerServiceProtocol {
    private let player: FFmpegPlayer

    func play(url: URL) {
        player.open(url: url)
        player.play()
    }
}

// Feature/Player/Domain/UseCase/PlayUseCase.swift
class PlayUseCase {
    private let playerService: PlayerServiceProtocol  // 依赖接口

    func execute(url: URL) {
        playerService.play(url: url)
    }
}

// Core/DependencyContainer.swift
final class DependencyContainer {
    static let shared = DependencyContainer()

    private init() {}

    // 根据配置返回具体实现
    func makePlayerService() -> PlayerServiceProtocol {
        switch KSOptions.playerType {
        case .avPlayer:
            return AVPlayerService()
        case .ffmpeg:
            return FFmpegPlayerService()
        }
    }
}
```

---

## 四、编码规范实施

### 4.1 命名规范

```swift
// ❌ 不推荐
func getData() -> Data?               // 不清晰
var flag: Bool = false               // 魔法值
let MAX_RETRY = 3                    // 魔法值

// ✅ 推荐
func fetchUserData(userId: String) async throws -> UserData
var isLoading: Bool = false
let maximumRetryCount = 3

// 类名用名词
class UserRepository {}
class MediaLoader {}
class CacheManager {}

// 函数用动宾结构
func fetchUser() -> User
func loadMedia() -> MediaItem
func clearCache() -> Void
func validateToken() -> Bool

// 布尔值用 is/has 前缀
var isLoading: Bool
var hasError: Bool
var canPlay: Bool
var shouldRetry: Bool
```

### 4.2 函数精简

```swift
// ❌ 不推荐：太长，嵌套深
func processUserData(userId: String, completion: @escaping (Result<User, Error>) -> Void) {
    guard !userId.isEmpty else {
        completion(.failure(ValidationError.emptyUserId))
        return
    }
    database.fetchUser(id: userId) { result in
        switch result {
        case .success(let user):
            if user.isPremium {
                self.fetchPremiumFeatures(user: user) { premiumResult in
                    switch premiumResult {
                    case .success(let features):
                        completion(.success(user.with(features: features)))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            } else {
                completion(.success(user))
            }
        case .failure(let error):
            completion(.failure(error))
        }
    }
}

// ✅ 推荐：卫语句 + 单一职责
func processUserData(userId: String) async throws -> User {
    guard !userId.isEmpty else {
        throw ValidationError.emptyUserId
    }

    let user = try await fetchUser(id: userId)

    guard user.isPremium else {
        return user
    }

    let features = try await fetchPremiumFeatures(user: user)
    return user.with(features: features)
}
```

### 4.3 注释规范

```swift
// ❌ 不推荐：复读机式注释
// Get user data from database
func getUser() -> User {
    return database.getUser()
}

// ✅ 推荐：只写 Why
// 优先从缓存读取以减少数据库查询（数据库查询在弱网环境下可能超时）
func getUser() -> User {
    return cache.get() ?? database.getUser()
}

// 临时方案或反常规设计必须注释
// TODO: 临时硬编码，等待后端 API v2 支持动态获取
let maxConcurrentDownloads = 3

// 临时绕过已知问题
// Workaround: iOS 15 以下版本 AVPlayer 不支持 HDR，降级使用软件解码
if #available(iOS 15, *) {
    useHardwareDecoder = true
} else {
    useHardwareDecoder = false
}
```

---

## 五、性能优化方案

### 5.1 启动性能优化（目标 < 1.5s）

```swift
// 1. 延迟初始化
class PlayerViewModel {
    // ❌ 不推荐：初始化时就加载
    private let repository = MediaRepository()

    // ✅ 推荐：懒加载
    private lazy var repository: MediaRepositoryProtocol = {
        DependencyContainer.shared.makeMediaRepository()
    }()
}

// 2. 预加载关键资源
class Preloader {
    // 在 AppDelegate didFinishLaunching 时启动
    static func preloadCriticalResources() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await FFmpegKit.preload() }
            group.addTask { await ShaderCache.warmUp() }
            group.addTask { await PermissionChecker.checkAvailability() }
        }
    }
}

// 3. 移除强制闪屏页
// AppDelegate.swift
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // ❌ 不推荐
    // window.rootViewController = SplashViewController()

    // ✅ 推荐：直接进入主界面
    window.rootViewController = MainTabBarController()

    // 异步预加载
    Task {
        await Preloader.preloadCriticalResources()
    }

    return true
}
```

### 5.2 即时反馈与进度显示

```swift
// UI 反馈
struct PlayerControlsView: View {
    var body: some View {
        Button(action: { play() }) {
            Image(systemName: "play.fill")
                .foregroundStyle(.blue)
        }
        .buttonStyle(.ripple)        // 触感/波纹反馈
        .disabled(isPlaying)
    }
}

// 超时显示进度
@MainActor
class PlayerViewModel: ObservableObject {
    func load(url: URL) async {
        state = .loading(progress: 0)

        // 耗时 > 200ms 显示进度
        async let loadTask: MediaItem? = Task {
            try? await loadUseCase.execute(url: url)
        }.value

        async let timeout = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            return true
        }.value

        let (item, didTimeout) = await (loadTask, timeout)

        if didTimeout && item == nil {
            state = .loading(progress: 0)  // 显示加载进度
        }

        guard let item = item else {
            state = .error(PlayerError.loadFailed)
            return
        }

        state = .loaded(item)
    }
}
```

### 5.3 弱网容错

```swift
// 本地缓存优先
class MediaRepository {
    func fetchMedia(url: URL) async throws -> MediaItem {
        // 1. 先读本地缓存
        if let cached = try? await cacheDataSource.get(url: url) {
            return cached
        }

        // 2. 网络请求（带超时）
        do {
            let item = try await networkDataSource.fetch(url: url)
                .timeout(10, scheduler: DispatchQueue.main)

            // 3. 写入缓存
            try? await cacheDataSource.set(item, for: url)
            return item
        } catch {
            // 4. 网络失败，返回上次缓存（如果存在）
            if let lastCached = try? await cacheDataSource.getLast(url: url) {
                return lastCached
            }
            throw PlayerError.networkFailed
        }
    }
}

// 错误占位图
struct ErrorPlaceholderView: View {
    let error: PlayerError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text(error.message)
                .multilineTextAlignment(.center)

            Button(action: onRetry) {
                Text("重试")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}
```

---

## 六、隐私合规

```swift
// 场景化权限申请
struct PermissionRequestView: View {
    var body: some View {
        VStack {
            Text("需要定位权限")
                .font(.title2)

            Text("用于根据您的位置推荐附近的餐厅")
                .foregroundColor(.gray)

            HStack {
                Button("取消") {
                    // 拒绝后核心功能依然可用
                    denyLocation()
                }
                .buttonStyle(.bordered)

                Button("允许") {
                    requestLocation()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
```

---

## 七、自动化规范

### 7.1 Pre-commit Hook

```bash
# .git/hooks/pre-commit
#!/bin/bash

# Swift 格式化
swift-format --in-place --recursive Sources/

# SwiftLint 检查
swiftlint lint --strict

# 运行测试
swift test

exit 0
```

### 7.2 Git 配置

```bash
# 安装 SwiftFormat
brew install swift-format

# 安装 SwiftLint
brew install swiftlint

# 启用 pre-commit
chmod +x .git/hooks/pre-commit
```

### 7.3 CI/CD 集成

```yaml
# .github/workflows/lint.yml
name: Lint

on: [push, pull_request]

jobs:
  swiftlint:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install SwiftLint
        run: brew install swiftlint
      - name: Run SwiftLint
        run: swiftlint lint --strict

  swift-format:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install SwiftFormat
        run: brew install swift-format
      - name: Check format
        run: swift-format --lint --recursive Sources/
```

---

## 八、重构实施步骤

### Phase 1: 基础设施（Week 1-2）
- [ ] 创建新的目录结构
- [ ] 实现依赖注入容器
- [ ] 实现路由系统
- [ ] 实现事件总线

### Phase 2: 数据层迁移（Week 2-3）
- [ ] 定义 Repository 协议
- [ ] 实现 MediaRepository
- [ ] 实现 CacheRepository
- [ ] 实现 SubtitleRepository
- [ ] 迁移 FFmpeg/Audio/Metal 到 Infrastructure

### Phase 3: 领域层迁移（Week 3-4）
- [ ] 实现 LoadMediaUseCase
- [ ] 实现 PlayUseCase
- [ ] 实现 SeekUseCase
- [ ] 实现 CacheUseCase
- [ ] 实现 SubtitleUseCase

### Phase 4: 表现层重构（Week 4-5）
- [ ] 实现 PlayerViewModel
- [ ] 实现新的 SwiftUI 视图
- [ ] 迁移现有视图到新架构
- [ ] 实现 Coordinator

### Phase 5: 性能优化（Week 5-6）
- [ ] 优化启动性能
- [ ] 实现即时反馈
- [ ] 实现弱网容错
- [ ] 实现缓存策略

### Phase 6: 测试与发布（Week 6-7）
- [ ] 单元测试
- [ ] 集成测试
- [ ] 性能测试
- [ ] Code Review
- [ ] 发布

---

## 九、风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 重构范围大 | 可能引入新 bug | 分阶段重构，每阶段测试 |
| 性能下降 | 用户体验变差 | 持续性能监控，基准测试 |
| 兼容性问题 | 老版本无法使用 | 保留旧接口，渐进式迁移 |
| 开发周期长 | 功能交付延迟 | 并行开发，双轨运行 |
| 团队学习曲线 | 团队不熟悉新架构 | 培训、代码评审、文档 |

---

## 十、成功指标

### 10.1 技术指标
- 启动时间 < 1.5s
- 编译时间 < 2min
- 代码覆盖率 > 80%
- SwiftLint 警告 = 0

### 10.2 质量指标
- 每个函数 < 20 行
- 每个类 < 300 行
- 圈复杂度 < 10
- 循环依赖 = 0

### 10.3 业务指标
- 崩溃率 < 0.1%
- 加载成功率 > 99%
- 用户满意度 > 4.5/5

---

**文档版本**: 1.0
**最后更新**: 2026-08-28
**负责人**: Architecture Team