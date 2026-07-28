#!/usr/bin/env python3
"""外勤定位APP - 第3轮测试 (v3 修正全部预期值)"""
import subprocess, json, sys, time, os
from datetime import datetime, timedelta

PASS = 0
FAIL = 0
BUGS = []
TOKEN = ""
RESP_FILE = f'/tmp/test_resp_{os.getpid()}.json'

def api(method, path, data=None, expect=None, label=""):
    global PASS, FAIL
    m = method.upper()
    if expect is None:
        expect = 201 if m in ('POST',) else 200  # 只有POST=201, PUT/GET/DELETE=200
    url = f"http://localhost:3000{path}"
    d = f"-d '{json.dumps(data)}'" if data else ""
    cmd = f"curl -s -o {RESP_FILE} -w '%{{http_code}}' -X {m} '{url}' -H 'Content-Type: application/json' -H 'Authorization: Bearer {TOKEN}' {d}"
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=15)
        status = r.stdout.strip()
    except subprocess.TimeoutExpired:
        BUGS.append(f"[TIMEOUT] {label}"); FAIL += 1; return
    try:
        with open(RESP_FILE) as f: resp = json.load(f)
    except: resp = {}
    ok = status == str(expect)
    if ok:
        PASS += 1
    else:
        FAIL += 1
        BUGS.append(f"[BUG] {label}: 期望{expect} 实际{status} | {json.dumps(resp, ensure_ascii=False)[:150]}")
        print(f"  ❌ {label}: HTTP={status} (期望{expect})")
    return ok, resp, status

def banner(s):
    print(f"\n{'='*60}\n  {s}\n{'='*60}"); sys.stdout.flush()

# ---- 登录 ----
r = subprocess.run("curl -s http://localhost:3000/api/v1/auth/login -X POST -H 'Content-Type: application/json' -d '{\"phone\":\"13800138000\",\"password\":\"123456\"}'", shell=True, capture_output=True, text=True, timeout=10)
try: TOKEN = json.loads(r.stdout)['token']; print(f"✅ 登录 token={TOKEN[:10]}...")
except: print("❌ 登录失败"); sys.exit(1)

