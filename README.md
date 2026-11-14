# 食刻 FoodLog

**食刻 FoodLog** 是一款采用 Local-first 架构的原生 iPhone 智能饮食记录与体重管理应用（Swift + SwiftUI + SwiftData + Swift Charts），最低支持 iOS 17.0。

## 功能概览

- **首页仪表盘**：按任意日期查看热量环、距离目标差额、三大营养素（蛋白质 / 脂肪 / 碳水化合物）进度条、常吃食物一键快记、五餐次卡片（早餐 / 午餐 / 晚餐 / 夜宵 / 加餐）、近期体重趋势及浮动「拍照记录」按钮。
- **AI 拍照识别**：
  - 支持相机拍照或相册多选图片，发送前明确提示第三方 AI 传输说明。
  - 多食物分项识别（如鸡排、烤肠、牛奶分别估算重量与营养素），同一餐多角度照片去重。
  - 优先识别包装「营养成分表」（支持 kJ 自动转 kcal 与包装净含量换算）。
  - 重量不确定时给出 `[最小克数, 最大克数]` 合理区间与估算依据，支持逐项编辑后保存。
- **多供应商 AI API 接入**：
  - 内置 **OpenAI**、**DeepSeek**、**Google Gemini**、**OpenAI-Compatible 自定义接口** 与 **内置离线演示（Mock）** 独立适配层。
  - API Key 仅存储在 iOS 系统 **Keychain**，不落盘明文、不进入备份、不打印日志。
  - 拍照识别前自动校验模型视觉能力（如拦截仅支持文本的 `deepseek-chat` 并提示切换视觉模型）。
  - 支持请求超时控制、主动取消、限流/余额不足/JSON 格式异常等结构化错误处理。
- **每日体重与趋势图表**：
  - 支持一天多次称重，可按「晨起空腹优先」「当日最低」「当日最新」「当日平均」一致规则提取每日代表值。
  - 使用 `Swift Charts` 绘制 7 天、30 天、90 天及自定义日期范围交互式曲线、目标体重参考线、周平均体重与每周增重/减重速率。
- **AI 综合数据分析**：
  - 支持最近 7 天、30 天、90 天或全部历史记录。
  - 先基于本地数据库生成真实客观统计摘要，经用户确认后再发送给所选 AI 模型。
  - 报告严格区分**客观统计数据**、**估算偏差与体重短期水分/糖原波动说明**以及**下周饮食与增重调整建议**。
- **数据导出与恢复**：
  - 支持导出 **CSV 饮食记录**、**CSV 体重记录**、**JSON 完整结构化数据备份**（含格式版本号，支持跨设备恢复；默认不打包照片与 API Key，提供独立开关包含照片）与 **PDF 中文分析报告**。

## 架构目录

```text
FoodLog/
├─ project.yml                  # XcodeGen 工程定义
├─ Gemfile                      # Fastlane 依赖
├─ FoodLog/
│  ├─ FoodLogApp.swift          # 应用入口
│  ├─ Info.plist                # 权限说明与基础配置
│  ├─ PrivacyInfo.xcprivacy     # App Store 隐私清单
│  ├─ Models/                   # 饮食、体重、目标、AI 响应模型
│  ├─ AIProviders/              # 多供应商适配器、视觉能力检测、JSON 校验
│  ├─ Services/                 # 营养计算、体重统计引擎、图片压缩存储
│  ├─ Persistence/              # SwiftData 容器与 Keychain 服务
│  ├─ Export/                   # CSV / JSON 备份恢复 / PDF 渲染导出
│  ├─ ViewModels/               # 全局状态与可取消任务管理
│  ├─ Views/                    # 首页、饮食、体重、AI 分析、设置视图
│  └─ Utilities/                # 日期格式与主题设计系统
├─ Tests/                       # 单元测试（营养、体重、AI 校验、导出恢复）
├─ UITests/                     # iOS Simulator UI 测试
├─ ci/                          # 签名校验、IPA 核验与截图脚本
├─ fastlane/Fastfile            # diagnose / bootstrap / release 自动化通道
└─ .github/workflows/           # Test 与 TestFlight GitHub Actions 工作流
```

## 本地生成与测试（macOS / Xcode 26+）

```bash
brew install xcodegen
xcodegen generate
xcodebuild test \
  -project FoodLog.xcodeproj \
  -scheme FoodLog \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

## TestFlight 发布说明

详见 [RELEASE.md](RELEASE.md)。
