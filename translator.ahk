#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook true

; ============================================================
;  全局划词翻译工具
;  - 短选(<= ShortMax 字符):松开鼠标后自动弹出翻译结果(系统原生 Tooltip),
;    鼠标只要挪开选区一定距离(或者点一下),就立刻消失 —— 不需要专门去点别处
;  - 长选:出现一个小 "译" 图标(8 秒后自动消失),点击后弹菜单(翻译 / 复制)
; ============================================================

global ScriptDir := A_ScriptDir
global ShortMax := 20
global AwayDistance := 60   ; 鼠标离开选区多少像素后,自动收起翻译提示

global downX := 0
global downY := 0
global iconGui := ""
global popupWatchTimer := 0
global isProcessing := false
global requestGen := 0

ReadBehaviorConfig()

TrayTip("划词翻译已启动", "选中文字试试看吧", "Mute")

; ---------- 鼠标按下:记录起点,顺手关掉上一次的弹窗 ----------
~LButton:: {
    global downX, downY, iconGui
    HidePopup()
    SafeDestroy(&iconGui)
    MouseGetPos(&x, &y)
    downX := x
    downY := y
}

; ---------- 鼠标松开:如果是拖拽(而不是单纯点击),当作一次选中 ----------
~LButton Up:: {
    global downX, downY
    MouseGetPos(&x, &y)
    dist := Sqrt((x - downX) ** 2 + (y - downY) ** 2)
    if (dist > 8) {
        HandleSelection(x, y)
    }
}

; 已知的截图工具进程名 —— 在这些工具的窗口里拖拽,不当作文字选中处理
global ScreenshotToolProcesses := [
    "ScreenClippingHost.exe", "SnippingTool.exe", "ShareX.exe",
    "PicPick.exe", "Greenshot.exe"
]

; ---------- 处理选中文本 ----------
HandleSelection(mx, my) {
    global ShortMax, ScreenshotToolProcesses, isProcessing, requestGen

    activeHwnd := WinExist("A")
    if (activeHwnd) {
        try {
            procName := WinGetProcessName("ahk_id " activeHwnd)
            for toolName in ScreenshotToolProcesses {
                if (procName = toolName)
                    return
            }
        }
    }

    ; 抢剪贴板这一小段(通常零点几秒)排队执行,避免两次划词同时读写剪贴板报错;
    ; 后面比较慢的翻译请求本身不受这个限制,可以多个同时进行。
    if (isProcessing)
        return
    isProcessing := true
    text := ""
    gotChange := false
    try {
        savedClip := TryGetClipboardAll()
        if !IsObject(savedClip)
            return

        A_Clipboard := ""
        Send("^c")
        gotChange := ClipWait(0.4)
        text := gotChange ? Trim(A_Clipboard) : ""

        ; 只有在剪贴板里现在的内容确实还是"刚才我们自己复制出来的这份"时才还原,
        ; 否则说明这段时间里有别的程序(比如截图工具刚截完图)也写了剪贴板,
        ; 这时候不要动它,免得把人家刚放进去的新内容(比如截图)覆盖掉。
        currentIsOurs := gotChange ? (A_Clipboard == text) : (A_Clipboard == "")
        if (currentIsOurs)
            try A_Clipboard := savedClip
    } finally {
        isProcessing := false
    }

    if (!gotChange || text = "")
        return

    ; 每次划词发一个"代次号",翻译回来的时候如果已经不是最新一次划词,
    ; 就直接丢弃这个结果 —— 避免"上一个词翻译很慢,回来的时候鼠标已经跑远了"
    ; 导致弹窗一闪就消失的怪现象。
    myGen := ++requestGen

    if (StrLen(text) <= ShortMax) {
        ; 用系统自带的轻量 Tooltip 做等待提示(没有自定义窗口的创建开销,不会闪)
        ToolTip("翻译中…", mx + 15, my + 15)
        result := CallTranslate(text)
        ToolTip()
        if (myGen != requestGen)
            return
        ShowResultPopup(mx, my, result)
    } else {
        ShowTranslateIcon(mx, my, text)
    }
}

; 剪贴板偶尔会被别的程序短暂占用,读取失败就重试几次,一直不行就放弃这次划词
TryGetClipboardAll() {
    Loop 3 {
        try
            return ClipboardAll()
        catch
            Sleep(30)
    }
    return ""
}

