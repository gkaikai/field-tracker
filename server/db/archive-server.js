#!/usr/bin/env node
/**
 * Field Tracker — 服务端编译归档脚本
 *
 * 将当前 dist/ 目录打包为版本化归档，存放在 releases/ 中。
 * 配合 git tag 使用，确保每个发布的编译产物都有备份。
 *
 * 用法:
 *   node archive-server.js               # 自动读取当前版本号并归档
 *   node archive-server.js v1.0.47       # 指定版本标签
 *   node archive-server.js list          # 列出所有归档
 *   node archive-server.js restore v1.0.45  # 快速恢复指定版本到 dist/
 */

const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

const ROOT_DIR = path.resolve(__dirname, '..');
const DIST_DIR = path.join(ROOT_DIR, 'dist');
const RELEASES_DIR = path.resolve(__dirname, '../../releases');
const PACKAGE_JSON = path.join(ROOT_DIR, 'package.json');

function getPackageVersion() {
  const pkg = JSON.parse(fs.readFileSync(PACKAGE_JSON, 'utf-8'));
  return pkg.version || '0.0.0';
}

function getGitTag() {
  try {
    const tag = execSync('git describe --tags --abbrev=0 2>/dev/null', { cwd: ROOT_DIR })
      .toString().trim();
    return tag || `v${getPackageVersion()}`;
  } catch {
    return `v${getPackageVersion()}`;
  }
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function archive(version) {
  if (!fs.existsSync(DIST_DIR)) {
    console.error('❌ dist/ 目录不存在，请先运行 npm run build');
    process.exit(1);
  }

  ensureDir(RELEASES_DIR);
  const tag = version || getGitTag();
  const archiveName = `server-dist-${tag}.tar.gz`;
  const archivePath = path.join(RELEASES_DIR, archiveName);

  // 已经存在则跳过
  if (fs.existsSync(archivePath)) {
    console.log(`⚠️  归档已存在: ${archiveName}`);
    return archivePath;
  }

  console.log(`📦 归档服务端编译产物: ${archiveName}`);
  execSync(
    `cd "${ROOT_DIR}" && tar -czf "${archivePath}" dist/ package.json node_modules/.package-lock.json 2>/dev/null || tar -czf "${archivePath}" dist/ package.json`,
    { stdio: 'inherit', cwd: ROOT_DIR }
  );
  
  const size = (fs.statSync(archivePath).size / 1024 / 1024).toFixed(1);
  console.log(`✅ 归档完成: ${archivePath} (${size}MB)`);
  return archivePath;
}

function listArchives() {
  ensureDir(RELEASES_DIR);
  const files = fs.readdirSync(RELEASES_DIR)
    .filter(f => f.startsWith('server-dist-') && f.endsWith('.tar.gz'))
    .sort()
    .reverse();

  if (files.length === 0) {
    console.log('📂 没有找到服务端归档');
    return;
  }

  console.log(`\n📂 releases/ 中的服务端归档 (${files.length} 个):\n`);
  files.forEach(f => {
    const stat = fs.statSync(path.join(RELEASES_DIR, f));
    const size = (stat.size / 1024 / 1024).toFixed(1);
    const time = stat.mtime.toISOString().substring(0, 19);
    console.log(`  ${f.padEnd(55)} ${size.padStart(5)}MB  ${time}`);
  });
  console.log();
}

function restore(version) {
  const tag = version || getGitTag();
  const archiveName = `server-dist-${tag}.tar.gz`;
  const archivePath = path.join(RELEASES_DIR, archiveName);

  if (!fs.existsSync(archivePath)) {
    console.error(`❌ 归档不存在: ${archiveName}`);
    console.error(`   可用: node archive-server.js list`);
    process.exit(1);
  }

  // 备份当前 dist（带时间戳，保留多代）
  if (fs.existsSync(DIST_DIR)) {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const backupDir = path.join(ROOT_DIR, `dist.bak.${timestamp}`);
    fs.renameSync(DIST_DIR, backupDir);
    console.log(`📦 已备份当前 dist/ → dist.bak.${timestamp}/`);
  }

  console.log(`♻️  恢复归档: ${archiveName}`);
  execSync(`tar -xzf "${archivePath}" -C "${ROOT_DIR}"`, { stdio: 'inherit' });
  console.log(`✅ 恢复完成，请重启服务: npm start`);
}

function main() {
  const args = process.argv.slice(2);
  const command = args[0];

  if (command === 'list') {
    listArchives();
    return;
  }

  if (command === 'restore') {
    restore(args[1]);
    return;
  }

  const tag = command || getGitTag();
  archive(tag);
}

main();
