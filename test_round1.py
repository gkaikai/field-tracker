#!/usr/bin/env python3
"""外勤定位APP - 10轮综合测试脚本"""
import subprocess, json, sys, time
from datetime import datetime

PASS = 0
FAIL = 0
BUGS = []

def api(method, path, data=None, expect=200, label=""):
    global PASS, FAIL
    cmd = f"curl -s -o /tmp/test_resp.json -w '%{{http_code}}' -X {method} 'http://localhost:3000{path}' -H 'Content-Type: application/json' -H 'Authorization: Bearer {TOKEN}'"
    if data:
        d = json.dumps(data)
        cmd = f"curl -s -o /tmp/test_resp.json -w '%{{http_code}}' -X {method} 'http://localhost:3000{path}' -H 'Content-Type: application/json' -H 'Authorization: Bearer {TOKEN}' -d '{d}'"
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=15)
    status = r.stdout.strip()
    try:
        with open('/tmp/test_resp.json') as f: resp = json.load(f)
    except: resp = {}
    ok = status == str(expect)
    if ok:
        PASS += 1
    else:
        FAIL += 1
        BUGS.append(f"[BUG] {label}: 期望{expect} 实际{status} | {json.dumps(resp, ensure_ascii=False)[:200]}")
    return ok, resp, status

def banner(title):
    print(f"\n{'='*60}")
    print(f"  {title}")
    print(f"{'='*60}")

# 登录
TOKEN = ""
r = subprocess.run("curl -s http://localhost:3000/api/v1/auth/login -X POST -H 'Content-Type: application/json' -d '{\"phone\":\"13800138000\",\"password\":\"test123456\"}'", shell=True, capture_output=True, text=True, timeout=10)
try:
    TOKEN = json.loads(r.stdout)['token']
except:
    print("❌ 登录失败，无法继续测试")
    sys.exit(1)
print(f"✅ 登录成功 token={TOKEN[:10]}...")

# ==================== 第1轮：核心API功能完整性 ====================
banner("第1轮: 核心API功能完整性测试")
api('POST', '/api/v1/location/report', {'lng':114.08,'lat':22.55,'speed':0}, label="位置上报")
api('POST', '/api/v1/location/report', {'lng':114.09,'lat':22.56,'speed':1.5}, label="位置上报(运动中)")
api('GET', '/api/v1/location/batch', expect=200, label="批量位置查询")
api('GET', '/api/v1/location/current', expect=200, label="当前用户位置")
api('GET', f'/api/v1/location/track/-1?date={datetime.now().strftime("%Y-%m-%d")}', expect=200, label="轨迹查询")
api('POST', '/api/v1/attendance/checkin', {'type':'checkin','lng':114.08,'lat':22.55}, label="签到")
api('POST', '/api/v1/attendance/checkin', {'type':'checkout','lng':114.08,'lat':22.55}, label="签退")
api('GET', '/api/v1/attendance/records?pageSize=5', expect=200, label="打卡记录")
api('GET', '/api/v1/attendance/rules', expect=200, label="打卡规则列表")
api('POST', '/api/v1/attendance/rules', {'name':'办公规则','startTime':'09:00','endTime':'18:00','radius':300}, label="创建打卡规则")
api('POST', '/api/v1/fences', {'name':'公司园区','shapeType':'circle','centerLat':22.55,'centerLng':114.08,'radiusMeters':500}, label="创建围栏")
api('GET', '/api/v1/fences/check?lat=22.55&lng=114.08', expect=200, label="围栏检测(圈内)")
api('GET', '/api/v1/fences/check?lat=22.60&lng=114.15', expect=200, label="围栏检测(圈外)")
api('GET', '/api/v1/fences', expect=200, label="围栏列表")
api('POST', '/api/v1/reports', {'type':'daily','content':'今日拜访3家客户，达成合作意向','summary':'良好'}, label="创建日报")
api('GET', '/api/v1/reports', expect=200, label="汇报列表")
api('POST', '/api/v1/customers', {'name':'深圳科技公司','phone':'0755-88886666','address':'深圳市南山区科技园'}, label="创建客户")
api('GET', '/api/v1/customers', expect=200, label="客户列表")
api('POST', '/api/v1/customers/visit', {'customerId':1,'content':'洽谈合作','lat':22.55,'lng':114.08}, label="拜访记录")
api('GET', '/api/v1/customers/visits', expect=200, label="拜访列表")
api('POST', '/api/v1/approvals', {'type':'leave','title':'请假一天','reason':'身体不适','startDate':'2026-07-18','endDate':'2026-07-18','duration':'1天'}, label="请假申请")
api('POST', '/api/v1/approvals', {'type':'business_trip','title':'深圳出差','reason':'客户拜访','startDate':'2026-07-20','endDate':'2026-07-22','duration':'3天'}, label="出差申请")
api('GET', '/api/v1/approvals', expect=200, label="审批列表")
api('GET', '/api/v1/org/departments', expect=200, label="部门列表")
api('POST', '/api/v1/org/departments', {'name':'销售部','manager':'张三'}, label="新增部门")
api('POST', '/api/v1/org/departments', {'name':'技术部','manager':'李四'}, label="新增部门2")
api('GET', '/api/v1/org/locations/online', expect=200, label="在线人员(含部门)")
api('GET', '/admin', expect=200, label="管理后台页面")
api('GET', '/admin.js', expect=200, label="管理后台JS")
api('GET', '/apk', expect=200, label="APK下载路由")