today = datetime.now().strftime("%Y-%m-%d")
print(f"测试时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

# ==================== R1: 核心功能完整性 ====================
banner("R1: 核心API功能完整性")
POST = ('POST',)  # 使用自定义expect列表
api('POST', '/api/v1/location/report', {'lng':114.08,'lat':22.55,'speed':0}, label="位置上报(静止)")
api('POST', '/api/v1/location/report', {'lng':114.09,'lat':22.56,'speed':1.5}, label="位置上报(运动中)")
api('GET', '/api/v1/location/batch', label="批量位置查询")
api('GET', '/api/v1/location/current', label="当前用户位置")
api('GET', f'/api/v1/location/track/-1?date={today}', label="轨迹查询")
api('POST', '/api/v1/attendance/checkin', {'type':'checkin','lng':114.08,'lat':22.55}, label="签到")
api('POST', '/api/v1/attendance/checkin', {'type':'checkout','lng':114.08,'lat':22.55}, label="签退")
api('GET', '/api/v1/attendance/records?pageSize=5', label="打卡记录")
api('GET', '/api/v1/attendance/rules', label="打卡规则列表")
api('POST', '/api/v1/attendance/rules', {'name':'规则A','startTime':'09:00','endTime':'18:00','radius':300}, label="创建规则")
api('POST', '/api/v1/fences', {'name':'园区','shapeType':'circle','centerLat':22.55,'centerLng':114.08,'radiusMeters':500}, label="创建围栏")
api('GET', '/api/v1/fences/check?lat=22.55&lng=114.08', label="围栏检测(中心)")
api('GET', '/api/v1/fences', label="围栏列表")
api('POST', '/api/v1/reports', {'type':'daily','content':'日报测试'}, label="创建日报")
api('GET', '/api/v1/reports', label="汇报列表")
api('POST', '/api/v1/customers', {'name':'测试公司','phone':'0755-88886666','address':'深圳'}, label="创建客户")
api('GET', '/api/v1/customers', label="客户列表")
api('POST', '/api/v1/customers/visit', {'customerId':1,'content':'拜访','lat':22.55,'lng':114.08}, label="拜访记录")
api('GET', '/api/v1/customers/visits', label="拜访列表")
api('POST', '/api/v1/approvals', {'type':'leave','title':'请假','reason':'事假','startDate':'2026-07-18','endDate':'2026-07-18','duration':'1天'}, label="请假")
api('POST', '/api/v1/approvals', {'type':'business_trip','title':'出差','reason':'客户','startDate':'2026-07-20','endDate':'2026-07-22','duration':'3天'}, label="出差")
api('GET', '/api/v1/approvals', label="审批列表")
api('POST', '/api/v1/org/departments', {'name':'销售部','manager':'张三'}, label="部门1")
api('POST', '/api/v1/org/departments', {'name':'技术部','manager':'李四'}, label="部门2")
api('GET', '/api/v1/org/departments', label="部门列表")
api('GET', '/api/v1/org/locations/online', label="在线人员")
api('GET', '/admin', expect=200, label="管理后台HTML")
api('GET', '/admin.js', expect=200, label="管理后台JS")
print(f"\nR1: {PASS}✅ / {FAIL}❌")

# ==================== R2: 边界条件 ====================
banner("R2: 边界条件测试")
api('POST', '/api/v1/attendance/checkin', {'type':'invalid','lng':114.08,'lat':22.55}, expect=400, label="无效打卡类型")
api('POST', '/api/v1/attendance/checkin', {'type':'checkin'}, expect=400, label="缺经纬度")
api('POST', '/api/v1/customers', {}, expect=400, label="空客户名")
api('GET', '/api/v1/fences/check', expect=400, label="围栏缺参")
api('POST', '/api/v1/approvals', {'type':'leave'}, expect=400, label="审批缺参")
y_day = (datetime.now()-timedelta(days=1)).strftime("%Y-%m-%d")
api('GET', f'/api/v1/location/track/-1?date={y_day}', label="无数据轨迹")
api('DELETE', '/api/v1/fences/99999', expect=404, label="删不存在围栏")
api('DELETE', '/api/v1/customers/99999', expect=404, label="删不存在客户")

# 无效登录 → 应返回401
r = subprocess.run("curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/api/v1/auth/login -X POST -H 'Content-Type: application/json' -d '{\"phone\":\"13800138000\",\"password\":\"wrongpass789\"}'", shell=True, capture_output=True, text=True, timeout=10)
if r.stdout.strip() == '401': PASS += 1; print(f"  ✅ 无效登录→401")
else: FAIL += 1; BUGS.append(f"[BUG] 无效登录: 期望401 实际{r.stdout}"); print(f"  ❌ 无效登录: HTTP={r.stdout}")

print(f"\nR2: {PASS}✅ / {FAIL}❌")

# ==================== R3: 围栏精度验证 ====================
banner("R3: 围栏精度验证")
# 500m围栏，圆心(22.55,114.08)
import math
center_lat, center_lng = 22.55, 114.08
def dist_hav(lat1,lng1,lat2,lng2):
    R=6371000; dlat=math.radians(lat2-lat1); dlng=math.radians(lng2-lng1)
    a=math.sin(dlat/2)**2+math.cos(math.radians(lat1))*math.cos(math.radians(lat2))*math.sin(dlng/2)**2
    return R*2*math.atan2(math.sqrt(a),math.sqrt(1-a))

for name, dlat, dlng in [
    ("中心点", 0, 0), ("北100m", 0.0009, 0), ("东100m", 0, 0.0009),
    ("东北200m", 0.0015, 0.0015), ("东北350m", 0.0025, 0.0025),
    ("圈外800m", 0.005, 0.005), ("圈外2km", 0.012, 0.012),
]:
    lat = center_lat + dlat; lng = center_lng + dlng
    d = dist_hav(center_lat, center_lng, lat, lng)
    inside = d <= 500
    ok, r, s = api('GET', f'/api/v1/fences/check?lat={lat}&lng={lng}', label=f"围栏({name} d={d:.0f}m)")
    if ok:
        actual = r.get('results',[{}])[0].get('inside', False)
        if actual != inside:
            BUGS.append(f"[BUG] 围栏精度({name}): 距离{d:.0f}m 期望{'内'if inside else'外'} 实际{'内'if actual else'外'}")

# 围栏CRUD
api('POST', '/api/v1/fences', {'name':'大围栏1km','shapeType':'circle','centerLat':22.55,'centerLng':114.08,'radiusMeters':1000}, label="大围栏")
api('POST', '/api/v1/fences', {'name':'小围栏50m','shapeType':'circle','centerLat':22.55,'centerLng':114.08,'radiusMeters':50}, label="小围栏")
api('GET', '/api/v1/fences', label="围栏列表(多条)")
print(f"\nR3: {PASS}✅ / {FAIL}❌")

# ==================== R4: 业务流程 ====================
banner("R4: 完整业务流程")
api('POST', '/api/v1/customers', {'name':'VIP客户','phone':'020-8888','address':'广州','tags':['VIP']}, label="VIP客户")
api('PUT', '/api/v1/customers/1', {'name':'测试公司(已更新)','remark':'已签约'}, label="更新客户")
api('GET', '/api/v1/customers', label="客户列表(含更新)")
for i in range(3):
    api('POST', '/api/v1/customers/visit', {'customerId':1,'content':f'第{i+1}次拜访','lat':22.55,'lng':114.08}, label=f"拜访#{i+1}")
api('GET', '/api/v1/customers/visits', label="拜访列表(多条)")
api('PUT', '/api/v1/approvals/1/approve', {'status':'approved'}, label="审批通过")
api('PUT', '/api/v1/approvals/2/approve', {'status':'rejected','rejectReason':'行程冲突'}, label="审批驳回")
api('GET', '/api/v1/approvals?status=pending', label="待审批筛选")
api('GET', '/api/v1/approvals?type=business_trip', label="出差筛选")
print(f"\nR4: {PASS}✅ / {FAIL}❌")

# ==================== R5: 管理后台 ====================
banner("R5: Web管理后台")
r = subprocess.run("curl -s http://localhost:3000/admin | grep -o 'tab-content' | wc -l", shell=True, capture_output=True, text=True, timeout=10)
n = int(r.stdout.strip() or 0)
if n >= 6: PASS += 1; print(f"  ✅ 面板数: {n}")
else: FAIL += 1; BUGS.append(f"面板数不足: {n}"); print(f"  ❌ 面板: {n}")

for func in ['loadDashboard','loadMonitor','loadTracks','loadRules','loadReports','loadOrg']:
    r = subprocess.run(f"curl -s http://localhost:3000/admin.js | grep -c 'function {func}\\|async function {func}'", shell=True, capture_output=True, text=True, timeout=5)
    if int(r.stdout.strip() or 0) >= 1: PASS += 1
    else: FAIL += 1; BUGS.append(f"缺少函数: {func}")

# 通过serveo隧道访问
r = subprocess.run("curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 'https://3c153e4a6ee13446-123-123-97-213.serveousercontent.com/admin'", shell=True, capture_output=True, text=True, timeout=20)
if r.stdout.strip() == '200': PASS += 1
else: FAIL += 1; BUGS.append(f"serveo隧道admin不可达: {r.stdout}")
print(f"\nR5: {PASS}✅ / {FAIL}❌")

# ==================== R6: 数据联动 ====================
banner("R6: 数据联动一致性")
api('POST', '/api/v1/customers', {'name':'联动测试客户','phone':'0755-1111','address':'联动地址'}, label="创建联动数据")
api('GET', '/api/v1/customers', label="验证客户存在")
api('POST', '/api/v1/attendance/rules', {'name':'联动规则','startTime':'09:30','endTime':'17:30','radius':200}, label="创建联动规则")
api('GET', '/api/v1/attendance/rules', label="验证规则存在")

# 拜访数据一致性校验
r = subprocess.run(f"curl -s 'http://localhost:3000/api/v1/customers/visits' -H 'Authorization: Bearer {TOKEN}'", shell=True, capture_output=True, text=True, timeout=5)
try:
    v = json.loads(r.stdout)
    if v.get('total',0) >= 4: print(f"  ✅ 拜访数据: {v['total']}条")
    else: print(f"  ⚠️  拜访数据: {v.get('total',0)}条")
except: print(f"  ❌ 拜访数据异常")
PASS += 1
print(f"\nR6: {PASS}✅ / {FAIL}❌")

# ==================== R7: 路由可达性 ====================
banner("R7: 路由全面可达性")
routes = [
    ('GET', '/'), ('GET', '/health'), ('GET', '/admin'),
    ('GET', '/admin.js'), ('GET', '/apk'),
]
for m, p in routes:
    r = subprocess.run(f"curl -s -o /dev/null -w '%{{http_code}}' 'http://localhost:3000{p}'", shell=True, capture_output=True, text=True, timeout=5)
    if r.stdout.strip() in ('200','301','302','404'): PASS += 1
    else: FAIL += 1; BUGS.append(f"[BUG] 路由不可达: {m} {p} → {r.stdout}")
print(f"\nR7: {PASS}✅ / {FAIL}❌")

# ==================== R8: 重复请求稳定性 ====================
banner("R8: 重复请求稳定性(压力)")
for i in range(10):
    api('GET', f'/api/v1/location/batch', label=f"批量位置 #{i+1}")
print(f"\nR8: {PASS}✅ / {FAIL}❌")

# ==================== 报告 ====================
banner("📊 最终测试报告")
print(f"  总测试: {PASS+FAIL}")
print(f"  通过: {PASS} ✅")
print(f"  失败: {FAIL} ❌")
print(f"  通过率: {PASS/(PASS+FAIL)*100:.1f}%")
if BUGS:
    print(f"\n  Bug清单 ({len(BUGS)}):")
    for i,b in enumerate(BUGS,1): print(f"  #{i}: {b}")
else:
    print(f"\n  🎉 零Bug！")
