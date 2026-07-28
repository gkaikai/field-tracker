import { exec } from 'child_process';
import { promisify } from 'util';
import { logger } from '../config/logger';
import { sendAlert, record5xx, recordSlowRequest } from './alert';

const execAsync = promisify(exec);

// ============================================================
//  基础监控指标收集
// ============================================================

/** 请求级别的指标数据 */
interface RequestMetrics {
  path: string;
  method: string;
  statusCode: number;
  durationMs: number;
  timestamp: number;
}

/** 端点聚合统计 */
interface EndpointStats {
  count: number;
  errors4xx: number;
  errors5xx: number;
  totalDuration: number;
  maxDuration: number;
  lastSeen: number;
}

// ============================================================
//  全局指标
// ============================================================

const metrics = {
  /** 请求总数 */
  totalRequests: 0,
  /** 当前活跃请求数 */
  activeRequests: 0,
  /** 请求错误数汇总 */
  totalErrors4xx: 0,
  totalErrors5xx: 0,
  /** 启动时间 */
  startTime: Date.now(),

  /** 端点级别统计 */
  endpoints: new Map<string, EndpointStats>(),

  /** 慢请求记录（最近 100 条） */
  slowRequests: [] as { path: string; durationMs: number; timestamp: number }[],
  /** 错误请求记录（最近 100 条） */
  errorRequests: [] as { path: string; statusCode: number; timestamp: number }[],
};

// ============================================================
//  记录请求
// ============================================================

/**
 * 记录一次请求的指标（由中间件调用）
 * - 聚合端点统计
 * - 触发告警规则检查（5xx 阈值、慢请求阈值）
 */
export function recordRequest(metric: RequestMetrics): void {
  metrics.totalRequests++;
  metrics.activeRequests++;

  // 端点聚合
  const epKey = `${metric.method}:${metric.path}`;
  let epStats = metrics.endpoints.get(epKey);
  if (!epStats) {
    epStats = { count: 0, errors4xx: 0, errors5xx: 0, totalDuration: 0, maxDuration: 0, lastSeen: 0 };
    metrics.endpoints.set(epKey, epStats);
  }
  epStats.count++;
  epStats.totalDuration += metric.durationMs;
  epStats.maxDuration = Math.max(epStats.maxDuration, metric.durationMs);
  epStats.lastSeen = metric.timestamp;

  // 错误统计
  if (metric.statusCode >= 400 && metric.statusCode < 500) {
    metrics.totalErrors4xx++;
    epStats.errors4xx++;
    metrics.errorRequests.unshift({
      path: metric.path,
      statusCode: metric.statusCode,
      timestamp: metric.timestamp,
    });
    if (metrics.errorRequests.length > 100) metrics.errorRequests.pop();
  }

  if (metric.statusCode >= 500) {
    metrics.totalErrors5xx++;
    epStats.errors5xx++;

    // 触发 5xx 告警规则
    record5xx(metric.statusCode, metric.path);

    metrics.errorRequests.unshift({
      path: metric.path,
      statusCode: metric.statusCode,
      timestamp: metric.timestamp,
    });
    if (metrics.errorRequests.length > 100) metrics.errorRequests.pop();
  }

  // 慢请求检测（> 3 秒）
  if (metric.durationMs > 3000) {
    recordSlowRequest(metric.durationMs, metric.path);
    metrics.slowRequests.unshift({
      path: metric.path,
      durationMs: metric.durationMs,
      timestamp: metric.timestamp,
    });
    if (metrics.slowRequests.length > 100) metrics.slowRequests.pop();

    logger.warn('慢请求检测', {
      path: metric.path,
      method: metric.method,
      duration: `${metric.durationMs}ms`,
    });
  }
}

/**
 * 请求完成时调用，减少活跃计数
 */
export function completeRequest(): void {
  metrics.activeRequests = Math.max(0, metrics.activeRequests - 1);
}

// ============================================================
//  快照 / 报告
// ============================================================

/** 获取当前所有指标的只读快照 */
export function getMetricsSnapshot() {
  const uptime = Math.floor((Date.now() - metrics.startTime) / 1000);

  // 按请求量排名的 Top 端点
  const topEndpoints = Array.from(metrics.endpoints.entries())
    .map(([key, stats]) => ({ endpoint: key, ...stats }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 20);

  return {
    uptime,
    totalRequests: metrics.totalRequests,
    activeRequests: metrics.activeRequests,
    totalErrors4xx: metrics.totalErrors4xx,
    totalErrors5xx: metrics.totalErrors5xx,
    errorRate: metrics.totalRequests > 0
      ? ((metrics.totalErrors4xx + metrics.totalErrors5xx) / metrics.totalRequests * 100).toFixed(2) + '%'
      : '0%',
    topEndpoints,
    recentSlowRequests: metrics.slowRequests.slice(0, 10),
    recentErrors: metrics.errorRequests.slice(0, 10),
  };
}

// ============================================================
//  报告生成 — 按端点输出统计日志
// ============================================================

/** 输出端点性能摘要到日志 */
export function logMetricsSummary(): void {
  const snapshot = getMetricsSnapshot();

  logger.info('===== 监控指标摘要 =====', {
    uptime: `${snapshot.uptime}s`,
    totalRequests: snapshot.totalRequests,
    activeRequests: snapshot.activeRequests,
    '4xx': snapshot.totalErrors4xx,
    '5xx': snapshot.totalErrors5xx,
    errorRate: snapshot.errorRate,
  });

  for (const ep of snapshot.topEndpoints.slice(0, 10)) {
    const avgDuration = ep.count > 0 ? (ep.totalDuration / ep.count).toFixed(0) : '0';
    logger.debug(`  [端点] ${ep.endpoint}`, {
      count: ep.count,
      '4xx': ep.errors4xx,
      '5xx': ep.errors5xx,
      avgMs: avgDuration,
      maxMs: ep.maxDuration,
    });
  }
}

// ============================================================
//  定期报告（定时器，默认每 30 分钟输出一次摘要）
// ============================================================

let summaryInterval: ReturnType<typeof setInterval> | null = null;

/** 启动定期报告（默认每 30 分钟） */
export function startMetricsSummary(intervalMs: number = 30 * 60 * 1000): void {
  if (summaryInterval) return;
  summaryInterval = setInterval(() => logMetricsSummary(), intervalMs);
  logger.info(`监控指标摘要输出已启动（间隔: ${intervalMs / 1000}s）`);
}

/** 停止定期报告 */
export function stopMetricsSummary(): void {
  if (summaryInterval) {
    clearInterval(summaryInterval);
    summaryInterval = null;
  }
}

// ============================================================
//  磁盘使用率告警
// ============================================================

/** 检查磁盘使用率并告警（通过 sendAlert） */
export async function checkDiskUsage(): Promise<void> {
  try {
    const { stdout } = await execAsync('df -h / | tail -1');
    // 输出格式示例: /dev/disk1s6  466G  380G   86G    82%  /
    const parts = stdout.trim().split(/\s+/);
    const usageStr = parts[parts.length - 2]; // e.g. "82%"
    const usagePercent = parseInt(usageStr.replace('%', ''), 10);

    if (usagePercent > 90) {
      sendAlert('critical', '磁盘使用率超过 90%', `当前使用率: ${usagePercent}%`);
    }
  } catch (err) {
    logger.error('磁盘使用率检查失败', { error: (err as Error).message });
  }
}

export default {
  recordRequest,
  completeRequest,
  getMetricsSnapshot,
  logMetricsSummary,
  startMetricsSummary,
  stopMetricsSummary,
  checkDiskUsage,
};
