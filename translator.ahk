#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook true

; ============================================================
;  全局划词翻译工具
;  - 短选(<= ShortMax 字符):松开鼠标后自动弹出翻译结果,
;    一直显示到你点别处 / 换选别的内容为止(不会自己倒计时消失)
;  - 长选:出现一个小 "译" 图标(这个还是 8 秒后自动消失),点击后弹菜单(翻译 / 复制)
; ============================================================

global ScriptDir := A_ScriptDir
global ShortMax := 20

global downX := 0
global downY := 0
global popupGui := ""
global iconGui := ""

ReadBehaviorConfig()

TrayTip("划词翻译已启动", "选中文字试试看吧", "Mute")

; ---------- 鼠标按下:记录起点,顺手关掉上一次的弹窗 ----------
~LButton:: {
    global downX, downY
    SafeDestroy(&popupGui)
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

; ---------- 处理选中文本 ----------
HandleSelection(mx, my) {
    global ShortMax

    savedClip := ClipboardAll()
    A_Clipboard := ""

    Send("^c")
    if !ClipWait(0.4) {
        A_Clipboard := savedClip
        return
    }

    text := Trim(A_Clipboard)
    A_Clipboard := savedClip

    if (text = "")
        return

    if (StrLen(text) <= ShortMax) {
        ; 用系统自带的轻量 Tooltip 做等待提示(没有自定义窗口的创建开销,不会闪)
        ToolTip("翻译中…", mx + 15, my + 15)
        result := CallTranslate(text)
        ToolTip()
        ShowResultPopup(mx, my, result)
    } else {
        ShowTranslateIcon(mx, my, text)
    }
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

; ---------- 短文本:自动弹出的翻译结果框(带淡入动画) ----------
; 不设自动消失的计时器 —— 只要选区还在就一直显示,
; 直到你点别处 / 重新选中别的内容(见 ~LButton:: 里的 SafeDestroy)才消失。
ShowResultPopup(x, y, text) {
    global popupGui
    SafeDestroy(&popupGui)

    popupGui := Gui("+AlwaysOnTop -Caption +ToolWindow", "translate")
    popupGui.BackColor := "0xFFFCE8"
    popupGui.SetFont("s10", "Microsoft YaHei")
    popupGui.AddText("w300 cBlack", text)
    popupGui.Show("x" (x + 15) " y" (y + 15) " NoActivate")

    FadeIn(popupGui.Hwnd)
}

; ---------- 淡入动画:透明度从 0 平滑过渡到不透明 ----------
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
    SetTimer(() => SafeDestroy(&iconGui), -8000)
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
