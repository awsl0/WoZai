import { Router } from 'express';

/** 是否行政区名（市/区/县/州 结尾），如“许昌市”“太康县”“蜀山区” */
export function looksLikeAdmin(s: string): boolean {
  const t = s.trim();
  return t.length <= 8 && /(市|区|县|州)$/.test(t);
}

export interface GeoResult {
  name: string;
  address: string;
  lat: number;
  lng: number;
  /** 行政区划省（如“河南省”） */
  province?: string;
  /** 行政区划市/县/区名 */
  cityName?: string;
}

/**
 * 地理编码查询（供路由与事件落库补坐标共用）
 * 多源失败自动切换：Photon → Nominatim；全部失败返回空列表
 */
export async function geocodeQuery(q: string): Promise<GeoResult[]> {
  const sources: { url: string; parser: (d: any, n: string) => GeoResult[] }[] = [
    {
      url: `https://photon.komoot.io/api/?q=${encodeURIComponent(q)}&limit=5`,
      parser: parsePhoton,
    },
    {
      url: `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(q)}&format=jsonv2&limit=5&accept-language=zh`,
      parser: parseNominatim,
    },
  ];
  for (const src of sources) {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 8000);
      const r = await fetch(src.url, {
        signal: controller.signal,
        headers: {
          'User-Agent': 'WoZaiApp/1.7 (ywjsn552566@163.com)',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        },
      });
      clearTimeout(timer);
      if (!r.ok) continue;
      const data = await r.json();
      const results = src.parser(data, q);
      if (results.length > 0) return results;
    } catch {
      // 下一个源
    }
  }
  return [];
}

const router = Router();

function parsePhoton(data: any, fallbackName: string): GeoResult[] {
  const out: GeoResult[] = [];
  for (const f of (data?.features ?? []) as any[]) {
    const props = f?.properties ?? {};
    const coord = f?.geometry?.coordinates;
    if (!Array.isArray(coord) || coord.length < 2) continue;
    const name = String(props.name ?? fallbackName).trim();
    if (!name) continue;
    const seen = new Set<string>();
    const parts: string[] = [];
    for (const k of ['country', 'state', 'city', 'county', 'district', 'locality', 'street']) {
      const v = String(props[k] ?? '').trim();
      if (v && v !== '中国' && !seen.has(v)) {
        seen.add(v);
        parts.push(v);
      }
    }
    out.push({
      name,
      address: parts.join(' '),
      lat: Number(coord[1]),
      lng: Number(coord[0]),
      province: String(props.state ?? '').trim() || undefined,
      cityName: String(props.city ?? props.county ?? props.district ?? '').trim() || undefined,
    });
  }
  return out;
}

function parseNominatim(data: any, fallbackName: string): GeoResult[] {
  const out: GeoResult[] = [];
  for (const r of (data ?? []) as any[]) {
    const lat = Number(r?.lat);
    const lng = Number(r?.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
    const nm = r?.name ? String(r.name).trim() : r?.display_name?.split(',').slice(0, 2).join('').trim() || fallbackName;
    // 从 display_name 拆出省/市/区级别（逗号分隔，OSM 是倒序：国家在最后）
    const segs = (String(r?.display_name ?? '').split(',')).map((s: string) => s.trim()).filter(Boolean);
    // display_name: 街道, 区, 市, 省, 国家
    const addrParts = segs.slice(0, Math.max(0, segs.length - 1)).slice(0, 4);
    const address = addrParts.slice().reverse().join(' ');
    out.push({
      name: nm,
      address: address.trim(),
      lat,
      lng,
      province: String(r?.address?.state ?? '').trim() || undefined,
      cityName:
        String(r?.address?.city ?? r?.address?.county ?? r?.address?.district ?? '').trim() ||
        undefined,
    });
  }
  return out;
}

/**
 * GET /api/geocode?q=周口
 * 地理编码代理：国内手机 → 自家服务器（必可达）→ 转发海外地理编码源
 * 多源失败自动切换：Photon → Nominatim
 */
router.get('/', async (req, res) => {
  const q = String(req.query.q ?? '').trim();
  if (!q) return res.json({ results: [] });
  const results = await geocodeQuery(q);
  return res.json({ results });
});

export default router;