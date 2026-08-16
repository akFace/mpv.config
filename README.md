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
- 可视化调节均衡器：[Equalizer-GUI](https://github.com/akFace/equalizer-gui)
- 功能强大的跨平台右键菜单：[mpv-menu-plugin-next](https://github.com/akFace/mpv-menu-plugin-next)
- 快捷键优化
- 超简单，只需两个步骤即可完成享用
- [>>查看主题预览效果截图](https://github.com/akFace/mpv.config#%E9%A2%84%E8%A7%88%E6%95%88%E6%9E%9C%E5%9B%BE)
- [>>常见相关问题](https://github.com/akFace/mpv.config#一些常用设置文档可选)

## 使用方法

- 先安装 mpv 或者 mpv.net 播放器 **(Windows 推荐 mpv.net)**，下载地址：[mpvnet-player](https://github.com/mpvnet-player/mpv.net/releases)，建议下载`setup-x64.exe`安装程序版本。||=>其他用户下载：[mpv 原生播放器](https://mpv.io/)
- [🎯 点击下载](https://github.com/akFace/mpv.config/releases) 你想要的主题皮肤（每个都已包含完整配置）`modernz`和`uosc`，并解压，**以下 ① 和 ② 根据自己选择的播放器按对应教程来即可**
- **①. mpv.net 播放器**：如图所示，右键>配置>打开配置文件夹或者`Ctrl + f`快捷键打开`配置文件夹`

  ![image](https://raw.githubusercontent.com/akFace/mpv.net.config/master/preview/Snipaste_2026-03-16_20-34-06.jpg)

- **②. mpv 原生播放器**：解压/安装播放器后，在播放器根目录下新建名为 `portable_config` 文件夹，作为`配置文件夹`
- 将解压出的全部复制到`配置文件夹`(只能共存一个主题配置)，重启播放器即可
- 注意目录结构

```
一般的目录结构如下:
~/mpv/配置文件夹目录
      ├── fonts
      ├── scripts
      ├── script-opts
      ├── mpv.conf
      └── input.conf
```

> ⚠️ **提示**：若你使用的并非 mpv.net 播放器，请修改`script-opts/thumbfast.conf`目录中的`mpv_path=mpvnet`改为`mpv_path=mpv`或者播放器安装目录可执行文件 例如：`mpv_path=C:\Program Files\mpv.net\mpvnet.exe`

### **[👉 常用快捷键](https://github.com/akFace/mpv.config/wiki/%E5%BF%AB%E6%8D%B7%E9%94%AE)**

### 一些常用设置&文档（可选）

- 弹幕默认样式在配置文件夹`script-opts/uosc_danmaku.conf`下，要修改请使用文本编辑器打开编辑
- 弹幕相关配置：[查看文档](https://github.com/Tony15246/uosc_danmaku#%E7%9B%AE%E5%BD%95)
- **关于弹幕流畅度问题**，目前本人的设备屏幕是 4k60hz，要打开`video-sync=display-resample`才流畅，但有些用户的设备打开此设置开倍速播放会导致声音卡问题，因此现在默认关闭，需要设置的请打开 mpv.conf 文件编辑，删除此行代码最前面的 # 号
- 跳过片头片尾：在配置文件夹中`mpv.conf`,打开编辑，可看到注释的跳过片头片尾，把注释的#号去掉，填写上自定义的片头片尾时间重启播放器即可
- **推荐：** 油猴脚本 👉 [play-with-mpv 使用 mpv 播放网页中的视频](https://github.com/akFace/play-with-mpv)
- [UOSC 主题](https://github.com/tomasklaen/uosc)
- [ModernZ 主题](https://github.com/Samillion/ModernZ)
- [Equalizer-GUI 均衡器](https://github.com/akFace/equalizer-gui)
- **语言/language:** The language setting for the modernz theme is in `script-opts/modernz.conf`, and the language setting for the uosc theme is in `script-opts/uosc.conf`. You can see it by searching for the keyword `language` in the file.，Download `input-en.conf` and rename it to `input.conf`, then replace the original file

## 如何更新到最新版

- 播放器更新：直接下载最新版[🎬[mpv.net 播放器]](https://github.com/mpvnet-player/mpv.net/releases) 或者[[mpv 原生播放器]](https://mpv.io/)安装即可
- 配置主题皮肤更新：直接下载最新版[🎯 点击下载](https://github.com/akFace/mpv.config/releases) 解压覆盖即可

## 预览效果图：

### 主题皮肤 1（modernz）

![image](https://raw.githubusercontent.com/akFace/mpv.net.config/master/preview/Snipaste_2026-03-16_20-32-59.jpg)

### 主题皮肤 2（uosc）

![image](https://raw.githubusercontent.com/akFace/mpv.net.config/master/preview/Snipaste_2026-03-18_16-51-00.jpg)

### 功能强大的右键菜单

default：
![image](https://raw.githubusercontent.com/akFace/mpv.net.config/master/preview/Snipaste_2026-08-15_00-09-37.jpg)
macos-white：
![image](https://github.com/akFace/mpv.config/raw/master/doc/preview/Snipaste_2026-08-16_01-04-38.jpg)
macos-dark：
![image](https://github.com/akFace/mpv.config/raw/master/doc/preview/Snipaste_2026-08-16_01-10-14.jpg)

### 可视化均衡器 eq

![alt text](https://github.com/akFace/equalizer-gui/raw/main/images/Snipaste_2026-08-13_18-08-43.jpg)
