const fs = require("fs-extra");
const path = require("path");
const { execSync } = require("child_process");
const { ZipArchive } = require("archiver");

// ---------- 配置 ----------
const SKINS = ["modernz", "uosc"];
const MENU_CONFIGS = [
  { suffix: "default", file: "menu-default.conf" },
  { suffix: "macos-white", file: "menu-macos-white.conf" },
  { suffix: "macos-dark", file: "menu-macos-dark.conf" },
];
const COMMON_DIR = "common";
const OUTPUT_DIR = "dist";
const ROOT_FILES = ["mpv.conf", "input.conf"];

// ---------- 获取版本号 ----------
function getVersion() {
  // 优先使用环境变量
  if (process.env.RELEASE_VERSION) {
    return process.env.RELEASE_VERSION;
  }
  // 本地开发：从 Git tag 自动递增
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

  // 检查皮肤目录
  for (const skin of SKINS) {
    if (!(await fs.pathExists(skin))) {
      console.error(`❌ 皮肤目录 "${skin}" 不存在！`);
      process.exit(1);
    }
  }

  for (const skin of SKINS) {
    for (const menu of MENU_CONFIGS) {
      const suffix = menu.suffix;
      const menuFile = menu.file;

      if (!(await fs.pathExists(menuFile))) {
        console.warn(`⚠️  跳过 ${skin}_${suffix}：${menuFile} 不存在`);
        continue;
      }

      const tempDir = `temp_${skin}_${suffix}`;
      console.log(`🔄 处理 ${skin}_${suffix} ...`);

      try {
        // 1. 复制皮肤
        await fs.copy(skin, tempDir);

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

        // 5. 复制根目录配置文件
        for (const file of ROOT_FILES) {
          const src = path.join(".", file);
          if (await fs.pathExists(src)) {
            await fs.copy(src, path.join(tempDir, file), { overwrite: true });
          } else {
            console.warn(`⚠️  根目录缺少 ${file}，将跳过`);
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
