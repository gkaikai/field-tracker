#!/usr/bin/env node
/**
 * Field Tracker — 数据库迁移运行器
 *
 * 管理数据库模式变更的上线（up）与回滚（down）。
 *
 * 用法:
 *   node migrate.js up          # 执行所有待处理的迁移
 *   node migrate.js up 2        # 执行接下来 2 个迁移
 *   node migrate.js down        # 回滚最近 1 个迁移
 *   node migrate.js down 3      # 回滚最近 3 个迁移
 *   node migrate.js status      # 查看迁移状态
 *   node migrate.js baseline    # 将当前数据库标记为基线（不执行任何SQL）
 *
 * 迁移文件格式:
 *   migrations/
 *     <序号>_<描述>.up.sql     # 正向变更
 *     <序号>_<描述>.down.sql   # 反向回退
 *
 * 示例:
 *   migrations/
 *     001_initial_schema.up.sql
 *     001_initial_schema.down.sql
 *     002_add_accuracy_column.up.sql
 *     002_add_accuracy_column.down.sql
 */

const { Pool } = require('pg');
const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const MIGRATIONS_DIR = path.join(__dirname, 'migrations');
// Pool 在 getPool() 中懒加载（避免 .env 缺失时模块级崩溃）

// ── 辅助函数 ──────────────────────────────────────────────

/** 获取数据库连接池（懒加载） */
let _pool = null;
function getPool() {
  if (!_pool) {
    _pool = new Pool({
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT || '5432'),
      database: process.env.DB_NAME || 'field_tracker',
      user: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD || '',
    });
  }
  return _pool;
}

async function query(text, params) {
  const client = await getPool().connect();
  try {
    return await client.query(text, params);
  } finally {
    client.release();
  }
}

/** 确保 _migrations 跟踪表存在 */
async function ensureMigrationTable() {
  await query(`
    CREATE TABLE IF NOT EXISTS _migrations (
      id          SERIAL PRIMARY KEY,
      version     VARCHAR(255) NOT NULL UNIQUE,
      name        VARCHAR(255) NOT NULL,
      applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      checksum    VARCHAR(64) NOT NULL,
      duration_ms INT NOT NULL DEFAULT 0
    );
  `);
}

/** 获取已应用的迁移列表 */
async function getAppliedMigrations() {
  const result = await query(
    'SELECT version, name, applied_at, checksum FROM _migrations ORDER BY id'
  );
  return result.rows;
}

/** 扫描迁移目录，获取所有迁移文件 */
function scanMigrations() {
  if (!fs.existsSync(MIGRATIONS_DIR)) {
    fs.mkdirSync(MIGRATIONS_DIR, { recursive: true });
    return [];
  }

  const files = fs.readdirSync(MIGRATIONS_DIR);
  const upFiles = files.filter(f => f.endsWith('.up.sql')).sort();
  
  const migrations = upFiles.map(f => {
    const match = f.match(/^(\d+)_(.+)\.up\.sql$/);
    if (!match) return null;
    const version = match[1];
    const name = match[2];
    const downFile = `${version}_${name}.down.sql`;
    // 使用 crypto 计算 SHA256
    const crypto = require('crypto');
    const upContent = fs.readFileSync(path.join(MIGRATIONS_DIR, f), 'utf-8');
    const checksum = crypto.createHash('sha256').update(upContent).digest('hex');
    
    return {
      version,
      name,
      upFile: f,
      downFile: files.includes(downFile) ? downFile : null,
      upContent,
      checksum,
    };
  }).filter(Boolean);

  return migrations;
}

/** 执行单个迁移（正向） */
async function applyMigration(migration) {
  console.log(`\n  ▶ 应用迁移 ${migration.version}_${migration.name}...`);
  
  const startMs = Date.now();
  
  // 在事务中执行
  const client = await getPool().connect();
  try {
    await client.query('BEGIN');
    
    // 执行 SQL
    await client.query(migration.upContent);
    
    // 记录迁移（在事务内直接写入 duration）
    const elapsed = Date.now() - startMs;
    await client.query(
      `INSERT INTO _migrations (version, name, checksum, duration_ms)
       VALUES ($1, $2, $3, $4)`,
      [migration.version, migration.name, migration.checksum, elapsed]
    );
    
    await client.query('COMMIT');
    
    console.log(`  ✅ 完成 (${elapsed}ms)`);
  } catch (e) {
    await client.query('ROLLBACK');
    console.error(`  ❌ 失败: ${e.message}`);
    throw e;
  } finally {
    client.release();
  }
}

/** 回滚单个迁移 */
async function rollbackMigration(migration) {
  if (!migration.downFile) {
    console.error(`  ❌ 迁移 ${migration.version} 没有对应的 .down.sql 文件，无法回滚`);
    return false;
  }
  
  console.log(`\n  ◀ 回滚迁移 ${migration.version}_${migration.name}...`);
  
  const downContent = fs.readFileSync(
    path.join(MIGRATIONS_DIR, migration.downFile), 'utf-8'
  );
  
  const start = Date.now();
  const client = await getPool().connect();
  try {
    await client.query('BEGIN');
    await client.query(downContent);
    await client.query(
      'DELETE FROM _migrations WHERE version = $1',
      [migration.version]
    );
    await client.query('COMMIT');
    const elapsed = Date.now() - start;
    console.log(`  ✅ 回滚完成 (${elapsed}ms)`);
    return true;
  } catch (e) {
    await client.query('ROLLBACK');
    console.error(`  ❌ 回滚失败: ${e.message}`);
    throw e;
  } finally {
    client.release();
  }
}

