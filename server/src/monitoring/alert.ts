import { logger } from '../config/logger';
import * as https from 'https';
import * as http from 'http';

// ============================================================
//  告警通知 — 钉钉 / 企业微信 Webhook 方式
// ============================================================

/** 告警级别 */
export type AlertLevel = 'info' | 'warning' | 'critical';

/** 告警通道配置 */
interface AlertChannelConfig {
  dingtalk?: string;   // 钉钉 Webhook URL
  wecom?: string;      // 企业微信 Webhook URL
}

/** 当前生效的告警通道 */
let alertConfig: AlertChannelConfig = {};

/**
 * 初始化告警通道（从环境变量读取 Webhook URL）
 * - DINGTALK_WEBHOOK: 钉钉机器人 Webhook URL
 * - WECOM_WEBHOOK: 企业微信机器人 Webhook URL
 */
export function initAlert(config?: AlertChannelConfig): void {
  alertConfig = {
    dingtalk: config?.dingtalk || process.env.DINGTALK_WEBHOOK,
    wecom: config?.wecom || process.env.WECOM_WEBHOOK,
  };

  if (alertConfig.dingtalk) {
    logger.info('[告警] 钉钉通知通道已配置');
  }
  if (alertConfig.wecom) {
    logger.info('[告警] 企业微信通知通道已配置');
  }
  if (!alertConfig.dingtalk && !alertConfig.wecom) {
    logger.warn('[告警] 未配置任何通知通道（设置 DINGTALK_WEBHOOK 或 WECOM_WEBHOOK）');
  }
}

// ============================================================
//  钉钉通知
// ============================================================

/**
 * 发送钉钉机器人消息
 * @see https://open.dingtalk.com/document/robots/custom-robot-access
 */
function sendDingTalk(level: AlertLevel, title: string, content: string): void {
  const webhook = alertConfig.dingtalk;
  if (!webhook) return;

  const colorMap: Record<AlertLevel, string> = {
    info: '#1890FF',
    warning: '#FAAD14',
    critical: '#F5222D',
  };

  const payload = JSON.stringify({
    msgtype: 'markdown',
    markdown: {
      title: `[${level.toUpperCase()}] ${title}`,
      text: [
        `### ⚠️ ${title}`,
        `---`,
        `**级别**: <font color="${colorMap[level]}">${level.toUpperCase()}</font>`,
        `**时间**: ${new Date().toLocaleString('zh-CN')}`,
        `**内容**: ${content}`,
        `---`,
        `*Field Tracker 监控告警*`,
      ].join('\n\n'),
    },
  });

  postWebhook(webhook, payload, '钉钉');
}

// ============================================================
//  企业微信通知
// ============================================================

/**
 * 发送企业微信机器人消息
 * @see https://developer.work.weixin.qq.com/document/path/91770
 */
function sendWeCom(level: AlertLevel, title: string, content: string): void {
  const webhook = alertConfig.wecom;
  if (!webhook) return;

  const levelLabel: Record<AlertLevel, string> = {
    info: 'ℹ️ 信息',
    warning: '⚠️ 警告',
    critical: '🚨 严重',
  };

  const payload = JSON.stringify({
    msgtype: 'markdown',
    markdown: {
      content: [
        `## ${levelLabel[level]} ${title}`,
        `> **时间**: ${new Date().toLocaleString('zh-CN')}`,
        `> **内容**: ${content}`,
        `> ---`,
        `> Field Tracker 监控告警`,
      ].join('\n'),
    },
  });

  postWebhook(webhook, payload, '企业微信');
}

// ============================================================
//  通用 Webhook HTTP POST
// ============================================================

function postWebhook(webhookUrl: string, payload: string, channelName: string): void {
  try {
    const url = new URL(webhookUrl);
    const client = url.protocol === 'https:' ? https : http;

    const req = client.request(
      webhookUrl,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload),
        },
        timeout: 10000,
      },
      (res) => {
        let body = '';
        res.on('data', (chunk) => (body += chunk));
        res.on('end', () => {
          if (res.statusCode !== 200) {
            logger.error(`[告警] ${channelName} 通知发送失败`, {
              status: res.statusCode,
              body: body.slice(0, 200),
            });
          }
        });
      },
    );

    req.on('error', (err) => {
      logger.error(`[告警] ${channelName} 通知请求异常`, { error: err.message });
    });

    req.on('timeout', () => {
      req.destroy();
      logger.error(`[告警] ${channelName} 通知请求超时`);
    });

    req.write(payload);
    req.end();
  } catch (err) {
    logger.error(`[告警] ${channelName} 通知构建失败`, { error: (err as Error).message });
  }
}

// ============================================================
//  对外告警接口
// ============================================================

/** 发送一条告警通知（同时发送到所有已配置的通道） */
export function sendAlert(level: AlertLevel, title: string, content: string): void {
  if (!alertConfig.dingtalk && !alertConfig.wecom) return;

  logger.info(`[告警发送] [${level}] ${title}: ${content}`);

  if (alertConfig.dingtalk) {
    sendDingTalk(level, title, content);
  }
  if (alertConfig.wecom) {
    sendWeCom(level, title, content);
  }
}

// ============================================================
//  告警规则检查 — 5xx 错误超过阈值
// ============================================================

interface ErrorCountBucket {
  windowStart: number;    // 时间窗口起始时间戳 (ms)
  count5xx: number;
  countSlow: number;
}

const errorBucket: ErrorCountBucket = {
  windowStart: Date.now(),
  count5xx: 0,
  countSlow: 0,
};

/** 重置计数窗口（每分钟调用） */
function resetBucketIfExpired(): void {
  const now = Date.now();
  if (now - errorBucket.windowStart >= 60_000) {
    errorBucket.windowStart = now;
    errorBucket.count5xx = 0;
    errorBucket.countSlow = 0;
  }
}

/**
 * 记录一次 5xx 错误，超过阈值触发告警
 * @param statusCode HTTP 状态码
 * @param path 请求路径
 */
export function record5xx(statusCode: number, path: string): void {
  if (statusCode < 500) return;

  resetBucketIfExpired();
  errorBucket.count5xx++;

  if (errorBucket.count5xx >= 5) {
    sendAlert('critical', '5xx 错误超过阈值', [
      `路径: ${path}`,
      `状态码: ${statusCode}`,
      `当前窗口(1分钟)内 5xx 错误数: ${errorBucket.count5xx}`,
      `阈值: 5次/分钟`,
    ].join('\n'));
  }
}

/**
 * 记录一次慢请求，触发告警
 * @param durationMs 请求耗时 (ms)
 * @param path 请求路径
 */
export function recordSlowRequest(durationMs: number, path: string): void {
  if (durationMs <= 3000) return;

  resetBucketIfExpired();
  errorBucket.countSlow++;

  sendAlert('warning', '接口响应超过 3 秒', [
    `路径: ${path}`,
    `耗时: ${durationMs}ms`,
    `阈值: 3000ms`,
  ].join('\n'));
}

/** 静默所有告警（用于测试/维护模式） */
export function silenceAlerts(silenced: boolean): void {
  if (silenced) {
    logger.info('[告警] 已静音，通知通道暂时关闭');
    alertConfig = {};
  } else {
    initAlert();
  }
}

export default {
  initAlert,
  sendAlert,
  record5xx,
  recordSlowRequest,
  silenceAlerts,
};
