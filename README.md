# 荣耀 iAware 框架层拦截 Google 服务：诊断与修复

> Honor iAware framework-layer Google service block — diagnosis & fix
> 设备：Honor REA-AN00 (Magic UI / Android 15)
> 日期：2026-07-30

---

## 问题现象

荣耀 (Honor) 手机在中国大陆使用时，会出现以下症状：

| 现象 | 详情 |
|------|------|
| Play 商店打不开 | 显示「出了点问题 / 您当前未连接到网络」 |
| Google 账号添加失败 | 系统设置 → 添加账户 → Google → 同样报错 |
| 收不到 Google 推送通知 | FCM (Firebase Cloud Messaging) 通道无法建立 |
| 但浏览器/curl 能访问 Google | 从 ADB shell 用 curl 访问 google.com 返回 200 |

**核心矛盾：网络明明是通的，但 Google 系 App 全部报「无网络」。**

---

## 根本原因：从第一性原理出发

### Android 网络栈的分层模型

```
┌─────────────────────────────────────────┐
│  应用层 (App)                             │
│  Google Play Services / Play Store        │
├─────────────────────────────────────────┤
│  应用框架层 (App Framework)               │
│  AccountManager / ConnectivityManager     │  ← iAware 在这里拦截
├─────────────────────────────────────────┤
│  网络框架层 (Network Framework)            │
│  Socket / DNS / Route                     │
├─────────────────────────────────────────┤
│  内核网络层 (Kernel Network Stack)         │
│  TUN device / iptables / netfilter        │
├─────────────────────────────────────────┤
│  物理网络层 (Physical Network)             │
│  WiFi / Cellular                          │
└─────────────────────────────────────────┘
```

### 第一性原理

**任何在内核网络层之上工作的拦截机制，都无法被在内核网络层工作的工具（VPN/TUN）绕过。**

iAware 钩入的是 Android 应用框架层（第 2 层），在 `ConnectivityManager` / `AccountManager` 层就拦截了 GMS (Google Mobile Services) 的网络请求。请求根本不会到达内核网络层，所以无论 VPN 怎么配置都无能为力。

比喻：
- VPN 是门口的安检站
- iAware 是大楼内部的门禁
- 如果大楼内部就不让你出门（iAware 拦截），你根本到不了门口的安检站（VPN）

### iAware 的触发条件

iAware 服务 (`com.hihonor.iaware`, uid=1000 系统级) 启动时读取以下条件：

| 属性 | 中国版手机典型值 |
|------|------------------|
| `gsm.sim.operator.iso-country` | `cn,cn` (中国运营商 SIM) |
| `ro.hw.country` | `cn` (硬件区域) |
| `ro.product.locale.region` | `CN` (产品区域) |
| `persist.sys.locale` | `zh-Hans-CN` (系统语言区域) |

全部命中中国条件后，iAware 写入属性并激活拦截：

```
[persist.sys.iaware_google_conn]: [时间戳, 0]
                                        ↑ 0 = 拦截, 1 = 放行
```

### 为什么 curl 能上 Google 但 Play 商店不行

| 路径 | 经过 iAware? | 结果 |
|------|-------------|------|
| `curl https://www.google.com` (ADB shell) | 否 (直接走内核网络栈) | 200 |
| 浏览器访问 Google | 否 | 能打开 |
| Play 商店请求 Google API | 是 (经过 GMS 框架) | 被拦截 |
| Google 账号添加 | 是 (经过 AccountManager) | 被拦截 |
| FCM 推送连接 (mtalk.google.com:5228) | 是 (经过 GMS 框架) | 被拦截 |

curl 和浏览器直接走内核网络栈，不经过 GMS 应用框架，所以 iAware 管不到。这就是为什么「网络看起来通但 Google 服务全挂」的根本原因。

---

## 解决方案：禁用 iAware

```bash
# 通过 ADB 禁用 iAware（需要 USB 调试）
adb shell pm disable-user --user 0 com.hihonor.iaware

# 重启手机让禁用生效
adb reboot
```

**关键区别：`pm disable-user` vs `am force-stop`**

| 命令 | 效果 | 重启后 |
|------|------|--------|
| `am force-stop` | 杀当前进程 | 系统会重新启动它 |
| `pm disable-user` | 包标记为禁用 | **不会重新启动** |

重启后 FCM (mtalk.google.com:5228) 即可建立连接，Google 推送通知恢复正常。

### 如果 iAware 被系统更新重新启用

```bash
# 检查 iAware 是否被重新启用
adb shell pm list packages -d | grep iaware

# 如果不在 disabled 列表里，重新禁用
adb shell pm disable-user --user 0 com.hihonor.iaware
adb reboot
```

### 副作用说明

