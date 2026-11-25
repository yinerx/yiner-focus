# 银耳专注

只在这台 Mac 上运行的菜单栏专注计时。专注和休息倒计时、进行中屏蔽指定应用和网站、本机历史和统计、把已完成的专注写入系统日历。没有账号，没有服务器，没有同步。

需求以 `docs/spec.md` 为准。界面、图标和拦截页都是新做的。

## 环境

- MacBook Air（Apple Silicon），macOS 26 或更新。银耳这台是 macOS 27。
- Xcode，能编译 macOS 26。
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)，用来生成工程。不要手改 `.xcodeproj`，那个文件没有放进仓库。

本仓库里的计时、屏蔽规则、统计、CSV 和日历文案是一个只依赖 Foundation 的 Swift 包，可以在没有 Xcode 的机器上测试。菜单栏、浏览器自动化、隐藏应用、日历、通知、登录项和小组件在 `App/` 里，必须在 Mac 上编译。

## 在 Mac 上编译运行

1. 安装 XcodeGen：

```bash
brew install xcodegen
```

2. 打开 `App/project.yml`，把 `DEVELOPMENT_TEAM` 换成你的 Apple Development Team ID。主应用和「今日统计」小组件要签在同一个团队下，App Group `group.com.yiner.focus` 才能用。

3. 生成工程并打开：

```bash
cd App
xcodegen generate
open YinerFocus.xcodeproj
```

4. 选中 scheme `YinerFocus`，目标选「My Mac」，运行。

装好之后菜单栏会出现剩余时间或阶段，Dock 里没有图标。产物名是 `YinerFocus.app`，显示名是「银耳专注」。Bundle ID 是 `com.yiner.focus`。

第一版不上架。沙盒是关的，因为要给 Safari、Google Chrome、Arc 发 Apple Events，还要把别的应用退到后台。Hardened Runtime 是开的，并允许自动化（Apple Events）。

从 Xcode 直接跑时，登录项有时要额外批准。想开机就在，可以把应用拷到「应用程序」文件夹再打开一次。

## 权限

系统会在第一次用到时询问，不会一启动就全部弹出。

- **自动化**：第一次在专注进行中检查网站时，分别询问能否控制 Safari、Google Chrome、Arc。拒绝某一个，只是那个浏览器不拦截，屏蔽设置里会写原因。路径：系统设置 › 隐私与安全性 › 自动化。
- **通知**：打开「专注结束」或「休息结束」通知，或第一次需要提醒时询问。若拒绝，设置里会提示去系统设置 › 通知里打开。
- **日历**：只有打开「把已完成的专注写入日历」才要完整日历权限。允许后在设置里选一个日历。
- **登录项**：默认打开「登录时启动」。若系统要求批准，设置里会提示去系统设置 › 通用 › 登录项。

不需要辅助功能权限。Firefox 不支持。名字还没确认的浏览器「Cra」只在名单里占一行，不会去控制它。

## 导入原来的 CSV

设置或统计里都可以导入、导出，用的是同一套逻辑。

1. 从原来的专注应用导出 CSV。仓库里的 `docs/samples/flow-export-sample.csv` 就是这种格式：UTF-8，表头为

```text
Type,Title,Tag,Duration,Duration With Interruptions,Started,Completed,ID
```

2. 银耳专注 › 设置或统计 › 导入 CSV，选中那个文件。
3. 结果会写出新增、跳过和无法解析的行数。同一个 ID 已经在本机时会跳过，不会覆盖你后来改过的记录。文件里没有的标签会自动建一个，颜色用默认色。
4. 导出使用同样的列和顺序。已完成的专注，Type 写成 `Flow`，这样可以再导回去。休息默认不导出。时间按本机时区写成 `YYYY-MM-DD HH:MM:SS`，时长写成 `HH:MM:SS`。

样例里有一条净时长比含中断少 1 秒，两个数都会保留。

## 数据在哪里，怎么备份

全部在本机：

```text
~/Library/Application Support/YinerFocus/store.json
```

这里有会话、标签、设置、屏蔽名单，以及当前这次倒计时。没有 iCloud，也没有 CloudKit。

备份：退出应用后，把整个 `YinerFocus` 文件夹拷走。只想带走专注记录时，用设置里的导出 CSV。CSV 不含设置和屏蔽名单。

读不出来的存档不会被空文件盖掉。把坏文件移走再打开，会从空记录重新开始。

「重置全部统计」会连续确认两次，只删会话，设置、标签和名单还在，不能撤销。

今日统计小组件读的是 App Group 里的一份今日汇总，由主应用写。没配好签名里的 App Group 时，小组件显示 0，应用里的统计不受影响。

## 自动化测试

在装了 Swift 的机器上：

```bash
cd Packages/YinerFocusCore
swift test
```

验收项 A01 到 A20 都在 `Tests/YinerFocusCoreTests/AcceptanceTests.swift`。同目录的 `SupportTests.swift` 覆盖统计、标签、存档和菜单栏文案这些配套逻辑。

没有添加 GitHub Actions 的 macOS 构建，避免产生费用。要开的话需要另一次确认。

## 想改默认值

`docs/spec.md` 第 10 节那些还没拍板的项，都按文档里的默认做了，集中在：

`Packages/YinerFocusCore/Sources/YinerFocusCore/Defaults.swift`

包括应用名、Bundle ID、时长、周期、登录时启动、开始后隐藏窗口、窗口置顶、全局快捷键保持关闭、CSV 不导出休息、以及要做「今日统计」小组件。精确网址规则去掉末尾至多一个 `/` 再比较，也写在这个文件的注释里。

## 使用时要注意

- 屏蔽只在专注「进行中」生效。暂停、待开始、短休息、长休息都不拦截。
- 网站拦截会把匹配的标签整页换成应用自带的本地页面，不联网。暂停或休息之后，已经打开的拦截页不会自动变回去。
- 网页名单可以在「阻止」和「允许」之间切换，共用一份名单。应用名单只有阻止，点开后会被退到后台，进程还在。
- 普通网站规则是不区分大小写的包含匹配，不必写 `http` 或 `www`。以 `*` 开头的是精确网址。
- 可能短暂闪过原来的页面。无痕或特殊配置文件有时读不到。点返回回到被拦地址时，会再换成拦截页。
- 浏览器以外的地方，以及没选中、没授权的浏览器，拦不住。
- 删掉一条会话，不会自动删掉已经写进日历的那条事件。
- 退出应用后，屏蔽马上停止。不会去改别的专注应用的数据。