print(f"\n📊 第1轮结果: {PASS}通过 / {FAIL}失败 / {len(BUGS)}个Bug")

# ==================== 第2轮：边界条件测试 ====================
banner("第2轮: 边界条件测试(空数据/异常参数)")
r2_start = PASS+FAIL
# 空位置
api('POST', '/api/v1/location/report', {}, label="空位置上报", expect=200)
# 极端位置值
api('POST', '/api/v1/location/report', {'lng':180,'lat':90}, label="极值位置(右上)", expect=200)
api('POST', '/api/v1/location/report', {'lng':-180,'lat':-90}, label="极值位置(左下)", expect=200)
# 无效打卡类型
api('POST', '/api/v1/attendance/checkin', {'type':'invalid','lng':114.08,'lat':22.55}, expect=400, label="无效打卡类型")
# 空经纬度打卡
api('POST', '/api/v1/attendance/checkin', {'type':'checkin'}, expect=400, label="缺经纬度打卡")
# 空客户名称
api('POST', '/api/v1/customers', {}, expect=400, label="空客户名创建")
# 围栏检查缺参数
api('GET', '/api/v1/fences/check', expect=400, label="缺参数围栏检测")
# 审批缺必填字段
api('POST', '/api/v1/approvals', {'type':'leave'}, expect=400, label="缺字段审批")
# 查询不存在的轨迹
import datetime as dt
yesterday = (dt.datetime.now() - dt.timedelta(days=1)).strftime("%Y-%m-%d")
api('GET', f'/api/v1/location/track/-1?date={yesterday}', expect=200, label="无数据日期轨迹")
# 超大分页
api('GET', '/api/v1/attendance/records?pageSize=99999', expect=200, label="超大分页")
# 删除不存在的资源
api('DELETE', '/api/v1/fences/99999', expect=404, label="删除不存在的围栏")
api('DELETE', '/api/v1/customers/99999', expect=404, label="删除不存在的客户")
# 搜索为空的关键字
api('GET', '/api/v1/customers?keyword=不存在的客户名', expect=200, label="搜索不存在的客户")
# 无效登录
r = subprocess.run("curl -s http://localhost:3000/api/v1/auth/login -X POST -H 'Content-Type: application/json' -d '{\"phone\":\"13800000000\",\"password\":\"wrong\"}' -o /tmp/test_resp.json -w '%{http_code}'", shell=True, capture_output=True, text=True, timeout=10)
if r.stdout.strip() == '401':
    PASS += 1
else:
    FAIL += 1
    BUGS.append(f"[BUG] 无效登录应返回401，实际{r.stdout}")
r2_end = PASS+FAIL
print(f"\n📊 第2轮结果: +{r2_end-r2_start}测试 / {PASS}累计通过 / {FAIL}累计失败")

# ==================== 第3轮：打卡规则+围栏链路 ====================
banner("第3轮: 打卡规则+围栏逻辑链路测试")
r3_start = PASS+FAIL
# 创建不同距离的围栏
api('POST', '/api/v1/fences', {'name':'大围栏','shapeType':'circle','centerLat':22.55,'centerLng':114.08,'radiusMeters':1000}, label="创建大围栏1000m")
api('POST', '/api/v1/fences', {'name':'小围栏','shapeType':'circle','centerLat':22.55,'centerLng':114.08,'radiusMeters':50}, label="创建小围栏50m")
# 围栏检测 - 不同距离
for dist_name, lat, lng, expect_in in [("围栏中心",22.55,114.08,True),("围栏边缘~300m",22.552,114.083,True),("围栏外~2km",22.57,114.10,False)]:
    ok, r, s = api('GET', f'/api/v1/fences/check?lat={lat}&lng={lng}', expect=200, label=f"围栏检测({dist_name})")
    if ok:
        inside = r.get('results',[{}])[0].get('inside', False)
        if inside != expect_in:
            BUGS.append(f"[BUG] 围栏检测({dist_name}): 期望{'内'if expect_in else'外'} 实际{'内'if inside else'外'}")
            FAIL += 1
        else:
            PASS += 1
# 打卡规则创建不同配置
api('POST', '/api/v1/attendance/rules', {'name':'弹性规则','startTime':'08:30','endTime':'18:30','radius':500,'wifiName':'Office-WiFi'}, label="弹性打卡规则")
api('GET', '/api/v1/attendance/rules', expect=200, label="规则列表(含多条)")
r3_end = PASS+FAIL
print(f"\n📊 第3轮结果: +{r3_end-r3_start}测试 / {PASS}累计通过 / {FAIL}累计失败")

