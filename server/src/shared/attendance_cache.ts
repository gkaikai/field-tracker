/// 内存考勤记录缓存（数据库不可用时使用）
///
/// 拆分为独立模块，避免 location.ts 与 attendance.ts 之间的循环依赖
/// 使用 const 对象容器，使引用和值变更均可跨模块生效

/** 内存考勤记录类型 */
export interface MemAttendanceRecord {
  id: number;
  user_id: string;
  type: string;
  lng: number;
  lat: number;
  address: string | null;
  accuracy: number;
  photo_url: string | null;
  wifi_bssid: string | null;
  device_info: string | null;
  check_time: string;
  created_at: string;
}

/** 内存考勤缓存（包含数组 + ID 自增计数器） */
export const attendanceCache: {
  records: MemAttendanceRecord[];
  nextId: number;
} = {
  records: [],
  nextId: 1,
};

/** 查询指定用户的考勤记录 */
export function getMemAttendanceRecords(userId: string): MemAttendanceRecord[] {
  return attendanceCache.records.filter(r => r.user_id === userId);
}
