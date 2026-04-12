<img width="1746" height="488" alt="image" src="https://github.com/user-attachments/assets/d4a33d70-c03f-411b-846d-ebe6b977a2b2" />


# Waterctl (HarmonyOS 6)

基于 ArkTS + ArkUI 的鸿蒙原生水控器应用，支持 BLE 扫描、连接、开关水、断开及使用时长记录。

## 功能

- 扫描并展示蓝牙设备
- 列表显示设备名、MAC、RSSI 与信号强度图形
- 连接/断开水控器
- 开水/关水控制
- 本地保存每次用水时长记录
- 实况窗不知道为什么做不出来，懒得搞了，但是代码还在

## 项目结构

- `entry/src/main/ets/pages/Index.ets`：主页面与交互
- `entry/src/main/ets/services/BleService.ets`：BLE 扫描/连接/写入/断连处理
- `entry/src/main/ets/storage/UsageRepo.ets`：历史记录持久化
- `entry/src/main/ets/storage/LiveViewStateRepo.ets`：实况状态持久化
- `entry/src/main/ets/entryliveformability/EntryLiveFormAbility.ets`：liveForm 扩展入口
- `entry/src/main/ets/pages/LiveView.ets`：实况展示页面

## 环境要求

- DevEco Studio（HarmonyOS NEXT / API 6.0.2）
- HarmonyOS 真机（建议，BLE 调试必需）

## 权限

已在 `entry/src/main/module.json5` 中声明：

- `ohos.permission.ACCESS_BLUETOOTH`
- `ohos.permission.DISCOVER_BLUETOOTH`
- `ohos.permission.LOCATION`

应用启动时会动态申请权限。

## 构建与运行

1. 用 DevEco Studio 打开项目根目录 `waterctl`
2. 同步依赖并选择 `entry` 模块
3. 连接真机，选择 `debug` 构建运行

## 使用说明

1. 首次进入授权蓝牙/定位权限
2. 在设备列表中选择目标水控器并点击“连接”
3. 连接成功后可点击“开水 / 关水 / 断开”
4. 使用记录会显示在页面下方，可点击“清空记录”

## 调试建议

- 关注日志标签：`WaterctlBLE`
- 若扫描失败，先确认系统蓝牙与定位开关已开启
- 若连接中断，应用会自动重置并重新扫描

---

免责申明：这玩意是我闲着没事时兴起写的，能用，但是出了问题不要找我，去找Sam Altman
