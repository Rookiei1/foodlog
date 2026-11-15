# 食刻 FoodLog — TestFlight 发布说明

公开源码仓库：`https://github.com/Rookiei1/foodlog`，默认分支 `main`。

| 项目 | 值 |
| --- | --- |
| 应用名称 | 食刻 FoodLog（若 App Store Connect 名称占用可用 `食刻 - AI 饮食与体重记录`） |
| 桌面显示名 (`CFBundleDisplayName`) | 食刻 |
| 平台 | iOS（iPhone） |
| 主要语言 | 简体中文（`zh-Hans`） |
| Bundle ID | `com.rookiei1.foodlog` |
| App Store Connect App ID | `6835001745` |
| SKU | `foodlog-iphone-001` |
| Team ID | `NGV55K28X8` |
| 复用分发证书 ID | `WUS3HDT696`（`Rookiei1/nofap-signing` 分支 `signing-assets-v2`，只读复用） |
| Scheme | `FoodLog` |
| 营销版本 (`MARKETING_VERSION`) | `1.0.0` |
| 最新已验证 TestFlight 构建号 (`CURRENT_PROJECT_VERSION`) | `6`（已上传并通过 Apple 构建处理，已自动分发至 Internal Testers） |
| 签名目标 | 仅主应用 `FoodLog.app`（`FoodLogTests` 与 `FoodLogUITests` 不签名上传） |
| 额外 Capabilities | 无（仅使用系统基础沙盒、标准 Keychain、相机与相册权限说明） |
| 加密合规 | 不使用自有非豁免加密，`ITSAppUsesNonExemptEncryption` 为 `false` |
| 最低系统 | iOS 17.0 |
| CI 运行环境 | GitHub Actions `macos-26`（Xcode 26.6，iOS 26 SDK） |

## 工作流入口

1. **源码编译与单元测试 (`Actions → Test`)**
   - 每次推送 `main` 或手动触发时在 `macos-26` 运行：检查敏感文件、验证 Fastlane / 签名校验脚本、通过 `xcodegen` 生成 `FoodLog.xcodeproj`、在 iPhone 模拟器执行 `FoodLogTests` 单元测试并抓取首页预览截图。
2. **TestFlight 诊断、初始化与发布 (`Actions → TestFlight`)**
   - 仅限仓库所有者在 `main` 分支手动触发（`workflow_dispatch`）：
   - `diagnose`：只读检查 Apple 协议状态、Developer App ID (`com.rookiei1.foodlog`)、App Store Connect 应用记录以及私有签名库中的现有分发证书 (`WUS3HDT696`)。不创建证书、不上传。
   - `bootstrap`：在复用现有分发证书 (`readonly: true` 读取证书与私钥) 的前提下，通过 API 检查/注册 `com.rookiei1.foodlog` 的 App Store 描述文件。不新建或撤销分发证书。
   - `release`：运行单元测试、安装现有分发证书与 App Store 描述文件、手动签名归档 `FoodLog.xcarchive`、导出 `FoodLog.ipa`、执行 `ci/verify_release.py` 严格核验签名与权限项，最后上传至 App Store Connect / TestFlight 并等待 Apple 处理完成。

## 签名与仓库 Secrets 映射

公开仓库不包含任何私钥、证书或 `.mobileprovision`。证书密文存储在私有仓库 `Rookiei1/nofap-signing` 的 `signing-assets-v2` 分支，由公开仓库通过只读 Deploy Key 访问。

需在 `https://github.com/Rookiei1/foodlog/settings/secrets/actions` 配置以下 7 个 Repository Secrets（与 `NoFap` / `IELTS-iPhone` 同名同值）：

| Secret 名称 | 用途 |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect API Key ID |
| `ASC_ISSUER_ID` | App Store Connect API Issuer ID |
| `ASC_PRIVATE_KEY` | `.p8` API 私钥完整内容（由 `ci/prepare_apple_key.py` 写入 `RUNNER_TEMP` 并在任务结束时清理） |
| `MATCH_PASSWORD_NEXT` | 私有签名仓库 `signing-assets-v2` 解密口令（工作流内映射为 `MATCH_PASSWORD`） |
| `SIGNING_CERTIFICATE_ID` | 复用的现有 Apple Distribution 证书 ID（`WUS3HDT696`） |
| `SIGNING_STORE_URL` | 私有签名仓库 SSH 地址（`git@github.com:Rookiei1/nofap-signing.git`） |
| `SIGNING_DEPLOY_KEY` | 私有签名仓库只读 SSH Deploy Key 私钥 |

## 已验证运行记录（2026-11-15）

- **模拟器编译、单元测试与截图 (`Test`)**：`https://github.com/Rookiei1/foodlog/actions/runs/43673169597`（`macos-26` / Xcode 26.6，13 项 `FoodLogTests` 单元测试 0 失败，生成首页预览截图）
- **TestFlight 只读诊断 (`TestFlight → diagnose`)**：`https://github.com/Rookiei1/foodlog/actions/runs/43677669095`（核验 Bundle ID `com.rookiei1.foodlog`、App Store Connect App `6835001745` 与证书 `WUS3HDT696` 通过）
- **TestFlight 描述文件准备 (`TestFlight → bootstrap`)**：`https://github.com/Rookiei1/foodlog/actions/runs/43677823925`（基于现有证书 `WUS3HDT696` 生成并核验 `com.rookiei1.foodlog` App Store Provisioning Profile，未创建新证书）
- **TestFlight 正式签名、归档、上传与构建处理 (`TestFlight → release`)**：`https://github.com/Rookiei1/foodlog/actions/runs/43677917053`（通过 13 项单元测试、`ci/verify_release.py` 归档与 IPA 校验，成功上传 `1.0.0 (6)` 至 App Store Connect `6835001745`，完成 Apple 构建处理并分发给内部测试组）
