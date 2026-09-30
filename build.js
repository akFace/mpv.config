const fs = require("fs-extra");
const path = require("path");
const { execSync } = require("child_process");
const { ZipArchive } = require("archiver");

// ---------- 配置 ----------
const BASE_SRC = "src";
const SKINS = ["modernz", "uosc"];

/**
 * INPUT_CONFIGS 说明：
 *   - suffix:  打包产物的后缀（<skin>_<suffix>.zip）
 *   - file:    src 根目录下的 input 配置文件
 *   - mpvConf: 可选。若非空，则插入到 mpv.conf 文件最前面
 *
 * 每个变体会把对应的 input 配置文件复制到打包临时目录根，
 * 并重命名为 input.conf，与 mpv.conf 处于同一目录。
 */
const INPUT_CONFIGS = [
  // 默认中文版
  { suffix: "zh", file: "input.conf" },
  // 英文版
  {
    suffix: "en",
    file: "input-en.conf",
    mpvConf: "script-opts = modernz-language=en,uosc-languages=en",
  },
  // 按需继续添加，例如：
  // {
  //   suffix: "jp",
  //   file: "input-jp.conf",
  //   mpvConf: "script-opts = modernz-language=jp,uosc-languages=jp",
  // }
];

const COMMON_DIR = path.join(BASE_SRC, "common");
const OUTPUT_DIR = "dist";
// input.conf 已由 INPUT_CONFIGS 处理，这里只保留其它根文件
const ROOT_FILES = ["mpv.conf"];

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
    for (const inputCfg of INPUT_CONFIGS) {
      const { suffix, file: inputFileName, mpvConf } = inputCfg;
      const inputFile = path.join(BASE_SRC, inputFileName);

      if (!(await fs.pathExists(inputFile))) {
        console.warn(`⚠️  跳过 ${skin}_${suffix}：${inputFile} 不存在`);
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

        // 3. 复制 input 配置，并重命名为 input.conf
        //    与 mpv.conf 同目录（临时目录根）
        await fs.copy(inputFile, path.join(tempDir, "input.conf"), {
          overwrite: true,
        });
        console.log(`   🔄 ${inputFileName} → input.conf`);

        // 4. 处理根目录的其它配置文件（mpv.conf 等）
        //    对 mpv.conf 特殊处理：若当前变体带 mpvConf 字段，
        //    读取原文件后把该内容插到最前面。
        for (const f of ROOT_FILES) {
          const srcFile = path.join(BASE_SRC, f);
          const destFile = path.join(tempDir, f);

          if (!(await fs.pathExists(srcFile))) {
            console.warn(`⚠️  源目录缺少 ${srcFile}，将跳过`);
            continue;
          }

          if (f === "mpv.conf" && mpvConf) {
            const original = await fs.readFile(srcFile, "utf8");
            const merged = mpvConf + "\n" + original;
            await fs.writeFile(destFile, merged);
            console.log(`   🔄 在 mpv.conf 最前面插入: ${mpvConf}`);
          } else {
            await fs.copy(srcFile, destFile, { overwrite: true });
          }
        }

        // 5. 写入 config-version
        await fs.writeFile(
          path.join(tempDir, "config-version"),
          version + "\n"
        );

        // 6. 打包
        const zipName = `${skin}_${suffix}.zip`;
        const zipPath = path.join(OUTPUT_DIR, zipName);
        await createZip(tempDir, zipPath);
        console.log(`✅ 生成 ${zipName}`);

        // 7. 清理
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