; ---------- 调用 PowerShell 脚本做实际翻译 ----------
CallTranslate(text) {
    global ScriptDir
    inFile := A_Temp "\wt_in.txt"
    outFile := A_Temp "\wt_out.txt"

    try FileDelete(outFile)

    f := FileOpen(inFile, "w", "UTF-8")
    f.Write(text)
    f.Close()

    ps1 := ScriptDir "\translate.ps1"
    cmd := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' ps1 '" "' inFile '" "' outFile '"'
    RunWait(cmd, , "Hide")

    if !FileExist(outFile)
        return "[没有收到结果,请检查 PowerShell 是否可用]"

    return Trim(FileRead(outFile, "UTF-8"))
}

; ---------- 短文本:翻译结果提示(系统原生 Tooltip,不会有残留/幽灵窗口) ----------
; 显示后开始监视鼠标位置,一旦鼠标离选中位置超过 AwayDistance 像素就自动收起,
; 不需要专门点一下别处才消失。
ShowResultPopup(x, y, text) {
    global popupWatchTimer
    HidePopup()

    ToolTip(text, x + 15, y + 15)

    watcher := WatchMouseAway.Bind(x, y)
    popupWatchTimer := watcher
    SetTimer(watcher, 120)
}

; ---------- 鼠标是否已经离开选中点太远,离开就收起 ----------
WatchMouseAway(anchorX, anchorY) {
    global popupWatchTimer
    MouseGetPos(&mx, &my)
    dist := Sqrt((mx - anchorX) ** 2 + (my - anchorY) ** 2)
    if (dist > AwayDistance) {
        ToolTip()
        SetTimer(popupWatchTimer, 0)
        popupWatchTimer := 0
    }
}

; ---------- 收起翻译提示(点击 / 新选区 / 鼠标移开时统一调用) ----------
HidePopup() {
    global popupWatchTimer
    ToolTip()
    if (popupWatchTimer) {
        SetTimer(popupWatchTimer, 0)
        popupWatchTimer := 0
    }
}

; ---------- 淡入动画:透明度从 0 平滑过渡到不透明(给长文本的小图标用) ----------
FadeIn(hwnd, steps := 10, stepDelayMs := 12) {
    WinSetTransparent(0, "ahk_id " hwnd)
    Loop steps {
        ; 淡入过程中窗口可能已经被关闭(比如用户很快又点了一下),这里直接停止
        if !WinExist("ahk_id " hwnd)
            return
        WinSetTransparent(Round(A_Index / steps * 255), "ahk_id " hwnd)
        Sleep(stepDelayMs)
    }
}

; ---------- 长文本:小图标 + 点击菜单 ----------
ShowTranslateIcon(x, y, text) {
    global iconGui
    SafeDestroy(&iconGui)

    iconGui := Gui("+AlwaysOnTop -Caption +ToolWindow", "icon")
    iconGui.SetFont("s10 bold", "Microsoft YaHei")
    btn := iconGui.AddButton("w32 h32", "译")
    btn.OnEvent("Click", ShowLongTextMenu.Bind(text, x, y))
    iconGui.Show("x" (x + 10) " y" (y + 10) " w32 h32 NoActivate")

    FadeIn(iconGui.Hwnd)
    SetTimer(HideIconGui, -8000)
}

; 单独用一个具名函数来关闭图标,不要在箭头函数里对外层变量取地址(&) ——
; 这种写法在 AutoHotkey v2 里偶尔会导致引用失效,报 "parameter has not been assigned a value"
HideIconGui() {
    global iconGui
    SafeDestroy(&iconGui)
}

ShowLongTextMenu(text, x, y, *) {
    global iconGui
    SafeDestroy(&iconGui)

    menu := Menu()
    menu.Add("翻译", TranslateMenuItem.Bind(text, x, y))
    menu.Add("复制", CopyMenuItem.Bind(text))
    menu.Show(x, y)
}

TranslateMenuItem(text, x, y, *) {
    ToolTip("翻译中…", x + 15, y + 15)
    result := CallTranslate(text)
    ToolTip()
    ShowResultPopup(x, y, result)
}

CopyMenuItem(text, *) {
    A_Clipboard := text
    ToolTip("已复制")
    SetTimer(() => ToolTip(), -1200)
}

; ---------- 工具函数 ----------
SafeDestroy(&guiVar) {
    if IsObject(guiVar) {
        try guiVar.Destroy()
        guiVar := ""
    }
}

ReadBehaviorConfig() {
    global ScriptDir, ShortMax
    cfg := ScriptDir "\config.ini"
    if !FileExist(cfg)
        return
    v := IniRead(cfg, "behavior", "short_text_max_chars", "20")
    if v is Integer
        ShortMax := Integer(v)
}
