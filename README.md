# Young Homer 简体中文补丁

《Young Homer: A Storyteller's Odyssey》简体中文补丁 v1.0.0，覆盖 599 条运行时文本和 3 张含文字图片。

## 下载与安装

下载 [`dist/Young-Homer-Chinese-Patch-v1.0.0.zip`](dist/Young-Homer-Chinese-Patch-v1.0.0.zip)，完整解压到游戏根目录（与 `data.win`、`younghomer.exe` 同级），双击 `安装汉化.cmd`。卸载时双击 `卸载汉化.cmd`。

补丁仅支持游戏 `2.0.0.1`，安装前会校验原文件，失败时不会修改游戏。安装器不联网、不修改注册表，也不写入游戏目录以外的位置。

## 开发

仓库不包含游戏本体、原版文本、反编译代码、图片或完整 `data.win`。要重新构建：

1. 将仓库放在游戏根目录的一个子目录中。
2. 从 [UndertaleModTool 官方 Releases](https://github.com/UnderminersTeam/UndertaleModTool/releases) 获取 `UTMT_CLI v0.9.2.0`，解压到 `tools/utmt/`。
3. 依次运行：

```powershell
pwsh -NoProfile -File .\tools\scripts\Refresh-Materials.ps1
pwsh -NoProfile -File .\tools\scripts\Build-ChinesePatch.ps1
```

`Refresh-Materials.ps1` 从开发者自备的 `data.win` 生成临时材料并套用 `materials/text/manual_translations.tsv`；`Build-ChinesePatch.ps1` 校验译文、图片、字体和目标文件后生成发布包。临时材料与工具副本均由 `.gitignore` 排除。

## 仓库内容

- `materials/text/manual_translations.tsv`：原创简体中文译文。
- `materials/fonts/source/`：Fusion Pixel 字体及 SIL Open Font License。
- `tools/scripts/`：材料提取、校验、字体生成和打包脚本。
- `packaging/`：安装与卸载入口源码。
- `dist/`：可直接分发的版本化补丁包。

游戏及其素材版权归原作者所有。本项目与游戏原作者无隶属关系；仓库中的脚本按 [MIT License](LICENSE) 发布。