iAware 同时负责电池优化 / 应用启动管理。禁用后：
- 影响极小，日常使用几乎无感知
- 后台应用管理会变得稍宽松（对大多数用户反而是好事）
- 不影响系统稳定性、不影响其他功能

---

## 诊断方法论

```
现象: Google 服务不通但网络看起来是通的
  ↓
第一步: VPN/TUN 接口是否真的 UP?
   adb shell ip -o addr show tun0
  ↓
第二步: 从 shell 直连 Google 是否通?
   adb shell curl -s -o /dev/null -w '%{http_code}' https://www.google.com
   → 如果通 → 拦截不在网络层，在框架层
  ↓
第三步: 检查 iAware 状态
   adb shell getprop persist.sys.iaware_google_conn
   adb shell pm list packages -d | grep iaware
  ↓
第四步: 检查触发条件
   adb shell getprop gsm.sim.operator.iso-country
   adb shell getprop ro.hw.country
  ↓
第五步: 禁用 iAware + 重启 → 验证
```

**核心教训：当网络看起来通但特定 App 不通时，先确定拦截发生在哪一层（应用层/框架层/网络层），而不是盲目改网络配置。**

---

## 完整时间线

```
2026-07-30 (北京时间)

10:05:47   ★ iAware 触发 Google 拦截 ★
           persist.sys.iaware_google_conn = [1785377147, 0]
           (手机开机/SIM 注册后自动检测中国区域)

10:13:48   用户第一次尝试登录 Google → 失败

··· 间隔约 5 小时 ···

15:10      用户发起求助

15:10-15:34  第一阶段: 怀疑是网络/VPN 配置问题
             - 检查 VPN 状态 → UP
             - 测试 curl → Google = 200 (从 shell 能通)
             - 尝试各种 VPN 配置修改 (MTU, http_proxy, auto_detect_interface)
             → 全部无效

15:34-15:40  关键转折: 检查 VPN 连接列表
             → 发现 Google/Play 流量根本没出现在列表里
             → 流量没到达 VPN → 拦截在更上层

15:40-15:49  第二阶段: 定位系统层拦截
             - getprop | grep google → 发现 iaware_google_conn
             - 解码时间戳: 1785377147 = 10:05:47
             - 发现 SIM 卡国家 = cn, 系统区域 = CN
             - 确认是荣耀 iAware 系统拦截

15:49       执行: adb shell pm disable-user --user 0 com.hihonor.iaware

15:49-15:53  用户手动重启手机

15:53:32    VPN 重新启动 (tun0 UP)

15:55       FCM 连接建立: mtalk.google.com:5228 → 美国节点
            Google 账号添加成功
            ★ 问题解决 ★

16:00       用户确认: "真可以了"
```

---

## 关键命令速查

```bash
# 检查 iAware 状态
adb shell getprop persist.sys.iaware_google_conn
# 输出: [时间戳, 0/1]  0=拦截 1=放行

# 检查 iAware 包是否被禁用（权威检查）
adb shell pm list packages -d | grep iaware

# 检查 SIM 卡国家（iAware 触发条件）
adb shell getprop gsm.sim.operator.iso-country

# 检查 FCM 推送通道是否建立
adb shell "ss -tn | grep -E ':5228|:5229|:5230'"

# 禁用 iAware
adb shell pm disable-user --user 0 com.hihonor.iaware

# 重新启用 iAware (如需恢复)
adb shell pm enable com.hihonor.iaware

# 查看 GMS 相关日志
adb shell logcat | grep -iE "gms|play|firebase|mtalk"
```

---

## 总结

本次问题的本质是：**荣耀手机在系统框架层内置的 Google 服务拦截机制，针对中国市场设备激活。**

关键认知：
1. **拦截发生在哪一层决定了能用什么工具解决** — 框架层拦截无法被网络层工具 (VPN) 绕过
2. **国产手机的「Google 不通」问题，往往不是网络问题，而是厂商策略问题**
3. **诊断时先确定拦截发生在哪一层，再决定解决方案**
4. **`pm disable-user` 是禁用系统服务的有效手段，不需要 Root**

最终解决方案：**禁用 `com.hihonor.iaware` + 重启**，一行命令解决困扰数小时的问题。

---

## 适用范围

- ✅ 荣耀 (Honor) 手机，中国版固件
- ✅ Magic UI 系统
- ⚠️ 华为 (Huawei) 早期机型可能有类似机制（iAware 起源于华为）
- ❌ 小米 / OPPO / vivo 等其他品牌使用不同的策略，需要单独分析

## 免责声明

本仓库记录的是在**个人自有设备**上诊断和修复系统服务行为的过程。所有操作均使用 Android 官方调试工具 (adb) 在用户拥有的设备上完成，不涉及任何破解、Root 或绕过系统安全机制。读者对在自己设备上执行的操作自行负责。