/** 获取迁移文件列表的 SHA256 摘要 */
function getFileChecksum(filePath) {
  if (!fs.existsSync(filePath)) return null;
  const crypto = require('crypto');
  const content = fs.readFileSync(filePath, 'utf-8');
  return crypto.createHash('sha256').update(content).digest('hex');
}

// ── CLI 命令 ───────────────────────────────────────────────

async function cmdUp(count) {
  await ensureMigrationTable();
  const applied = await getAppliedMigrations();
  const appliedVersions = new Set(applied.map(m => m.version));
  const allMigrations = scanMigrations();
  
  const pending = allMigrations.filter(m => !appliedVersions.has(m.version));
  
  if (pending.length === 0) {
    console.log('✅ 没有待处理的迁移');
    await getPool().end();
    return;
  }
  
  const toApply = count ? pending.slice(0, count) : pending;
  console.log(`将应用 ${toApply.length} 个迁移（共 ${pending.length} 个待处理）`);
  
  for (const m of toApply) {
    await applyMigration(m);
  }
  
  await getPool().end();
}

async function cmdDown(count) {
  await ensureMigrationTable();
  const applied = await getAppliedMigrations();
  
  if (applied.length === 0) {
    console.log('✅ 没有可回滚的迁移');
    await getPool().end();
    return;
  }
  
  const allMigrations = scanMigrations();
  const toRollback = count ? applied.slice(-count).reverse() : [applied[applied.length - 1]];
  
  console.log(`将回滚 ${toRollback.length} 个迁移`);
  
  for (const m of toRollback) {
    const migrationDef = allMigrations.find(mm => mm.version === m.version);
    if (!migrationDef) {
      console.error(`  ❌ 迁移 ${m.version} 定义文件不存在`);
      continue;
    }
    
    // 校验 checksum 是否匹配
    const expectedChecksum = getFileChecksum(
      path.join(MIGRATIONS_DIR, migrationDef.upFile)
    );
    if (expectedChecksum && expectedChecksum !== m.checksum) {
      console.error(`  ⚠️  迁移 ${m.version} 的 .up.sql 文件已变更（checksum不匹配）`);
      console.error(`     数据库记录: ${m.checksum.substring(0, 16)}...`);
      console.error(`     当前文件:   ${expectedChecksum.substring(0, 16)}...`);
      console.error(`     跳过此迁移的回滚，请手动处理`);
      continue;
    }
    
    await rollbackMigration(migrationDef);
  }
  
  await getPool().end();
}

async function cmdStatus() {
  await ensureMigrationTable();
  const applied = await getAppliedMigrations();
  const appliedSet = new Map(applied.map(m => [m.version, m]));
  const allMigrations = scanMigrations();
  
  console.log('\n┌─────────┬──────────────────────────────────┬──────────┬───────────────────────┐');
  console.log('│ 版本     │ 名称                             │ 状态     │ 应用时间              │');
  console.log('├─────────┼──────────────────────────────────┼──────────┼───────────────────────┤');
  
  for (const m of allMigrations) {
    const a = appliedSet.get(m.version);
    const status = a ? '✅ 已应用' : '⬜ 待处理';
    const time = a ? a.applied_at.toISOString().substring(0, 19) : '';
    const name = m.name.length > 30 ? m.name.substring(0, 27) + '...' : m.name;
    console.log(
      `│ ${m.version.padEnd(7)} │ ${name.padEnd(32)} │ ${status.padEnd(8)} │ ${time.padEnd(22)} │`
    );
  }
  console.log('└─────────┴──────────────────────────────────┴──────────┴───────────────────────┘');
  console.log(`\n总计: ${allMigrations.length} 个迁移，${applied.length} 个已应用，${allMigrations.length - applied.length} 个待处理\n`);
  
  await getPool().end();
}

async function cmdBaseline() {
  await ensureMigrationTable();
  const applied = await getAppliedMigrations();
  
  if (applied.length > 0) {
    console.log('⚠️  数据库已有迁移记录，跳过基线设置');
    await getPool().end();
    return;
  }
  
  // 扫描迁移目录，把所有现有迁移标记为已应用（不走SQL）
  const allMigrations = scanMigrations();
  if (allMigrations.length === 0) {
    console.log('⚠️  没有找到迁移文件，跳过基线设置');
    await getPool().end();
    return;
  }
  
  const client = await getPool().connect();
  try {
    await client.query('BEGIN');
    for (const m of allMigrations) {
      await client.query(
        `INSERT INTO _migrations (version, name, checksum, duration_ms)
         VALUES ($1, $2, $3, 0)
         ON CONFLICT (version) DO NOTHING`,
        [m.version, m.name, m.checksum]
      );
      console.log(`  📌 基线: ${m.version}_${m.name}`);
    }
    await client.query('COMMIT');
    console.log(`✅ 已设置 ${allMigrations.length} 个迁移为基线`);
  } catch (e) {
    await client.query('ROLLBACK');
    console.error(`❌ 基线设置失败: ${e.message}`);
  } finally {
    client.release();
  }
  
  await getPool().end();
}

// ── 入口 ───────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  const command = args[0] || 'status';
  const count = args[1] ? parseInt(args[1]) : null;
  
  console.log(`\n📦 Field Tracker — 数据库迁移工具\n`);
  
  try {
    switch (command) {
      case 'up':
        await cmdUp(count);
        break;
      case 'down':
        await cmdDown(count);
        break;
      case 'status':
        await cmdStatus();
        break;
      case 'baseline':
        await cmdBaseline();
        break;
      default:
        console.log(`用法:
  node migrate.js up [数量]    执行迁移
  node migrate.js down [数量]  回滚迁移
  node migrate.js status       查看状态
  node migrate.js baseline     标记基线
`);
        await getPool().end();
    }
  } catch (e) {
    console.error(`\n❌ 错误: ${e.message}`);
    process.exit(1);
  }
}

main();
