import { Pool } from 'pg';
import Redis from 'ioredis';
// 环境变量由入口文件 src/index.ts 根据 NODE_ENV 加载对应的 .env 文件
// 此文件不再调用 dotenv.config()，避免干扰入口文件的加载顺序

// PostgreSQL 连接池
export const pgPool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME || 'field_tracker',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

pgPool.on('error', (err) => {
  console.error('PostgreSQL 连接异常:', err.message);
});

// Redis 客户端（可选，连接失败不阻塞启动）
const redisOpts = {
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379'),
  retryStrategy: (times: number) => {
    if (times > 3) return null; // 3次重试后放弃，不再自动重连
    return Math.min(times * 200, 2000);
  },
  maxRetriesPerRequest: 3,
  lazyConnect: true, // 不自动连接
};
export const redis = new Redis(redisOpts);

// 静默连接，不输出错误日志（Redis不可用时降级运行）
redis.connect().catch(() => {
  // Redis不可用 → 降级运行（不输出"Redis错误"到终端）
});

// 测试数据库连接
export async function testConnection() {
  try {
    const client = await pgPool.connect();
    const result = await client.query('SELECT NOW()');
    console.log('PostgreSQL 已连接:', result.rows[0].now);
    client.release();
    return true;
  } catch (err) {
    console.error('PostgreSQL 连接失败:', err);
    return false;
  }
}
