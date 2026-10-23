# Teleprompter for macOS 录屏提词器

A floating teleprompter for macOS that stays visible on your screen but is hidden from most screen recordings.

一个浮在屏幕最上层的 Mac 提词器。屏幕上看得见，但大多数录屏软件录不到它。

## 功能 Features

- 自己输入或粘贴提词，随时编辑、删除、更新，内容自动保存
- 自动滚动，可调速度；也可以用鼠标滚轮手动滚动
- 调节字号、背景透明度，配色可选白字黑底或黑字白底
- 窗口始终置顶，播放时点按钮不会抢走浏览器焦点
- 录屏时不录提词窗口（`NSWindow.sharingType = .none`）

## 安装 Install

需要 macOS 和 Xcode 命令行工具：

```bash
xcode-select --install
```

下载本仓库后，在文件夹里编译：

```bash
swiftc teleprompter.swift -o teleprompter
./teleprompter
```

想双击打开的话，给启动文件加执行权限：

```bash
chmod +x 打开提词器.command
```

之后双击 `打开提词器.command` 即可。第一次打开如果提示"无法打开"，右键选"打开"。

## 使用 Usage

| 按钮 | 作用 |
|---|---|
| 编辑 / 完成 | 进入或退出编辑，支持 Cmd+C/V/X/A/Z |
| 播放 / 暂停 | 自动滚动 |
| 慢 / 快 | 调整滚动速度 |
| A- / A+ | 调整字号 |
| 回到开头 | 滚回顶部 |
| 清空 | 清空文字（可 Cmd+Z 撤回） |
| 背景透明度 | 拖动滑块调节 |
| 配色 | 白字黑底 / 黑字白底 |

## 注意 Notes

- 正式录制前先试录几秒，确认提词窗口没被录进去。新版 macOS 上部分录屏软件可能无视这个设置；遇到这种情况，改为只录制浏览器窗口而不是全屏。
- 使用时终端不要关，关掉终端程序也会退出。

## License

MIT
