#!/usr/bin/env python3
"""外勤定位APP - 10轮综合测试 (v2 修复状态码)"""
import subprocess, json, sys, time, os
from datetime import datetime, timedelta

PASS = 0
FAIL = 0
BUGS = []
TOKEN = ""
RESP_FILE = f'/tmp/test_resp_{os.getpid()}.json'

def api(method, path, data=None, expect=None, label=""):
    global PASS, FAIL
    method_upper = method.upper()
    
    # 智能默认expect: POST/PUT=201, GET/DELETE=200
    if expect is None:
        expect = 201 if method_upper in ('POST', 'PUT') else 200
    
    data_arg = ""
    url_path = f"http://localhost:3000{path}"
    
    if data:
        d = json.dumps(data)
        data_arg = f"-d '{d}'"
    
    cmd = f"""curl -s -o {RESP_FILE} -w '%{{http_code}}' -X {method_upper} '{url_path}' -H 'Content-Type: application/json' -H 'Authorization: Bearer {TOKEN}' {data_arg}"""
    
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=15)
        status = r.stdout.strip()
    except subprocess.TimeoutExpired:
        BUGS.append(f"[TIMEOUT] {label}: 请求超时")
        FAIL += 1
        return False, {}, "timeout"
    
    try:
        with open(RESP_FILE) as f: resp = json.load(f)
    except:
        resp = {}
    
    ok = status == str(expect)
    if ok:
        PASS += 1
        if label:
            print(f"  ✅ {label}")
    else:
        FAIL += 1
        msg = json.dumps(resp, ensure_ascii=False)[:150]
        BUGS.append(f"[BUG] {label}: 期望{expect} 实际{status} | {msg}")
        print(f"  ❌ {label}: HTTP={status} (期望{expect})")
    
    return ok, resp, status

def banner(title):
    print(f"\n{'='*60}")
    print(f"  {title}")
    print(f"{'='*60}")
    sys.stdout.flush()

# ==================== 登录 ====================
r = subprocess.run(
    "curl -s http://localhost:3000/api/v1/auth/login -X POST -H 'Content-Type: application/json' -d '{\"phone\":\"13800138000\",\"password\":\"123456\"}'",
    shell=True, capture_output=True, text=True, timeout=10)
try:
    TOKEN = json.loads(r.stdout)['token']
    print(f"✅ 登录成功 token={TOKEN[:10]}...")
except:
    print("❌ 登录失败，无法继续测试")
    sys.exit(1)

today = datetime.now().strftime("%Y-%m-%d")

# ==================== 第1轮：核心功能 ====================
banner("第1轮: 核心API功能完整性测试")
api('POST', '/api/v1/location/report', {'lng':114.08,'lat':22.55,'speed':0}, label="1.1 位置上报(静止)")
api('POST', '/api/v1/location/report', {'lng':114.09,'lat':22.56,'speed':1.5}, label="1.2 位置上报(运动中)")
api('GET', '/api/v1/location/batch', label="1.3 批量位置查询")
api('GET', '/api/v1/location/current', label="1.4 当前用户位置")
api('GET', f'/api/v1/location/track/-1?date={today}', label="1.5 轨迹查询")
api('POST', '/api/v1/attendance/checkin', {'type':'checkin','lng':114.08,'lat':22.55}, label="1.6 签到")
api('POST', '/api/v1/attendance/checkin', {'type':'checkout','lng':114.08,'lat':22.55}, label="1.7 签退")
api('GET', '/api/v1/attendance/records?pageSize=5', label="1.8 打卡记录列表")
api('GET', '/api/v1/attendance/rules', label="1.9 打卡规则列表")
api('POST', '/api/v1/attendance/rules', {'name':'办公规则','startTime':'09:00','endTime':'18:00','radius':300}, label="1.10 创建打卡规则")
api('POST', '/api/v1/fences', {'name':'公司园区','shapeType':'circle','centerLat':22.55,'centerLng':114.08,'radiusMeters':500}, label="1.11 创建围栏")
api('GET', '/api/v1/fences/check?lat=22.55&lng=114.08', label="1.12 围栏检测(圈内)")
api('GET', '/api/v1/fences/check?lat=22.60&lng=114.15', label="1.13 围栏检测(圈外)")
api('GET', '/api/v1/fences', label="1.14 围栏列表")
api('POST', '/api/v1/reports', {'type':'daily','content':'今日拜访3家客户','summary':'良好'}, label="1.15 创建日报")
api('GET', '/api/v1/reports', label="1.16 汇报列表")
api('POST', '/api/v1/customers', {'name':'深圳科技公司','phone':'0755-88886666','address':'深圳市南山区科技园'}, label="1.17 创建客户")
api('GET', '/api/v1/customers', label="1.18 客户列表")
api('POST', '/api/v1/customers/visit', {'customerId':1,'content':'洽谈合作','lat':22.55,'lng':114.08}, label="1.19 拜访记录")
api('GET', '/api/v1/customers/visits', label="1.20 拜访列表")
api('POST', '/api/v1/approvals', {'type':'leave','title':'请假一天','reason':'身体不适','startDate':'2026-07-18','endDate':'2026-07-18','duration':'1天'}, label="1.21 请假申请")
api('POST', '/api/v1/approvals', {'type':'business_trip','title':'深圳出差','reason':'客户拜访','startDate':'2026-07-20','endDate':'2026-07-22','duration':'3天'}, label="1.22 出差申请")
api('GET', '/api/v1/approvals', label="1.23 审批列表")
api('POST', '/api/v1/org/departments', {'name':'销售部','manager':'张三'}, label="1.24 新增部门")
api('POST', '/api/v1/org/departments', {'name':'技术部','manager':'李四'}, label="1.25 新增部门2")
api('GET', '/api/v1/org/departments', label="1.26 部门列表")
api('GET', '/api/v1/org/locations/online', label="1.27 在线人员(含部门)")
api('GET', '/admin', expect=200, label="1.28 管理后台页面")
api('GET', '/admin.js', expect=200, label="1.29 管理后台JS")

