const fs = require("fs-extra");
const path = require("path");
const { execSync } = require("child_process");
const { ZipArchive } = require("archiver");

// ---------- 配置 ----------
const BASE_SRC = "src"; // 所有源文件位于此目录
const SKINS = ["modernz", "uosc"];
const MENU_CONFIGS = [
  { suffix: "default", file: "menu-default.conf" },
  { suffix: "macos-white", file: "menu-macos-white.conf" },
  { suffix: "macos-dark", file: "menu-macos-dark.conf" },
];
const COMMON_DIR = path.join(BASE_SRC, "common");
const OUTPUT_DIR = "dist";
const ROOT_FILES = ["mpv.conf", "input.conf"]; // 这些文件也在 src 根目录下

// ---------- 获取版本号 ----------
function getVersion() {
  if (process.env.RELEASE_VERSION) {
    return process.env.RELEASE_VERSION;
  }
  try {
    const lastTag = execSync("git describe --tags --abbrev=0", {
      encoding: "utf8",
    }).trim();
    const versionNum = lastTag.replace(/^v/, "");
    const parts = versionNum.split(".");
    const majorMinor = parts.slice(0, 2).join(".");
    const patch = parseInt(parts[2] || "0", 10) + 1;
    return `v${majorMinor}.${patch}`;
  } catch {
    return "v1.0.0";
  }
}

// ---------- 打包函数 ----------
function createZip(sourceDir, zipPath) {
  return new Promise((resolve, reject) => {
    const output = fs.createWriteStream(zipPath);
    const archive = new ZipArchive({ zlib: { level: 9 } });

    output.on("close", resolve);
    archive.on("error", reject);

    archive.pipe(output);
    archive.directory(sourceDir, false);
    archive.finalize();
  });
}

// ---------- 主流程 ----------
async function build() {
  const version = getVersion();
  console.log(`📦 版本号: ${version}`);

  await fs.ensureDir(OUTPUT_DIR);
  await fs.emptyDir(OUTPUT_DIR);

  // 检查源目录是否存在
  if (!(await fs.pathExists(BASE_SRC))) {
    console.error(
      `❌ 源目录 "${BASE_SRC}" 不存在！请确保所有源文件已放入 src/ 目录。`
    );
    process.exit(1);
  }

  // 检查皮肤目录
  for (const skin of SKINS) {
    const skinPath = path.join(BASE_SRC, skin);
    if (!(await fs.pathExists(skinPath))) {
      console.error(`❌ 皮肤目录 "${skinPath}" 不存在！`);
      process.exit(1);
    }
  }

  for (const skin of SKINS) {
    for (const menu of MENU_CONFIGS) {
      const suffix = menu.suffix;
      const menuFile = path.join(BASE_SRC, menu.file); // 菜单配置也在 src 下

      if (!(await fs.pathExists(menuFile))) {
        console.warn(`⚠️  跳过 ${skin}_${suffix}：${menuFile} 不存在`);
        continue;
      }

      const tempDir = `temp_${skin}_${suffix}`;
      const skinSrc = path.join(BASE_SRC, skin);
      console.log(`🔄 处理 ${skin}_${suffix} ...`);

      try {
        // 1. 复制皮肤
        await fs.copy(skinSrc, tempDir);

        // 2. 合并 common
        if (await fs.pathExists(COMMON_DIR)) {
          await fs.copy(COMMON_DIR, tempDir, { overwrite: true });
        }

        // 3. 创建 script-opts
        const scriptOptsDir = path.join(tempDir, "script-opts");
        await fs.ensureDir(scriptOptsDir);

        // 4. 复制菜单配置
        await fs.copy(menuFile, path.join(scriptOptsDir, "menu_style.conf"), {
          overwrite: true,
        });

        // 5. 复制根目录的 mpv.conf 和 input.conf（现在也在 src 下）
        for (const file of ROOT_FILES) {
          const srcFile = path.join(BASE_SRC, file);
          if (await fs.pathExists(srcFile)) {
            await fs.copy(srcFile, path.join(tempDir, file), {
              overwrite: true,
            });
          } else {
            console.warn(`⚠️  源目录缺少 ${srcFile}，将跳过`);
          }
        }

        // 6. 写入 config-version
        await fs.writeFile(
          path.join(tempDir, "config-version"),
          version + "\n"
        );

        // 7. 打包
        const zipName = `${skin}_${suffix}.zip`;
        const zipPath = path.join(OUTPUT_DIR, zipName);
        await createZip(tempDir, zipPath);
        console.log(`✅ 生成 ${zipName}`);

        // 8. 清理
        await fs.remove(tempDir);
      } catch (err) {
        console.error(`❌ 处理 ${skin}_${suffix} 失败:`, err);
        await fs.remove(tempDir).catch(() => {});
        process.exit(1);
      }
    }
  }

  console.log(`🎉 所有压缩包已生成到 ${OUTPUT_DIR}/`);
}

build().catch((err) => {
  console.error("脚本执行出错:", err);
  process.exit(1);
});
