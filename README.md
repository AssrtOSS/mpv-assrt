mpv-assrt
=========

使用[assrt.net](http://assrt.net)匹配并下载字幕。

需要mpv **0.26.0** 及以上版本支持。

支持Windows, macOS和Linux。

<p align="center"> <img alt="mpv-assrt-screenshot" src="https://wx1.sinaimg.cn/large/436919cbgy1fo7fcq8s3jg20go0b4u0x.gif"/> </p>

## 使用说明

1. 下载[zip压缩包](https://github.com/AssrtOSS/mpv-assrt/archive/master.zip)或`git clone`本项目
2. 解压压缩包
3. 将`scripts`和`script-settings`文件夹复制到mpv主目录中。Windows用户的mpv主目录位于与`mpv.exe`同目录的`mpv`文件夹；Linux和macOS用户的mpv主目录位于`~/.config/mpv`。
4. 打开视频后，按<kbd>a</kbd>键调起搜索字幕。

## 快捷键

如需自定义快捷键，可以在`input.conf`中添加下列行，如更改快捷键为<kbd>Ctrl</kbd>+<kbd>a</kbd>：

    ctrl-a script-binding assrt

`input.conf`位于mpv主目录下，如果该文件不存在，请创建一个空白的文件。

## 配置文件

如需自定义配置，请将`script-settings`中的**assrt.conf.example**更名为**assrt.conf**。

```conf
# 菜单外观
## 设置多少秒后自动关闭菜单，设为0时不关闭
auto_close=0
## 设置每页显示字幕条数
max_lines=15
## 设置菜单字体大小
font_size=24

# 设置是否使用https
use_https=no

# 自定义API Token
# api_token=
```

如需自定义API Token，可以在网站上注册后从[用户面板](https://secure.assrt.net/usercp.php)中获得。

## 依赖库

- [SteveJobzniak's Modules.js](https://github.com/SteveJobzniak/mpv-tools/tree/master/scripts/modules.js)
