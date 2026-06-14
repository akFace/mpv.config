# mpv 和 mpv.net 开箱即用配置文件&精美 UI 主题皮肤&常用插件（Windows、macOS、Linux）

## 简要说明

- 支持 Windows、macOS、Linux
- 两套主题皮肤`modernz`、`uosc`
- 使用原生 mpv 播放器，配置/播放器分离，无需担心播放器无法更新到最新版
- 集成进度条缩略图预览：[Thumbfast](https://github.com/po5/thumbfast)
- 集成漂亮的 UI 无边框设计：[Samillion/ModernZ]、[tomasklaen/uosc]
- 集成在线中文字幕搜素-搜索快捷键：`Alt + f`：[dyphire/mpv-sub-assrt]
- 支持全网弹幕加载，集成插件：[Tony15246/uosc_danmaku]
- 集成 Anime4K 超分超清画质，提升画质：[Anime4K](https://github.com/bloc97/Anime4K)
- 支持插帧模式功能，提升流畅度
- 快捷键优化
- 超简单，只需两个步骤即可完成享用

## 使用方法

- 先安装 mpv 或者 mpv.net 播放器 **(Windows 用户推荐下载 mpv.net)**，下载地址：[mpvnet-player](https://github.com/mpvnet-player/mpv.net/releases)，建议下载`setup-x64.exe`安装程序版本。其他用户下载：[mpv 原生播放器](https://mpv.io/)
- [🎯 点击下载](https://github.com/akFace/mpv.net.config/releases) 你想要的主题皮肤（每个都已包含完整配置）`modernz`和`uosc`，并解压，**以下 ① 和 ② 根据自己选择的播放器按对应教程来即可**
- **①. mpv.net 播放器**：如图所示，右键>配置>打开配置文件夹或者`Ctrl + f`快捷键打开`配置文件夹`

  ![image](https://raw.githubusercontent.com/akFace/mpv.net.config/master/preview/Snipaste_2026-03-16_20-34-06.jpg)

- **②. mpv 原生播放器**：解压/安装播放器后，在播放器根目录下新建名为 `portable_config` 文件夹，作为`配置文件夹`
- 将解压出的全部复制到`配置文件夹`(只能共存一个主题配置)，重启播放器即可
- 注意目录结构

```
一般的目录结构如下:
~/.config/配置文件夹目录
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
`Ctrl+-` 画面缩放：缩小  
`Ctrl++` 画面缩放：放大  
`Ctrl + i` 查看和设置所有快捷键

#### 超帧插帧开启快捷键

`n` 键，默认关闭插帧，连按循环：`关闭插帧` ➜ `电影模式` ➜ `动漫模式` ➜ `极致丝滑`

- 说明：`电影模式`（去抖动，零模糊）、`动漫模式`：sphinx 配合 0.65 模糊度，既丝滑又能收紧二次元的线条，不发糊、`极致丝滑`：bicubic 默认稍糊，设定为 -0.40 稍微锐化一下，压制过度黏糊感
- 本配置使用 mpv 内置时间轴插帧（interpolation=yes）—— 根据网上 AI 结论：最推荐，综合体验最好，适合大部分硬件设备。[如果需要其他插帧方式，可询问 AI，方法也很简单]
- 结合 Anime4K 超分画质达到最佳观影体验

#### Anime4K 超分画质开启快捷键

`Alt+del` 关闭 Anime4K，默认关闭

- 不同的模式有不同的效果，建议自行 AI 查询效果，看动漫强烈建议开启超分画质功能，效果十分明显
- 适用显卡 GPU: (Eg. GTX 1080, RTX 2070, RTX 3060, RX 590, Vega 56, 5700XT, 6600XT) 以上  
  `Alt+F1` Anime4K: Mode A (HQ)  
  `Alt+F2` Anime4K: Mode B (HQ)  
  `Alt+F3` Anime4K: Mode C (HQ)  
  `Alt+F4` Anime4K: Mode A+A (HQ)  
  `Alt+F5` Anime4K: Mode B+B (HQ)  
  `Alt+F6` Anime4K: Mode C+A (HQ)

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

## 如何更新到最新版

- 播放器更新：直接下载最新版[🎬[mpv.net 播放器]](https://github.com/mpvnet-player/mpv.net/releases) 或者[[mpv 原生播放器]](https://mpv.io/)安装即可
- 配置主题皮肤更新：直接下载最新版[🎯 点击下载](https://github.com/akFace/mpv.net.config/releases) 解压覆盖即可

## 预览效果图：

### 主题皮肤 1（modernz）

![image](https://raw.githubusercontent.com/akFace/mpv.net.config/master/preview/Snipaste_2026-03-16_20-32-59.jpg)

### 主题皮肤 2（uosc）

![image](https://raw.githubusercontent.com/akFace/mpv.net.config/master/preview/Snipaste_2026-03-18_16-51-00.jpg)
