import { Router, Request, Response, NextFunction } from 'express';
import { authMiddleware } from '../middleware/auth';

const router = Router();

// 地理编码接口需要认证，防止 API Key 被盗用
router.use(authMiddleware);

/**
 * GET /api/v1/geocode/search
 * 地理编码：地址→坐标
 * 使用高德Web Service API（国内稳定）
 */
router.get('/search', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { address } = req.query;
    if (!address || typeof address !== 'string' || address.trim().length === 0) {
      return res.status(400).json({ success: false, message: '请提供地址参数' });
    }

    const key = process.env.AMAP_WS_KEY || '';
    if (!key) {
      return res.status(500).json({ success: false, message: '高德Key未配置' });
    }
    // ⚠️ 安全风险: key 通过 URL query 参数传递，会被服务器访问日志明文记录。
    //    生产环境建议确认高德已关闭 access log 的 query 参数记录，或后续改用
    //    header 方式（高德服务目前仅支持 key 参数，暂无法避免）。
    const url = `https://restapi.amap.com/v3/geocode/geo?key=${key}&address=${encodeURIComponent(address)}&output=JSON`;
    const resp = await fetch(url);
    const data = await resp.json() as any;
    if (data.status !== '1' || !data.geocodes || data.geocodes.length === 0) {
      return res.json({ success: true, results: [] });
    }
    const results = data.geocodes.map((item: any) => ({
      address: item.formatted_address ?? '',
      lat: parseFloat(item.location.split(',')[1] ?? 0),
      lng: parseFloat(item.location.split(',')[0] ?? 0),
    }));
    return res.json({ success: true, results });
  } catch (err) {
    console.error('[Geocode] 搜索失败:', (err as Error).message);
    next(err);
  }
});

export default router;