# ==================== 第4轮：审批+客户+拜访完整流程 ====================
banner("第4轮: 审批+客户+拜访完整流程测试")
r4_start = PASS+FAIL
# 客户完整CRUD
api('POST', '/api/v1/customers', {'name':'广州客户','phone':'020-88888888','address':'广州市天河区','tags':['VIP','重点']}, label="创建客户(含标签)")
api('PUT', '/api/v1/customers/1', {'name':'深圳科技公司(更新)','remark':'已合作'}, label="更新客户")
api('GET', '/api/v1/customers', expect=200, label="客户列表(含更新)")
# 拜访多个客户
for i in range(3):
    api('POST', '/api/v1/customers/visit', {'customerId':1,'content':f'第{i+1}次拜访-讨论方案','lat':22.55,'lng':114.08}, label=f"拜访记录#{i+1}")
api('GET', '/api/v1/customers/visits', expect=200, label="拜访记录列表(多条)")
# 审批流程
api('PUT', '/api/v1/approvals/1/approve', {'status':'approved'}, label="审批通过")
api('PUT', '/api/v1/approvals/2/approve', {'status':'rejected','rejectReason':'行程冲突'}, label="审批驳回(含原因)")
api('GET', '/api/v1/approvals?status=pending', expect=200, label="待审批列表")
api('GET', '/api/v1/approvals?type=business_trip', expect=200, label="出差审批筛选")
r4_end = PASS+FAIL
print(f"\n📊 第4轮结果: +{r4_end-r4_start}测试 / {PASS}累计通过 / {FAIL}累计失败")

# ==================== 第5轮：Web管理后台HTML完整性 ====================
banner("第5轮: Web管理后台各面板功能测试")
r5_start = PASS+FAIL
# 检查admin页面HTML包含所有面板
r = subprocess.run("curl -s http://localhost:3000/admin | grep -c 'tab-content'", shell=True, capture_output=True, text=True, timeout=10)
tab_count = int(r.stdout.strip() or 0)
if tab_count >= 6:
    PASS += 1
else:
    FAIL += 1
    BUGS.append(f"[BUG] 管理后台面板数量不足: 期望>=6 实际{tab_count}")
# 检查admin.js包含所有功能函数
for func in ['loadDashboard','loadMonitor','loadTracks','loadRules','loadReports','loadOrg','searchTrack','saveRule','exportExcel','addDept','deleteDept']:
    r = subprocess.run(f"curl -s http://localhost:3000/admin.js | grep -c 'function {func}\\|async function {func}'", shell=True, capture_output=True, text=True, timeout=10)
    if int(r.stdout.strip() or 0) >= 1:
        PASS += 1
    else:
        FAIL += 1
        BUGS.append(f"[BUG] admin.js缺少函数: {func}")
# 通过serveo隧道测试
r = subprocess.run("curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 'https://3c153e4a6ee13446-123-123-97-213.serveousercontent.com/admin'", shell=True, capture_output=True, text=True, timeout=20)
if r.stdout.strip() == '200':
    PASS += 1
else:
    FAIL += 1
    BUGS.append(f"[BUG] serveo隧道admin页面不可达: {r.stdout}")
r5_end = PASS+FAIL
print(f"\n📊 第5轮结果: +{r5_end-r5_start}测试 / {PASS}累计通过 / {FAIL}累计失败")

# ==================== 第6轮：Web后台API联动 ====================
banner("第6轮: Web管理后台API联动测试")
r6_start = PASS+FAIL
# 创建数据->验证数据可查询->验证管理后台可展示
api('POST', '/api/v1/customers', {'name':'联动测试客户','phone':'0755-1111111','address':'联动地址'}, label="创建联动测试数据")
api('GET', '/api/v1/customers?keyword=联动', expect=200, label="关键字搜索客户")
api('POST', '/api/v1/attendance/rules', {'name':'联动规则','startTime':'09:30','endTime':'17:30','radius':200}, label="创建联动规则")
api('GET', '/api/v1/attendance/rules', expect=200, label="验证规则已创建")
r6_end = PASS+FAIL
print(f"\n📊 第6轮结果: +{r6_end-r6_start}测试 / {PASS}累计通过 / {FAIL}累计失败")

# ==================== bug报告 ====================
banner("🐛 BUG汇总报告")
if BUGS:
    print(f"\n共发现 {len(BUGS)} 个Bug:")
    for i, b in enumerate(BUGS, 1):
        print(f"  #{i}: {b}")
else:
    print("\n✅ 本轮测试未发现Bug！")

print(f"\n{'='*60}")
print(f"  累计: {PASS} 通过 / {FAIL} 失败")
print(f"{'='*60}")
