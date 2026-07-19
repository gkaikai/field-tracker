#!/usr/bin/env python3
"""
外勤定位APP - 10轮×2次 = 20轮完整自动化测试
每轮：R1核心功能 → R2边界 → R3围栏精度 → R4业务流程 → R5管理后台 → R6数据联动 → R7路由 → R8压力 → R9异常恢复 → R10全量回归
"""
import subprocess, json, sys, time, os, math
from datetime import datetime, timedelta

# ============ 全局 ============
PASS = 0; FAIL = 0; BUGS = []; TOKEN = ""; CYCLE = 1; ROUND = 0
RESP_FILE = f'/tmp/test_global_{os.getpid()}.json'
GLOBAL_BUGS_FILE = '/tmp/test_all_bugs.txt'

def log(msg):
    print(msg); sys.stdout.flush()

def curl(method, path, data=None, expect=None, label="", auth=True):
    global PASS, FAIL
    m = method.upper()
    if expect is None: expect = 201 if m == 'POST' else 200
    h = f"-H 'Authorization: Bearer {TOKEN}'" if auth else ""
    d = f"-d '{json.dumps(data)}'" if data else ""
    cmd = f"curl -s -o {RESP_FILE} -w '%{{http_code}}' -X {m} 'http://localhost:3000{path}' -H 'Content-Type: application/json' {h} {d}"
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=15)
        s = r.stdout.strip()
    except:
        BUGS.append(f"[C{CYCLE}R{ROUND} TIMEOUT] {label}"); FAIL += 1; return False, {}, ""
    try:
        with open(RESP_FILE) as f: resp = json.load(f)
    except: resp = {}
    ok = s == str(expect)
    if ok:
        PASS += 1
    else:
        FAIL += 1
        bug = f"[C{CYCLE}R{ROUND} BUG] {label}: 期望{expect} 实际{s} | {json.dumps(resp, ensure_ascii=False)[:150]}"
        BUGS.append(bug)
        log(f"  ❌ {label}: HTTP={s}")
    return ok, resp, s

def login():
    global TOKEN
    r = subprocess.run("curl -s --connect-timeout 5 http://localhost:3000/api/v1/auth/login -X POST -H 'Content-Type: application/json' -d '{\"phone\":\"13800138000\",\"password\":\"test123456\"}'", shell=True, capture_output=True, text=True, timeout=10)
    if r.returncode == 0 and 'token' in r.stdout:
        TOKEN = json.loads(r.stdout)['token']
        return True
    return False

