# 全局划词翻译

在 Windows 上任何窗口里选中文字,松开鼠标自动弹出翻译;选中大段文字则出现一个小图标,点击后可选"翻译"或"复制"。

## 组成

| 文件 | 作用 |
|---|---|
| `translator.ahk` | AutoHotkey v2 脚本,常驻后台,监听全局鼠标拖选,负责弹窗 UI |
| `translate.ps1` | 被 `translator.ahk` 调用,负责实际请求 Claude API 并解析结果 |
| `config.ini` | 存放你的 API Key 和一些行为参数(**不会被提交到 git**) |
| `config.example.ini` | 配置模板,给别人参考用的 |

## 使用前准备

1. **安装 AutoHotkey v2**:https://www.autohotkey.com/ → Download → 选 v2 版本安装
2. **打开 `config.ini`**,把 `key = YOUR_ANTHROPIC_API_KEY_HERE` 换成你自己的 Key(从 https://platform.claude.com/settings/keys 复制)

## 启动

双击 `translator.ahk` 即可运行(装好 AutoHotkey 后,双击会自动用它执行)。任务栏右下角出现一个绿色小图标就说明启动成功了。

- **短文本**(≤20 字符,可在 `config.ini` 里改):选中并松开鼠标后,几秒内自动弹出翻译结果(音标/词性/释义),会一直显示,直到你点别处或重新选中别的内容才消失
- **长文本**:选中后旁边出现一个小小的"译"按钮,点一下弹出菜单,选"翻译"或"复制"
- 退出:右键点任务栏的 AutoHotkey 图标 → Exit

## 开机自启(可选)

把 `translator.ahk` 的快捷方式放进这个文件夹:
```
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
```
下次开机就会自动运行。

## 已知限制

- 如果目标程序是以**管理员身份**运行的(比如某些以管理员打开的软件),普通权限下的 AutoHotkey 脚本模拟不了 `Ctrl+C`,选中了也不会有反应。如果需要,把 `translator.ahk` 也用管理员身份运行即可
- 划词的判定方式是"鼠标拖拽后剪贴板内容发生变化",在拖动文件、调整窗口大小等场景下不会误触发(因为剪贴板不会变),但在个别支持拖拽复制的软件里可能有极少数误判
- 该工具会在你拖选文字的瞬间读取剪贴板,理论上如果你选中的是密码框里的文字也会被读取到,请注意在敏感字段里划词时留意
