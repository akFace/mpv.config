# Ready-to-Use Configuration Files, Elegant UI Themes & Useful Plugins for mpv and mpv.net (Windows, macOS, Linux)

> The configuration file of the mpv player supports Windows, macOS, Linux, with a consistent context menu feature across all platforms.

#### [中文](https://github.com/akFace/mpv.config/blob/main/README.md) | English

- Note: This document was translated by `AI-translated` and may contain some inaccuracies.

## Overview

- Two themes, `modernz` and `uosc`, featuring a beautiful modern UI with a borderless design
- Uses the native mpv player with configuration and player kept separate, so you do not need to worry about the player being unable to update to the latest version
- Integrated thumbnail previews on the progress bar
- Integrated online Chinese subtitle search
- Supports online loading of danmaku from across the web
- Integrated Anime4K upscaling for real-time image quality enhancement
- Supports multiple video shader filters：[shaders](https://github.com/akFace/mpv.config/wiki/Shader---Video-Filter-Selection-Guide)
- Video filters (Anime4K, FSRCNNX, CuNNy, ArtCNN, etc.) can be loaded on demand via the right-click menu.
- Supports frame interpolation mode for smoother playback
- Supports 360° VR panoramic videos
- Visual equalizer controls, Audio channel switch, Automatic HDR, Decoding switching, and Color grading...
- Switch theme color schemes in real-time
- Powerful and consistent context menu functionality across Windows, macOS, and Linux
- Lightweight and extremely simple, with just two steps to get started

## Installation

### 1. Install the Player

- **Windows:**
  - [Official Builds (Recommended)](https://github.com/mpv-player/mpv/releases)
  - [Daily Builds (Recommended)](https://github.com/zhongfly/mpv-winbuild/releases)
  - [shinchiro Builds](https://github.com/shinchiro/mpv-winbuild-cmake/releases)
  - [mpv.net Builds](https://github.com/mpvnet-player/mpv.net/releases)
- **macOS, Linux:** [Download from the official mpv website](https://mpv.io/installation/)

### 2. Download the Theme Configuration

[🎯 Click to Download](https://github.com/akFace/mpv.config/releases) the theme you need. The following themes are currently available: `xxx_en.zip` version

- `modernz`
- `uosc`

Each theme archive contains a complete, fully functional configuration. Simply download and extract it.

### 3. Configure the Player

- **The following example uses Windows:**
- After extracting/installing the player, create a new folder named `portable_config` in the player's root directory (the same directory as `mpv.exe`). This will be used as the `configuration folder`.
- **Copy all extracted files into the `configuration folder` (only one theme configuration can be used at a time), then restart the player.**

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

macOS、Linux 、Windows， The global configuration directories are:

```
macOS:   ~/Library/Application Support/mpv/
Linux:   ~/.config/mpv/
Windows: C:/Users/%username%/AppData/Roaming/mpv/
```

> ⚠️ **Tip**: If you are using the mpv.net player and thumbnails occasionally fail to load, change `mpv_path=mpv` in `script-opts/thumbfast.conf` to `mpv_path=mpvnet`, or specify the executable in the player installation directory, for example: `mpv_path=C:\Program Files\mpv.net\mpvnet.exe`
>
> - The procedure is the same for macOS and Linux users: simply place the extracted files into the **_`configuration folder`_** and restart the player.

### **[👉 View common keyboard shortcuts! ](https://github.com/akFace/mpv.config/wiki/%E5%BF%AB%E6%8D%B7%E9%94%AE)**

### Common Settings & Documentation (Optional)

- Uosc Theme Options：[Uosc](https://github.com/tomasklaen/uosc#options)
- ModernZ Theme Options：[ModernZ](https://github.com/Samillion/ModernZ#customization)
- The default danmaku style is configured in `script-opts/uosc_danmaku.conf`. To modify it, open the file with a text editor.
- Danmaku-related configuration: [View the documentation](https://github.com/Tony15246/uosc_danmaku#%E7%9B%AE%E5%BD%95)
- **Recommended:** Tampermonkey script 👉 [play-with-mpv - Play videos from web pages with mpv](https://github.com/akFace/play-with-mpv)

## How to Update to the Latest Version

- Player update: Simply download and install the latest [mpv player](https://mpv.io/) or [🎬 mpv.net player](https://github.com/mpvnet-player/mpv.net/releases).
- Configuration/theme update: Simply [🎯 download the latest version](https://github.com/akFace/mpv.config/releases), extract it, and overwrite the existing files. (Back up your files before overwriting)
- How can I customize the configuration ( mpv.conf ) and keybindings menus ( input.conf ) so that they remain unaffected when overwriting files during a version update? 📢 [View more >>](https://github.com/akFace/mpv.config/wiki/Customize-the-mpv.conf-&-input.conf)

## Preview

![image](https://raw.githubusercontent.com/akFace/mpv.net.config/main/preview/Snipaste_2026-09-02_22-25-41.jpg)
![image](https://raw.githubusercontent.com/akFace/mpv.net.config/main/preview/Snipaste_2026-09-02_22-31-00.jpg)

## Open-source project

See also:

- [equalizer-gui](https://github.com/akFace/equalizer-gui)
- [mpv-menu-plugin-next](https://github.com/akFace/mpv-menu-plugin-next)
- [switch-opts](./src/common/scripts/switch-opts.lua)
- [interp_switch](./src/common/scripts/interp_switch.lua)
- [merge-input](./src/common/scripts/merge-input.lua)
- [play-with-mpv](https://github.com/akFace/play-with-mpv)
- [scheme-handler-cross](https://github.com/akFace/scheme-handler-cross)

---

Thanks to the following open-source projects for making this possible:

- [mpv](https://github.com/mpv-player/mpv)
- [thumbfast](https://github.com/po5/thumbfast)
- [celebi](https://github.com/po5/celebi)
- [uosc](https://github.com/tomasklaen/uosc)
- [ModernZ](https://github.com/Samillion/ModernZ)
- [mpv-sub-assrt](https://github.com/dyphire/mpv-sub-assrt)
- [uosc_danmaku](https://github.com/Tony15246/uosc_danmaku)
- [Anime4K](https://github.com/bloc97/Anime4K)
- [CuNNy](https://github.com/funnyplanter/CuNNy)
- [ArtCNN](https://github.com/Artoriuz/ArtCNN)
- [mpv360](https://github.com/kasper93/mpv360)
- [recent-menu](https://github.com/natural-harmonia-gropius/recent-menu)
- [awesome-mpv](https://github.com/stax76/awesome-mpv)
- [mpv_PlayKit](https://github.com/hooke007/mpv_PlayKit)
- [mpv guide](https://hooke007.github.io/official_man/index.html)
