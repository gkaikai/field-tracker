import { Pool } from 'pg';
import Redis from 'ioredis';
import dotenv from 'dotenv';

dotenv.config();

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

// Redis 客户端
export const redis = new Redis({
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379'),
  retryStrategy: (times) => {
    const delay = Math.min(times * 50, 2000);
    return delay;
  },
});

redis.on('connect', () => {
  console.log('Redis 已连接');
});

redis.on('error', (err) => {
  console.error('Redis 错误:', err.message);
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
