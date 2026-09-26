const fs = require("fs-extra");
const path = require("path");
const { execSync } = require("child_process");
const { ZipArchive } = require("archiver");

// ---------- 配置 ----------
const BASE_SRC = "src";
const SKINS = ["modernz", "uosc"];

/**
 * MENU_CONFIGS 说明：
 *   - suffix:          打包产物的后缀（<skin>_<suffix>.zip）
 *   - file:            src 根目录下的菜单样式文件
 *   - renameSkinConf:  若为 true，则把
 *                      src/<skin>/script-opts/<skin>-<suffix>.conf
 *                      复制为 script-opts/<skin>.conf
 *
 * 不论 renameSkinConf 是否为 true，打包前都会清理
 * 临时目录 script-opts/ 下所有 <skin>-*.conf 变体文件，
 * 只保留 <skin>.conf（以及其它不属于变体命名规则的文件）。
 */
const MENU_CONFIGS = [
  { suffix: "default", file: "menu-default.conf" },
  {
    suffix: "macos-white",
    file: "menu-macos-white.conf",
    renameSkinConf: true,
  },
  { suffix: "macos-dark", file: "menu-macos-dark.conf", renameSkinConf: true },
  { suffix: "cyan-blue", file: "menu-cyan-blue.conf", renameSkinConf: true },
  // { suffix: "purple", file: "menu-purple.conf", renameSkinConf: true },
];

const COMMON_DIR = path.join(BASE_SRC, "common");
const OUTPUT_DIR = "dist";
const ROOT_FILES = ["mpv.conf", "input.conf"];

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

// ---------- 清理 script-opts 中的 <skin>-*.conf 变体 ----------
async function cleanSkinVariantConfs(scriptOptsDir, skin) {
  if (!(await fs.pathExists(scriptOptsDir))) return;

  const prefix = `${skin}-`;
  const entries = await fs.readdir(scriptOptsDir);

  for (const name of entries) {
    if (name.startsWith(prefix) && name.endsWith(".conf")) {
      await fs.remove(path.join(scriptOptsDir, name));
      console.log(`   🗑️  移除临时目录中的 ${name}`);
    }
  }
}

// ---------- 主流程 ----------
async function build() {
  const version = getVersion();
  console.log(`📦 版本号: ${version}`);

  await fs.ensureDir(OUTPUT_DIR);
  await fs.emptyDir(OUTPUT_DIR);

  if (!(await fs.pathExists(BASE_SRC))) {
    console.error(
      `❌ 源目录 "${BASE_SRC}" 不存在！请确保所有源文件已放入 src/ 目录。`
    );
    process.exit(1);
  }

  for (const skin of SKINS) {
    const skinPath = path.join(BASE_SRC, skin);
    if (!(await fs.pathExists(skinPath))) {
      console.error(`❌ 皮肤目录 "${skinPath}" 不存在！`);
      process.exit(1);
    }
  }

  for (const skin of SKINS) {
    for (const menu of MENU_CONFIGS) {
      const { suffix, file: menuFileName, renameSkinConf } = menu;
      const menuFile = path.join(BASE_SRC, menuFileName);

      if (!(await fs.pathExists(menuFile))) {
        console.warn(`⚠️  跳过 ${skin}_${suffix}：${menuFile} 不存在`);
        continue;
      }

      const tempDir = `temp_${skin}_${suffix}`;
      const skinSrc = path.join(BASE_SRC, skin);
      console.log(`🔄 处理 ${skin}_${suffix} ...`);

      try {
        // 1. 复制皮肤（会连带 script-opts/ 下的 <skin>-*.conf 变体一起复制过来）
        await fs.copy(skinSrc, tempDir);

        // 2. 合并 common
        if (await fs.pathExists(COMMON_DIR)) {
          await fs.copy(COMMON_DIR, tempDir, { overwrite: true });
        }

        // 3. 确保 script-opts 目录存在
        const scriptOptsDir = path.join(tempDir, "script-opts");
        await fs.ensureDir(scriptOptsDir);

        // 4. 复制菜单样式
        await fs.copy(menuFile, path.join(scriptOptsDir, "menu_style.conf"), {
          overwrite: true,
        });

        // 5. 若需要，从 src 源目录把 <skin>-<suffix>.conf 复制为 <skin>.conf
        //    注意：源文件从 src 读取，避免后续清理时被误删
        if (renameSkinConf) {
          const skinConfName = `${skin}-${suffix}.conf`;
          const srcSkinConf = path.join(
            BASE_SRC,
            skin,
            "script-opts",
            skinConfName
          );
          const destSkinConf = path.join(scriptOptsDir, `${skin}.conf`);

          if (await fs.pathExists(srcSkinConf)) {
            await fs.copy(srcSkinConf, destSkinConf, { overwrite: true });
            console.log(`   🔄 ${skinConfName} → ${skin}.conf`);
          } else {
            console.warn(
              `   ⚠️  未找到 ${srcSkinConf}，跳过 ${skin}.conf 重命名`
            );
          }
        }

        // 6. 无条件清理临时目录中所有 <skin>-*.conf 变体文件
        //    （modernz.conf / uosc.conf 不匹配 <skin>- 前缀，会被保留）
        await cleanSkinVariantConfs(scriptOptsDir, skin);

        // 7. 复制根目录的 mpv.conf 和 input.conf
        for (const f of ROOT_FILES) {
          const srcFile = path.join(BASE_SRC, f);
          if (await fs.pathExists(srcFile)) {
            await fs.copy(srcFile, path.join(tempDir, f), {
              overwrite: true,
            });
          } else {
            console.warn(`⚠️  源目录缺少 ${srcFile}，将跳过`);
          }
        }

        // 8. 写入 config-version
        await fs.writeFile(
          path.join(tempDir, "config-version"),
          version + "\n"
        );

        // 9. 打包
        const zipName = `${skin}_${suffix}.zip`;
        const zipPath = path.join(OUTPUT_DIR, zipName);
        await createZip(tempDir, zipPath);
        console.log(`✅ 生成 ${zipName}`);

        // 10. 清理
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