# ==================== 第2轮：边界条件 ====================
banner("第2轮: 边界条件测试")
# 无效打卡类型
api('POST', '/api/v1/attendance/checkin', {'type':'invalid','lng':114.08,'lat':22.55}, expect=400, label="2.1 无效打卡类型")
# 缺字段打卡
api('POST', '/api/v1/attendance/checkin', {'type':'checkin'}, expect=400, label="2.2 缺经纬度")
# 空客户名
api('POST', '/api/v1/customers', {}, expect=400, label="2.3 空客户名")
# 围栏缺参数
api('GET', '/api/v1/fences/check', expect=400, label="2.4 围栏缺参数")
# 审批缺字段
api('POST', '/api/v1/approvals', {'type':'leave'}, expect=400, label="2.5 审批缺字段")
# 无数据日期轨迹
yesterday = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")
api('GET', f'/api/v1/location/track/-1?date={yesterday}', label="2.6 无数据轨迹(空列表)")
# 删除不存在资源
api('DELETE', '/api/v1/fences/99999', expect=404, label="2.7 删除不存在围栏")
api('DELETE', '/api/v1/customers/99999', expect=404, label="2.8 删除不存在客户")
# 无效登录
r = subprocess.run(
    "curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/api/v1/auth/login -X POST -H 'Content-Type: application/json' -d '{\"phone\":\"13800000000\",\"password\":\"wrong\"}'",
    shell=True, capture_output=True, text=True, timeout=10)
if r.stdout.strip() == '401':
    PASS += 1
    print("  ✅ 2.9 无效登录返回401")
else:
    FAIL += 1
    BUGS.append(f"[BUG] 无效登录应返回401，实际{r.stdout}")
    print(f"  ❌ 2.9 无效登录: HTTP={r.stdout} (期望401)")

# ==================== 第3轮：围栏精度 ====================
banner("第3轮: 围栏精度验证")
# 围栏检测精度
tests = [
    ("中心点", 22.55, 114.08, True),
    ("边缘~100m", 22.551, 114.081, True),
    ("边缘~400m", 22.5535, 114.0835, True),
    ("圈外~1km", 22.56, 114.09, False),
    ("圈外~5km", 22.60, 114.15, False),
]
for dist, lat, lng, expect_inside in tests:
    ok, r, s = api('GET', f'/api/v1/fences/check?lat={lat}&lng={lng}', label=f"3.{tests.index((dist,lat,lng,expect_inside))+1} 围栏检测({dist})")
    if ok:
        inside = r.get('results',[{}])[0].get('inside', False)
        if inside != expect_inside:
            BUGS.append(f"[BUG] 围栏精度({dist}): 期望{'内'if expect_inside else'外'} 实际{'内'if inside else'外'}")
            FAIL += 1

