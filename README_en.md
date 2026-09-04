# Ready-to-Use Configuration Files, Elegant UI Themes & Useful Plugins for mpv and mpv.net (Windows, macOS, Linux)

> The configuration file of the mpv player supports Windows, macOS, Linux, with a consistent context menu feature across all platforms.

#### [中文](https://github.com/akFace/mpv.config/blob/master/README.md) | English

- Note: This document was translated by `AI-translated` and may contain some inaccuracies.

## Overview

- Two themes, `modernz` and `uosc`, featuring a beautiful modern UI with a borderless design
- Uses the native mpv player with configuration and player kept separate, so you do not need to worry about the player being unable to update to the latest version
- Integrated thumbnail previews on the progress bar
- Integrated online Chinese subtitle search
- Supports online loading of danmaku from across the web
- Integrated Anime4K upscaling for real-time image quality enhancement
- Supports multiple video shader filters：[shaders](https://github.com/akFace/mpv.config/tree/master/src/common/shaders)
- Supports frame interpolation mode for smoother playback
- Supports 360° VR panoramic videos
- Visual equalizer controls, Audio channel switch, Automatic HDR, Decoding switching, and Color grading...
- Powerful and consistent context menu functionality across Windows, macOS, and Linux
- Lightweight and extremely simple, with just two steps to get started

## Installation

- First, install a player: **Windows:** [Official builds - Recommended](https://github.com/mpv-player/mpv/releases), [Daily builds - Recommended](https://github.com/zhongfly/mpv-winbuild/releases), [shinchiro builds](https://github.com/shinchiro/mpv-winbuild-cmake/releases), or [mpv.net builds](https://github.com/mpvnet-player/mpv.net/releases). **macOS, Linux:** [Download mpv from the official website](https://mpv.io/installation/)
- [🎯 Click here to download](https://github.com/akFace/mpv.config/releases) the theme you want (`modernz` or `uosc`). Each archive already contains a complete functional configuration. Extract it after downloading.
- **The following example uses Windows: ① and ② correspond to the player you choose; follow the relevant instructions.**
- **①. Official mpv player**: After extracting/installing the player, create a folder named `portable_config` in the player root directory (the same directory as `mpv.exe`) and use it as the `configuration folder`.
- **②. mpv.net player**: right-click > Configuration > Open Configuration Folder, or press `Ctrl + f` to open the `configuration folder`.

- **Copy all extracted files into the `configuration folder` (only one theme configuration can be used at a time)**

- **Language:** The language setting for the ModernZ theme is located in `script-opts/modernz.conf`, while the language setting for the UOSC theme is located in `script-opts/uosc.conf`. To change the language, search for the keyword `language` in the corresponding file. Download [`input-en.conf`](https://github.com/akFace/mpv.config/blob/master/src/input-en.conf), rename it to `input.conf`, and replace the original `input.conf` file with it, then restart the player.

- **Note the directory structure**

```
A typical directory structure looks like this:
~/mpv/configuration folder
      ├── fonts
      ├── scripts
      ├── script-opts
      ├── mpv.conf
      └── input.conf
```

For standard mpv installations using `setup-install` (not the `Portable` version), the global configuration directories are:

```
Linux:   ~/.config/mpv/
Windows: C:/Users/%username%/AppData/Roaming/mpv/
macOS:   ~/Library/Application Support/mpv/
```

> ⚠️ **Tip**: If you are using the mpv.net player and thumbnails occasionally fail to load, change `mpv_path=mpv` in `script-opts/thumbfast.conf` to `mpv_path=mpvnet`, or specify the executable in the player installation directory, for example: `mpv_path=C:\Program Files\mpv.net\mpvnet.exe`
>
> - On other platforms, the [uosc_danmaku](https://github.com/Tony15246/uosc_danmaku/issues/194) plugin may sometimes prevent the player from opening. See the [context menu troubleshooting guide](https://github.com/akFace/mpv-menu-plugin-next/blob/main/doc/README.md#linux) and check for a solution.

### **[👉 View common keyboard shortcuts! It is recommended to remember the most useful ones](https://github.com/akFace/mpv.config/wiki/%E5%BF%AB%E6%8D%B7%E9%94%AE)**

### Common Settings & Documentation (Optional)

- Uosc Theme Options：[Uosc](https://github.com/tomasklaen/uosc#options)
- ModernZ Theme Options：[ModernZ](https://github.com/Samillion/ModernZ#customization)
- The default danmaku style is configured in `script-opts/uosc_danmaku.conf`. To modify it, open the file with a text editor.
- Danmaku-related configuration: [View the documentation](https://github.com/Tony15246/uosc_danmaku#%E7%9B%AE%E5%BD%95)
- Skip intros and outros: Open `mpv.conf` in the configuration folder. You will find commented-out settings for skipping intros and outros. Remove the `#` symbols and enter your custom intro/outro times, then restart the player.
- **Recommended:** Tampermonkey script 👉 [play-with-mpv - Play videos from web pages with mpv](https://github.com/akFace/play-with-mpv)

## How to Update to the Latest Version

- Player update: Simply download and install the latest [🎬 mpv.net player](https://github.com/mpvnet-player/mpv.net/releases) or [mpv player](https://mpv.io/).
- Configuration/theme update: Simply [🎯 download the latest version](https://github.com/akFace/mpv.config/releases), extract it, and overwrite the existing files. (Back up your files before overwriting)

## Preview

![image](https://raw.githubusercontent.com/akFace/mpv.net.config/master/preview/Snipaste_2026-09-02_22-25-41.jpg)
![image](https://raw.githubusercontent.com/akFace/mpv.net.config/master/preview/Snipaste_2026-09-02_22-31-00.jpg)

## Open-source project

Thanks to the following open-source projects for making this possible:

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
- [mpv Chinese Configuration Manual](https://hooke007.github.io/official_man/index.html)