def ensure_server():
    """确保服务器在运行"""
    r = subprocess.run("curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 http://localhost:3000/health", shell=True, capture_output=True, text=True, timeout=5)
    if r.stdout.strip() != '200':
        log("  ⚠️ 服务器未运行，正在启动...")
        subprocess.Popen("cd /Users/openclaw-gkf/development/field_tracker/server && npm start", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(5)
        r = subprocess.run("curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://localhost:3000/health", shell=True, capture_output=True, text=True, timeout=8)
        if r.stdout.strip() != '200':
            log("  ❌ 服务器启动失败！")
            return False
    return True

def banner(title):
    log(f"\n{'='*60}\n  {title}\n{'='*60}")

def run_rounds():
    """执行 R1~R8（前8轮，不包含重启）"""
    global ROUND, PASS, FAIL, BUGS
    today = datetime.now().strftime("%Y-%m-%d")
    
    # =============== R1: 核心功能完整 ===============
    ROUND = 1; banner(f"第{CYCLE}轮周期 → R{ROUND}: 核心API功能完整性")
    curl('POST','/api/v1/location/report',{'lng':114.08,'lat':22.55,'speed':0})
    curl('POST','/api/v1/location/report',{'lng':114.09,'lat':22.56,'speed':1.5})
    curl('GET','/api/v1/location/batch')
    curl('GET','/api/v1/location/current')
    curl('GET',f'/api/v1/location/track/-1?date={today}')
    curl('POST','/api/v1/attendance/checkin',{'type':'checkin','lng':114.08,'lat':22.55})
    curl('POST','/api/v1/attendance/checkin',{'type':'checkout','lng':114.08,'lat':22.55})
    curl('GET','/api/v1/attendance/records?pageSize=5')
    curl('GET','/api/v1/attendance/rules')
    curl('POST','/api/v1/attendance/rules',{'name':f'规则{RAND}','startTime':'09:00','endTime':'18:00','radius':300})
    curl('POST','/api/v1/fences',{'name':f'围栏{RAND}','shapeType':'circle','centerLat':22.55,'centerLng':114.08,'radiusMeters':500})
    curl('GET','/api/v1/fences/check?lat=22.55&lng=114.08')
    curl('GET','/api/v1/fences')
    curl('POST','/api/v1/reports',{'type':'daily','content':f'R{CYCLE}日报测试','summary':'良好'})
    curl('GET','/api/v1/reports')
    curl('POST','/api/v1/customers',{'name':f'客户{RAND}','phone':'0755-88886666','address':'深圳'})
    curl('GET','/api/v1/customers')
    curl('POST','/api/v1/customers/visit',{'customerId':1,'content':f'R{CYCLE}拜访','lat':22.55,'lng':114.08})
    curl('GET','/api/v1/customers/visits')
    curl('POST','/api/v1/approvals',{'type':'leave','title':f'R{CYCLE}请假','reason':'事假','startDate':today,'endDate':today,'duration':'1天'})
    curl('POST','/api/v1/approvals',{'type':'business_trip','title':f'R{CYCLE}出差','reason':'客户','startDate':today,'endDate':today,'duration':'3天'})
    curl('GET','/api/v1/approvals')
    curl('POST','/api/v1/org/departments',{'name':f'部门{RAND}','manager':'测试'})
    curl('GET','/api/v1/org/departments')
    curl('GET','/api/v1/org/locations/online')
    curl('GET','/admin',expect=200)
    curl('GET','/admin.js',expect=200)
    
    # =============== R2: 边界条件 ===============
    ROUND = 2; banner(f"第{CYCLE}轮周期 → R{ROUND}: 边界条件测试")
    curl('POST','/api/v1/attendance/checkin',{'type':'invalid','lng':114.08,'lat':22.55},expect=400)
    curl('POST','/api/v1/attendance/checkin',{'type':'checkin'},expect=400)
    curl('POST','/api/v1/customers',{},expect=400)
    curl('GET','/api/v1/fences/check',expect=400)
    curl('POST','/api/v1/approvals',{'type':'leave'},expect=400)
    api_yd = (datetime.now()-timedelta(days=1)).strftime("%Y-%m-%d")
    curl('GET',f'/api/v1/location/track/-1?date={api_yd}')
    curl('DELETE','/api/v1/fences/99999',expect=404)
    curl('DELETE','/api/v1/customers/99999',expect=404)
    r = subprocess.run("curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://localhost:3000/api/v1/auth/login -X POST -H 'Content-Type: application/json' -d '{\"phone\":\"13800138000\",\"password\":\"wrongpass789\"}'", shell=True, capture_output=True, text=True, timeout=10)
    if r.stdout.strip() == '401': PASS += 1
    else: FAIL += 1; BUGS.append(f"[C{CYCLE}R{ROUND} BUG] 无效登录: 期望401 实际{r.stdout}")

    # =============== R3: 围栏精度 ===============
    ROUND = 3; banner(f"第{CYCLE}轮周期 → R{ROUND}: 围栏精度验证")
    CLAT, CLNG = 22.55, 114.08
    for nm, dlat, dlng in [("中心0m",0,0),("北100m",0.0009,0),("东100m",0,0.0009),("东北200m",0.0015,0.0015),("东北350m",0.0025,0.0025),("圈外800m",0.005,0.005),("圈外2km",0.012,0.012)]:
        lat=CLAT+dlat; lng=CLNG+dlng
        d=R=6371000; dlat_r=math.radians(dlat); dlng_r=math.radians(dlng)
        a=math.sin(dlat_r/2)**2+math.cos(math.radians(CLAT))*math.cos(math.radians(lat))*math.sin(dlng_r/2)**2
        d=R*2*math.atan2(math.sqrt(a),math.sqrt(1-a))
        expected_inside = d <= 500
        ok, rsp, _ = curl('GET',f'/api/v1/fences/check?lat={lat}&lng={lng}',label=f"围栏({nm} d={d:.0f}m)")
        if ok:
            actual = rsp.get('results',[{}])[0].get('inside',False)
            if actual != expected_inside:
                FAIL += 1; BUGS.append(f"[C{CYCLE}R{ROUND} BUG] 围栏精度({nm}): 距离{d:.0f}m 期望{'内'if expected_inside else'外'} 实际{'内'if actual else'外'}")

    # =============== R4: 业务流程 ===============
    ROUND = 4; banner(f"第{CYCLE}轮周期 → R{ROUND}: 完整业务流程")
    curl('POST','/api/v1/customers',{'name':f'VIP-{RAND}','phone':'020-8888','address':'广州','tags':['VIP','重点']})
    curl('PUT','/api/v1/customers/1',{'name':f'客户-{RAND}(已更新)','remark':'已签约'})
    curl('GET','/api/v1/customers')
    for i in range(3):
        curl('POST','/api/v1/customers/visit',{'customerId':1,'content':f'R{CYCLE}-第{i+1}次拜访','lat':22.55,'lng':114.08})
    curl('GET','/api/v1/customers/visits')
    curl('PUT','/api/v1/approvals/1/approve',{'status':'approved'})
    curl('PUT','/api/v1/approvals/2/approve',{'status':'rejected','rejectReason':'R{CYCLE}行程冲突'})
    curl('GET','/api/v1/approvals?status=pending')
    curl('GET','/api/v1/approvals?type=business_trip')

    # =============== R5: 管理后台 ===============
    ROUND = 5; banner(f"第{CYCLE}轮周期 → R{ROUND}: Web管理后台")
    r = subprocess.run("curl -s --connect-timeout 5 http://localhost:3000/admin | grep -o 'tab-content' | wc -l", shell=True, capture_output=True, text=True, timeout=10)
    n = int(r.stdout.strip() or 0)
    if n >= 6: PASS += 1
    else: FAIL += 1; BUGS.append(f"[C{CYCLE}R{ROUND} BUG] 面板数不足: {n}")
    for func in ['loadDashboard','loadMonitor','loadTracks','loadRules','loadReports','loadOrg','saveRule','exportExcel','addDept','deleteDept']:
        r = subprocess.run(f"curl -s --connect-timeout 5 http://localhost:3000/admin.js | grep -c 'function {func}\\|async function {func}'", shell=True, capture_output=True, text=True, timeout=5)
        if int(r.stdout.strip() or 0) >= 1: PASS += 1
        else: FAIL += 1; BUGS.append(f"[C{CYCLE}R{ROUND} BUG] admin.js缺少: {func}")
    r = subprocess.run("curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 'https://3c153e4a6ee13446-123-123-97-213.serveousercontent.com/admin'", shell=True, capture_output=True, text=True, timeout=20)
    if r.stdout.strip() == '200': PASS += 1
    else: FAIL += 1; BUGS.append(f"[C{CYCLE}R{ROUND} BUG] serveo隧道admin不可达: {r.stdout}")

    # =============== R6: 数据联动 ===============
    ROUND = 6; banner(f"第{CYCLE}轮周期 → R{ROUND}: 数据联动一致性")
    curl('POST','/api/v1/customers',{'name':f'联动-{RAND}','phone':'0755-1111','address':'联动地址'})
    curl('GET','/api/v1/customers')
    curl('POST','/api/v1/attendance/rules',{'name':f'联动规则-{RAND}','startTime':'09:30','endTime':'17:30','radius':200})
    curl('GET','/api/v1/attendance/rules')

    # =============== R7: 路由可达 ===============
    ROUND = 7; banner(f"第{CYCLE}轮周期 → R{ROUND}: 路由全面可达性")
    for m, p in [('GET','/'),('GET','/health'),('GET','/admin'),('GET','/admin.js'),('GET','/apk')]:
        r = subprocess.run(f"curl -s -o /dev/null -w '%{{http_code}}' --connect-timeout 5 'http://localhost:3000{p}'", shell=True, capture_output=True, text=True, timeout=5)
        if r.stdout.strip() in ('200','301','302','404'): PASS += 1
        else: FAIL += 1; BUGS.append(f"[C{CYCLE}R{ROUND} BUG] 路由不可达: {p} → {r.stdout}")

    # =============== R8: 压力 ===============
    ROUND = 8; banner(f"第{CYCLE}轮周期 → R{ROUND}: 重复请求稳定性(10次)")
    for i in range(10):
        curl('GET','/api/v1/location/batch',label=f"批量位置 #{i+1}")

def run_r9():
    """R9: 异常恢复（服务器重启）"""
    global ROUND, TOKEN, PASS, FAIL, BUGS
    ROUND = 9; banner(f"第{CYCLE}轮周期 → R{ROUND}: 异常恢复(服务器重启)")
    curl('POST','/api/v1/location/report',{'lng':114.08,'lat':22.55},label="重启前-上报")
    curl('POST','/api/v1/attendance/checkin',{'type':'checkin','lng':114.08,'lat':22.55},label="重启前-签到")
    curl('POST','/api/v1/customers',{'name':f'重启前-{RAND}'},label="重启前-客户")
    curl('GET','/api/v1/location/batch',label="重启前-验证")
    log("  🔄 模拟服务器重启...")
    subprocess.run("kill -9 $(lsof -ti:3000) 2>/dev/null", shell=True, timeout=5)
    time.sleep(3)
    subprocess.Popen("cd /Users/openclaw-gkf/development/field_tracker/server && npm start", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(5)
    if login():
        log("  ✅ 重启后登录成功"); PASS += 1
    else:
        log("  ❌ 重启后登录失败"); BUGS.append(f"[C{CYCLE}R9 BUG] 重启后登录失败"); FAIL += 1
    curl('GET','/health',expect=200,label="重启后-健康检查")
    curl('GET','/api/v1/location/batch',label="重启后-位置(空)")
    curl('GET','/api/v1/location/current',expect=404,label="重启后-当前位置(内存丢失)")
    curl('GET','/api/v1/attendance/records',label="重启后-打卡记录(空)")
    curl('POST','/api/v1/location/report',{'lng':114.08,'lat':22.55},label="重启后-新上报")
    curl('GET','/api/v1/location/batch',label="重启后-新数据验证")
    curl('POST','/api/v1/attendance/checkin',{'type':'checkin','lng':114.08,'lat':22.55},label="重启后-新签到")
    curl('GET','/api/v1/attendance/records',label="重启后-新打卡记录")
    curl('GET','/api/v1/fences',label="重启后-围栏(空)")
    curl('GET','/api/v1/attendance/rules',label="重启后-规则(空)")

def run_r10():
    """R10: 全量回归"""
    global ROUND, PASS, FAIL, BUGS
    ROUND = 10; banner(f"第{CYCLE}轮周期 → R{ROUND}: 最终全量回归")
    today = datetime.now().strftime("%Y-%m-%d")
    tests = [
        # R1
        ('POST','/api/v1/location/report',{'lng':114.08,'lat':22.55},201),
        ('GET','/api/v1/location/batch',None,200), ('GET','/api/v1/location/current',None,200),
        ('GET',f'/api/v1/location/track/-1?date={today}',None,200),
        ('POST','/api/v1/attendance/checkin',{'type':'checkin','lng':114.08,'lat':22.55},201),
        ('POST','/api/v1/attendance/checkin',{'type':'checkout','lng':114.08,'lat':22.55},201),
        ('GET','/api/v1/attendance/records',None,200), ('GET','/api/v1/attendance/rules',None,200),
        ('POST','/api/v1/attendance/rules',{'name':f'回归规则{CYCLE}','startTime':'09:00','endTime':'18:00','radius':300},201),
        ('POST','/api/v1/fences',{'name':f'回归围栏{CYCLE}','shapeType':'circle','centerLat':22.55,'centerLng':114.08,'radiusMeters':500},201),
        ('GET','/api/v1/fences/check?lat=22.55&lng=114.08',None,200), ('GET','/api/v1/fences',None,200),
        ('POST','/api/v1/reports',{'type':'daily','content':f'回归{CYCLE}日报'},201), ('GET','/api/v1/reports',None,200),
        ('POST','/api/v1/customers',{'name':f'回归客户{CYCLE}','phone':'0755-0000'},201), ('GET','/api/v1/customers',None,200),
        ('POST','/api/v1/customers/visit',{'customerId':1,'content':f'回归{CYCLE}拜访','lat':22.55,'lng':114.08},201),
        ('GET','/api/v1/customers/visits',None,200),
        ('POST','/api/v1/approvals',{'type':'leave','title':f'回归{CYCLE}请假','reason':'测试','startDate':today,'endDate':today,'duration':'1天'},201),
        ('GET','/api/v1/approvals',None,200),
        ('POST','/api/v1/org/departments',{'name':f'回归部{CYCLE}','manager':'测试'},201), ('GET','/api/v1/org/departments',None,200),
        ('GET','/api/v1/org/locations/online',None,200), ('GET','/admin',None,200), ('GET','/admin.js',None,200),
        # R2
        ('POST','/api/v1/attendance/checkin',{'type':'invalid','lng':114.08,'lat':22.55},400),
        ('POST','/api/v1/attendance/checkin',{'type':'checkin'},400), ('POST','/api/v1/customers',{},400),
        ('GET','/api/v1/fences/check',None,400), ('DELETE','/api/v1/fences/99999',None,404),
        # R3
        ('GET','/api/v1/fences/check?lat=22.55&lng=114.08',None,200),
        ('GET','/api/v1/fences/check?lat=22.551&lng=114.081',None,200),
        ('GET','/api/v1/fences/check?lat=22.56&lng=114.09',None,200),
        # R4
        ('POST','/api/v1/customers',{'name':f'回归VIP{CYCLE}','phone':'020-1111'},201),
        ('PUT','/api/v1/customers/1',{'name':f'回归{CYCLE}(更新)'},200),
        ('PUT','/api/v1/approvals/1/approve',{'status':'approved'},200),
        # R5+R7
        ('GET','/admin',None,200), ('GET','/admin.js',None,200),
        ('GET','/health',None,200), ('GET','/apk',None,200),
    ]
    for i, (m, p, d, e) in enumerate(tests, 1):
        curl(m, p, d, e, label=f"R10-{i:02d} {m} {p}")

def report():
    global PASS, FAIL, BUGS
    banner(f"📊 第{CYCLE}轮周期最终报告")
    log(f"  总测试: {PASS+FAIL}")
    log(f"  通过: {PASS} ✅")
    log(f"  失败: {FAIL} ❌")
    log(f"  通过率: {PASS/(PASS+FAIL)*100:.1f}%")
    if BUGS:
        with open(GLOBAL_BUGS_FILE, 'a') as f:
            f.write(f"\n=== 第{CYCLE}轮周期 ({datetime.now().strftime('%H:%M:%S')}) ===\n")
            for b in BUGS: f.write(b + "\n")
        log(f"  Bug ({len(BUGS)}个):")
        for i,b in enumerate(BUGS,1): log(f"  #{i}: {b}")
    else:
        log(f"  🎉 零Bug！")
    # 保存全局统计
    with open(f'/tmp/test_cycle_{CYCLE}_result.txt', 'w') as f:
        f.write(f"Cycle:{CYCLE} Pass:{PASS} Fail:{FAIL} Rate:{PASS/(PASS+FAIL)*100:.1f}% Bugs:{len(BUGS)}\n")

# ============ 主入口 ============
if __name__ == '__main__':
    OPEN_BUGS = 0
    for CYCLE in range(1, 3):  # 2个完整周期
        RAND = int(time.time()) % 10000
        PASS = 0; FAIL = 0; BUGS = []
        log(f"\n{'#'*70}")
        log(f"  {'#'*66}")
        log(f"  ##   开始第 {CYCLE}/2 轮周期测试 ({datetime.now().strftime('%Y-%m-%d %H:%M:%S')})")
        log(f"  {'#'*66}")
        log(f"{'#'*70}")

        if not ensure_server():
            log("❌ 服务器不可用，终止测试")
            sys.exit(1)
        if not login():
            log("❌ 登录失败，终止测试")
            sys.exit(1)
        log(f"✅ 服务器就绪 | TOKEN={TOKEN[:10]}...")

        # 执行 R1~R8
        run_rounds()
        # 执行 R9（含服务器重启）
        run_r9()
        # 执行 R10（重启后的全量回归）
        run_r10()
        # 报告
        report()
        OPEN_BUGS += len(BUGS)

        # 确保第2轮开始前服务器正常
        if CYCLE == 1:
            ensure_server()
            if not login():
                # 如果登录失败可能还没起好，再等
                time.sleep(3)
                ensure_server()
                login()

    # ============ 最终总报告 ============
    log(f"\n{'='*70}")
    log(f"  🏆🏆🏆 全部2个周期 × 10轮 = 20轮测试完成！🏆🏆🏆")
    log(f"{'='*70}")
    log(f"  总周期: 2个（每周期10轮）")
    log(f"  总Bug数: {OPEN_BUGS}")
    log(f"  详细Bug记录: {GLOBAL_BUGS_FILE}")
    if OPEN_BUGS == 0:
        log(f"  🎉🎉🎉 20轮测试零Bug！🎉🎉🎉")
    log(f"{'='*70}")