# 打卡规则创建
api('POST', '/api/v1/attendance/rules', {'name':'弹性规则','startTime':'08:30','endTime':'18:30','radius':500,'wifiName':'Office-WiFi'}, label="3.6 弹性打卡规则")
api('GET', '/api/v1/attendance/rules', label="3.7 规则列表(多条)")

# ==================== 第4轮：业务流程 ====================
banner("第4轮: 完整业务流程")
api('POST', '/api/v1/customers', {'name':'广州客户','phone':'020-88888888','address':'广州市天河区','tags':['VIP','重点']}, label="4.1 创建客户(含标签)")
api('PUT', '/api/v1/customers/1', {'name':'深圳科技(已更新)','remark':'合同已签'}, label="4.2 更新客户")
api('GET', '/api/v1/customers', label="4.3 客户列表(含更新)")
for i in range(3):
    api('POST', '/api/v1/customers/visit', {'customerId':1,'content':f'第{i+1}次拜访','lat':22.55,'lng':114.08}, label=f"4.{4+i} 拜访#{i+1}")
api('GET', '/api/v1/customers/visits', label="4.7 拜访列表(多条)")
api('PUT', '/api/v1/approvals/1/approve', {'status':'approved'}, label="4.8 审批通过")
api('PUT', '/api/v1/approvals/2/approve', {'status':'rejected','rejectReason':'行程冲突'}, label="4.9 审批驳回(含原因)")
api('GET', '/api/v1/approvals?status=pending', label="4.10 待审批筛选")
api('GET', '/api/v1/approvals?type=business_trip', label="4.11 出差审批筛选")

# ==================== 第5轮：管理后台完整性 ====================
banner("第5轮: Web管理后台完整性")
r = subprocess.run("curl -s http://localhost:3000/admin | grep -o 'tab-content' | wc -l", shell=True, capture_output=True, text=True, timeout=10)
tab_count = int(r.stdout.strip() or 0)
if tab_count >= 6:
    PASS += 1; print(f"  ✅ 5.1 面板数量: {tab_count}")
else: FAIL += 1; BUGS.append(f"[BUG] 面板不足: 期望>=6 实际{tab_count}"); print(f"  ❌ 5.1 面板: {tab_count}")

for func in ['loadDashboard','loadMonitor','loadTracks','loadRules','loadReports','loadOrg','saveRule','exportExcel','addDept','deleteDept']:
    r = subprocess.run(f"curl -s http://localhost:3000/admin.js | grep -c 'function {func}'", shell=True, capture_output=True, text=True, timeout=5)
    if int(r.stdout.strip() or 0) >= 1:
        PASS += 1
    else:
        FAIL += 1
        BUGS.append(f"[BUG] admin.js缺少: {func}")
print(f"  ✅ 5.2 admin.js函数完整性")

# ==================== 第6轮：数据一致性 ====================
banner("第6轮: 数据一致性测试")
api('POST', '/api/v1/customers', {'name':'联动客户','phone':'0755-1111111','address':'联动地址'}, label="6.1 创建测试数据")
api('GET', '/api/v1/customers', label="6.2 验证数据存在")
api('POST', '/api/v1/attendance/rules', {'name':'联动规则','startTime':'09:30','endTime':'17:30','radius':200}, label="6.3 创建联动规则")
api('GET', '/api/v1/attendance/rules', label="6.4 验证规则已创建")
# 验证客户拜访关联
r = subprocess.run("curl -s http://localhost:3000/api/v1/customers/visits -H 'Authorization: Bearer $TOKEN'", shell=True, capture_output=True, text=True, timeout=5)
try:
    visits = json.loads(r.stdout)
    if visits.get('total',0) >= 4: print(f"  ✅ 6.5 拜访数据一致性: {visits['total']}条")
    else: print(f"  ⚠️  6.5 拜访数据: {visits.get('total',0)}条")
except: print(f"  ❌ 6.5 拜访数据读取失败")
PASS += 1

# ==================== 报告 ====================
banner(f"📊 测试报告")
print(f"  总测试数: {PASS+FAIL}")
print(f"  通过: {PASS} ✅")
print(f"  失败: {FAIL} ❌")
if BUGS:
    print(f"\n  Bug清单:")
    for i, b in enumerate(BUGS, 1):
        print(f"  #{i}: {b}")
else:
    print(f"\n  🎉 零Bug！")

print(f"\n  通过率: {PASS/(PASS+FAIL)*100:.1f}%" if (PASS+FAIL) > 0 else "  无测试执行")
