# mpv 和 mpv.net 开箱即用配置文件&精美 UI 主题&常用插件

## 简要说明

- 两套主题皮肤`modernz`、`uosc`
- 使用原生 mpv.net 播放器
- 集成进度条缩略图预览：[Thumbfast](https://github.com/po5/thumbfast)
- 集成漂亮的 UI 无边框设计：[Samillion/ModernZ]、[tomasklaen/uosc]
- 集成在线中文字幕搜素-搜索快捷键：`Alt + f`：[dyphire/mpv-sub-assrt]
- 支持全网弹幕加载，集成插件：[Tony15246/uosc_danmaku]
- 集成 Anime4K 超帧画质：[bloc97/Anime4K](https://github.com/bloc97/Anime4K)
- 快捷键优化
- 超简单，只需两个步骤即可完成享用

## 使用方法

- 先安装 mpv.net 播放器，下载地址：[mpvnet-player](https://github.com/mpvnet-player/mpv.net/releases)，推荐下载`setup-x64.exe`安装程序版本
- [🎯 点击下载](https://github.com/akFace/mpv.net.config/releases) 你想要的主题皮肤（每个都已包含完整配置）`modernz`和`uosc`，并解压
- 如图所示，右键>配置>打开配置文件夹或者`Ctrl + f`快捷键打开配置文件夹

  ![image](https://raw.githubusercontent.com/akFace/mpv.net.config/master/preview/Snipaste_2026-03-16_20-34-06.jpg)

- 将解压出的全部复制到配置文件夹(只能共存一个主题配置)，重启播放器即可
- 注意目录结构

```
一般的目录结构如下:
~/.config/mpv
├── fonts
├── scripts
├── script-opts
├── mpv.conf
└── input.conf

```

- 若你使用的并非 mpv.net 播放器，请修改`script-opts/thumbfast.conf`目录中的`mpv_path=mpvnet`改为`mpv_path=mpv`或者播放器安装目录可执行文件 例如：`mpv_path=C:\Program Files\mpv.net\mpvnet.exe`

## 快捷键

`Alt + f` 搜索字幕  
`Ctrl+d` 搜索弹幕  
`d` 显示/隐藏弹幕  
`Alt+d` 打开弹幕总开关菜单  
`Alt+z` 显示/隐藏 OSD（右上角信息：包括视频时间进度、系统时间）  
`Ctrl + i` 查看和设置所有快捷键

#### Anime4K 超帧画质开启快捷键

`Alt+0` 关闭 Anime4K，默认关闭

- 不同的模式有不同的效果，建议自行 AI 查询效果
- 适用显卡 GPU: (Eg. GTX 1080, RTX 2070, RTX 3060, RX 590, Vega 56, 5700XT, 6600XT) 以上  
  `Alt+F1` Anime4K: Anime4K: Mode A (HQ)  
  `Alt+F2` Anime4K: Anime4K: Mode B (HQ)  
  `Alt+F3` Anime4K: Anime4K: Mode C (HQ)  
  `Alt+F4` Anime4K: Anime4K: Mode A+A (HQ)  
  `Alt+F5` Anime4K: Anime4K: Mode B+B (HQ)  
  `Alt+F6` Anime4K: Anime4K: Mode C+A (HQ)

- 适用显卡 GPU: (Eg. GTX 980, GTX 1060, RX 570) 以下  
  `Alt+F7` Anime4K: Mode A (Fast)  
  `Alt+F8` Anime4K: Mode B (Fast)  
  `Alt+F9` Anime4K: Mode C (Fast)  
  `Alt+F10` Anime4K: Mode A+A (Fast)  
  `Alt+11` Anime4K: Mode B+B (Fast)  
  `Alt+F12` Anime4K: Mode C+A (Fast)

- 其他快捷键请看这里：[快捷键大全](https://zhuanlan.zhihu.com/p/533804122)
- 弹幕默认样式在配置文件夹`script-opts/uosc_danmaku.conf`下，要修改请使用文本编辑器打开编辑
- 注：`modernz`主题的弹幕插件没有界面 UI，只能通过快捷键来使用

## 预览效果图：

### 主题皮肤 1（modernz）

![image](https://raw.githubusercontent.com/akFace/mpv.net.config/master/preview/Snipaste_2026-03-16_20-32-59.jpg)

### 主题皮肤 2（uosc）

![image](https://raw.githubusercontent.com/akFace/mpv.net.config/master/preview/Snipaste_2026-03-18_16-51-00.jpg)
