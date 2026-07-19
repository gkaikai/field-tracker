import { Router, Request, Response } from 'express';

const router = Router();

/**
 * GET /api/v1/geocode/search
 * 地理编码：地址→坐标
 * 使用 Nominatim (OpenStreetMap) 免费服务
 * 对国内地址建议用高德/百度，后续可切换
 */
router.get('/search', async (req: Request, res: Response) => {
  const { address } = req.query;
  if (!address || typeof address !== 'string' || address.trim().length === 0) {
    return res.status(400).json({ success: false, message: '请提供地址参数' });
  }

  try {
    // 使用 photon.komoot.io 免费地理编码（基于OSM数据，国内可用）
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 5000);
    
    const url = `https://photon.komoot.io/api/?q=${encodeURIComponent(address)}&limit=5`;
    const resp = await fetch(url, {
      signal: controller.signal,
    });
    clearTimeout(timeoutId);

    if (!resp.ok) {
      return res.status(502).json({ success: false, message: '地理编码服务不可用' });
    }

    const data = await resp.json() as any;
    if (!data || !data.features) {
      console.error('[Geocode] 响应格式异常:', JSON.stringify(data).slice(0, 200));
      return res.json({ success: true, results: [] });
    }
    const features = data.features as any[];
    if (!features || features.length === 0) {
      return res.json({ success: true, results: [] });
    }

    const results = features.map((item: any) => ({
      address: item.properties?.name ?? '',
      lat: parseFloat(item.geometry?.coordinates?.[1] ?? 0),
      lng: parseFloat(item.geometry?.coordinates?.[0] ?? 0),
    }));

    return res.json({ success: true, results });
  } catch (e: any) {
    console.error('[Geocode] 搜索失败:', e.message);
    return res.status(500).json({ success: false, message: '搜索服务异常' });
  }
});

export default router;
