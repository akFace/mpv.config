# mpv 和 mpv.net 播放器开箱即用配置文件&精美 UI 主题皮肤&常用插件（支持 Windows、macOS、Linux）

> - mpv 配置文件支持 Windows、macOS、Linux，全平台带有一致的右键菜单功能
> - The configuration file of the mpv player supports Windows, macOS, Linux, with a consistent context menu feature across all platforms.

## 简要说明

- 两套主题皮肤`modernz`、`uosc`，漂亮的现代化 UI 无边框设计
- 使用原生 mpv 播放器，配置/播放器分离，无需担心播放器无法更新到最新版
- 集成进度条缩略图预览
- 集成在线中文字幕搜索
- 支持全网弹幕在线加载
- 集成 Anime4K 超分画质，实时提升画质
- 支持多种视频着色器滤镜
- 支持插帧模式功能，提升流畅度
- 支持 360°VR 全景视频
- 可视化调节均衡器
- Windows、macOS、Linux 全平台一致的强大右键菜单功能
- 轻量级，超简单，只需两个步骤即可完成享用
- [>>查看主题预览效果截图](https://github.com/akFace/mpv.config#%E9%A2%84%E8%A7%88%E6%95%88%E6%9E%9C%E5%9B%BE)
- [>>常见相关问题](https://github.com/akFace/mpv.config#一些常用设置文档可选)

## 使用方法

- 先安装播放器：**Windows：**[官方构建版本-推荐](https://github.com/mpv-player/mpv/releases)、[每日构建版本-推荐](https://github.com/zhongfly/mpv-winbuild/releases)、 [shinchiro 版本](https://github.com/shinchiro/mpv-winbuild-cmake/releases)、[mpv.net 版本](https://github.com/mpvnet-player/mpv.net/releases)。**MacOS、Linux ：**[mpv 官网下载](https://mpv.io/installation/)
- [🎯 点击下载](https://github.com/akFace/mpv.config/releases) 你想要的主题皮肤（每个压缩包都已包含完整功能的配置）`modernz`和`uosc`，并解压
- **以下案例以 Windows 系统为例： ① 和 ② 根据自己选择的播放器按对应教程来即可**
- **①. mpv 原生播放器**：解压/安装播放器后，在播放器根目录(`mpv.exe` 同目录)下新建名为 `portable_config` 文件夹，作为`配置文件夹`
- **②. mpv.net 播放器**：如图所示，右键>配置>打开配置文件夹或者`Ctrl + f`快捷键打开`配置文件夹`

  ![image](https://raw.githubusercontent.com/akFace/mpv.net.config/master/preview/Snipaste_2026-03-16_20-34-06.jpg)

- **将解压出的全部文件复制到`配置文件夹`(只能共存一个主题配置)，重启播放器即可**

- **注意目录结构**

```
一般的目录结构如下:
~/mpv/配置文件夹目录
      ├── fonts
      ├── scripts
      ├── script-opts
      ├── mpv.conf
      └── input.conf
```

- 一般 mpv 安装版`setup-install`（非 `Portable` 便携版）全局配置文件目录：

```
Linux:   ~/.config/mpv/
Windows: C:/Users/%username%/AppData/Roaming/mpv/
macOS:   ~/Library/Application Support/mpv/
```

> ⚠️ **提示**：若你使用的是 mpv.net 播放器，如果出现偶尔无法加载缩略图，请修改`script-opts/thumbfast.conf`目录中的`mpv_path=mpv`改为`mpv_path=mpvnet`或者播放器安装目录可执行文件 例如：`mpv_path=C:\Program Files\mpv.net\mpvnet.exe`
>
> - 其他平台可能会因为 [uosc_danmaku](https://github.com/Tony15246/uosc_danmaku/issues/194) 插件导致无法打开， [右键菜单故障排查文档](https://github.com/akFace/mpv-menu-plugin-next/blob/main/doc/README.md#%E5%89%AA%E8%B4%B4%E6%9D%BF)，请自查解决方案。

### **[👉 查看常用快捷键！推荐记住一些常用的即可](https://github.com/akFace/mpv.config/wiki/%E5%BF%AB%E6%8D%B7%E9%94%AE)**

### 一些常用设置&文档（可选）

- 弹幕默认样式在配置文件夹`script-opts/uosc_danmaku.conf`下，要修改请使用文本编辑器打开编辑
- 弹幕相关配置：[查看文档](https://github.com/Tony15246/uosc_danmaku#%E7%9B%AE%E5%BD%95)
- **关于弹幕流畅度问题**，目前本人的设备屏幕是 4k60hz，要打开`video-sync=display-resample`才流畅，但有些用户的设备打开此设置开倍速播放会导致声音卡问题，因此现在默认关闭，需要设置的请打开 mpv.conf 文件编辑，删除此行代码最前面的 # 号
- 跳过片头片尾：在配置文件夹中`mpv.conf`,打开编辑，可看到注释的跳过片头片尾，把注释的#号去掉，填写上自定义的片头片尾时间重启播放器即可
- 直接播放 B 站、YouTube 视频或其他链接：安装 [yt-dlp](https://github.com/yt-dlp/yt-dlp/releases) ，进入下载 yt-dlp.exe，放到 `mpv.exe` 同目录下，即：播放器安装目录。重启即可直接粘贴视频页面链接，不过更推荐下边的浏览器插件
- **推荐：** 油猴脚本 👉 [play-with-mpv 使用 mpv 播放网页中的视频](https://github.com/akFace/play-with-mpv)
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
![image](https://github.com/akFace/mpv.config/raw/master/preview/Snipaste_2026-08-16_01-04-38.jpg)
macos-dark：
![image](https://github.com/akFace/mpv.config/raw/master/preview/Snipaste_2026-08-16_01-10-14.jpg)

### 可视化均衡器 eq

![alt text](https://github.com/akFace/equalizer-gui/raw/main/images/Snipaste_2026-08-13_18-08-43.jpg)

## 相关链接

鸣谢以下开源项目提供的便利：

- [mpv](https://github.com/mpv-player/mpv)
- [mpv-winbuild](https://github.com/zhongfly/mpv-winbuild)
- [shinchiro](https://github.com/shinchiro/mpv-winbuild-cmake)
- [mpv.net](https://github.com/mpvnet-player/mpv.net)
- [Thumbfast](https://github.com/po5/thumbfast)
- [UOSC](https://github.com/tomasklaen/uosc)
- [ModernZ](https://github.com/Samillion/ModernZ)
- [mpv-sub-assrt](https://github.com/dyphire/mpv-sub-assrt)
- [uosc_danmaku](https://github.com/Tony15246/uosc_danmaku)
- [Anime4K](https://github.com/bloc97/Anime4K)
- [mpv360](https://github.com/kasper93/mpv360)
- [Equalizer-GUI](https://github.com/akFace/equalizer-gui)
- [mpv-menu-plugin-next](https://github.com/akFace/mpv-menu-plugin-next)
- [play-with-mpv](https://github.com/akFace/play-with-mpv)
- [recent-menu](https://github.com/natural-harmonia-gropius/recent-menu)
- [awesome-mpv](https://github.com/stax76/awesome-mpv)
- [mpv 中文配置手册](https://hooke007.github.io/official_man/index.html)
