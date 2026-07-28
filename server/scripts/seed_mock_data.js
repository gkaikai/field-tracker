/**
 * 批量生成模拟数据 — 覆盖所有业务表
 * 使用 PostgreSQL gen_random_uuid() 生成ID
 * 三个端都可以拉取验证
 */
const { Pool } = require('pg');
const pool = new Pool({host:'localhost',port:5432,database:'field_tracker',user:'postgres',password:'postgres'});

// 固定参考用的已有部门ID
const EXISTING_DEPT_ID = '8a19b6a4-7b65-48f7-9aae-5197949966ce'; // 默认部门

// 已有用户ID（勿重复创建）
const EXISTING_USERS = [
  'e5a01fa9-fbd1-4fee-b220-0d04457c3c8c',
  '268e6bb5-69da-4730-874b-bbb9bc31d664',
  '2d9b8845-1aff-42c8-bcd5-2c9ac4ac57f0',
  '064a6cf0-de57-4bc8-8ad5-5a1ed697f714',
];

async function seed() {
  console.log('🌱 开始生成模拟数据...\n');

  // ============================
  // 1. 新部门（2个）
  // ============================
  console.log('📁 1. 创建新部门...');
  const depts = await pool.query(`
    INSERT INTO departments (id, name, parent_id, description, sort_order)
    VALUES
      (gen_random_uuid(), '项目部', $1, '项目管理部', 1),
      (gen_random_uuid(), '市场部', $1, '市场营销部', 2)
    RETURNING id, name
  `, [EXISTING_DEPT_ID]);
  const [projDeptId, marketDeptId] = depts.rows.map(r => r.id);
  console.log(`   - ${depts.rows[0].name}: ${projDeptId}`);
  console.log(`   - ${depts.rows[1].name}: ${marketDeptId}`);

  // ============================
  // 2. 新用户（6个，每个部门3个）
  // ============================
  console.log('\n👤 2. 创建新用户...');
  const newUsers = [
    {name:'赵工', phone:'13600136001', role:'employee', dept:projDeptId},
    {name:'钱工', phone:'13600136002', role:'employee', dept:projDeptId},
    {name:'孙经理', phone:'13600136003', role:'manager', dept:projDeptId},
    {name:'周销售', phone:'13600136004', role:'employee', dept:marketDeptId},
    {name:'吴销售', phone:'13600136005', role:'employee', dept:marketDeptId},
    {name:'郑经理', phone:'13600136006', role:'manager', dept:marketDeptId},
  ];
  const userIds = [];
  for (const u of newUsers) {
    const hash = await require('bcryptjs').hash('123456', 10);
    const r = await pool.query(`
      INSERT INTO users (id, name, phone, password_hash, department_id, role, is_active)
      VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, true)
      RETURNING id, name, role, department_id
    `, [u.name, u.phone, hash, u.dept, u.role]);
    userIds.push(r.rows[0]);
    console.log(`   - ${r.rows[0].name}(${u.role}) created`);
  }

  // 所有可用用户ID（已有+新）
  const allUserIds = [...EXISTING_USERS, ...userIds.map(u => u.id)];
  const allDeptIds = [EXISTING_DEPT_ID, projDeptId, marketDeptId];

  // ============================
  // 3. 打卡规则（每个部门1条）
  // ============================
  console.log('\n📋 3. 创建打卡规则...');
  for (const deptId of allDeptIds) {
    const deptName = deptId === EXISTING_DEPT_ID ? '默认部' :
                     deptId === projDeptId ? '项目部' : '市场部';
    await pool.query(`
      INSERT INTO attendance_rules (id, name, department_id, rule_type, center_lat, center_lng, radius_meters, checkin_start, checkin_end)
      VALUES (gen_random_uuid(), $1, $2, 'location', $3, $4, 500, '09:00', '18:00')
    `, [`${deptName}打卡规则`, deptId, 34.61 + Math.random()*0.01, 113.90 + Math.random()*0.01]);
    console.log(`   - ${deptName}打卡规则`);
  }

  // ============================
  // 4. 批量打卡记录（每个用户最近7天每天2条）
  // ============================
  console.log('\n🕐 4. 批量生成打卡记录...');
  let checkinCount = 0;
  for (const uid of allUserIds) {
    for (let day = 0; day < 7; day++) {
      const date = new Date(Date.now() - day * 86400000);
      // 80%概率打卡
      if (Math.random() < 0.8) {
        // 上班
        const checkinTime = new Date(date);
        checkinTime.setHours(8, 50 + Math.floor(Math.random()*30), 0, 0);
        await pool.query(`
          INSERT INTO attendance_records (user_id, type, lng, lat, address, accuracy, check_time, source, status)
          VALUES ($1, 'checkin', $2, $3, $4, $5, $6, 'app', 'normal')
        `, [uid, 113.90+Math.random()*0.02, 34.61+Math.random()*0.01, '模拟打卡-公司附近', 10+Math.random()*20, checkinTime]);
        checkinCount++;

        // 下班（70%概率）
        if (Math.random() < 0.7) {
          const checkoutTime = new Date(date);
          checkoutTime.setHours(18, 0 + Math.floor(Math.random()*30), 0, 0);
          await pool.query(`
            INSERT INTO attendance_records (user_id, type, lng, lat, address, accuracy, check_time, source, status)
            VALUES ($1, 'checkout', $2, $3, $4, $5, $6, 'app', 'normal')
          `, [uid, 113.90+Math.random()*0.02, 34.61+Math.random()*0.01, '模拟打卡-公司附近', 10+Math.random()*20, checkoutTime]);
          checkinCount++;
        }
      }
    }
  }
  console.log(`   - 生成 ${checkinCount} 条打卡记录`);

  // ============================
  // 5. 批量位置轨迹（每天500点/每人）
  // ============================
  console.log('\n📍 5. 批量生成模拟轨迹...');
  let locCount = 0;
  for (const uid of allUserIds.slice(0, 6)) { // 前6个用户有轨迹
    // 模拟3天轨迹，每天8:00-18:00每2分钟一个点
    for (let day = 0; day < 3; day++) {
      const baseLat = 34.61 + Math.random() * 0.02;
      const baseLng = 113.90 + Math.random() * 0.02;
      for (let t = 0; t < 300; t++) {
        const recordedAt = new Date(Date.now() - day * 86400000 - (t * 120 * 1000));
        const driftLat = (Math.random() - 0.5) * 0.002;
        const driftLng = (Math.random() - 0.5) * 0.002;
        try {
          await pool.query(`
            INSERT INTO location_records (user_id, lng, lat, accuracy, speed, recorded_at, provider)
            VALUES ($1, $2, $3, $4, $5, $6, 'gps')
          `, [uid, baseLng+driftLng, baseLat+driftLat, 5+Math.random()*15, Math.random()*3, recordedAt]);
          locCount++;
        } catch(e) {/* 分区表可能报错跳过 */}
      }
    }
  }
  console.log(`   - 生成 ${locCount} 条轨迹点`);

  // ============================
  // 6. 模拟围栏事件
  // ============================
  console.log('\n🚧 6. 批量生成围栏事件...');
  const fences = (await pool.query('SELECT id, name FROM geo_fences LIMIT 3')).rows;
  let fenceEventCount = 0;
  for (const uid of allUserIds.slice(0, 4)) {
    for (const fence of fences) {
      for (let i = 0; i < 3; i++) { // 每人每个围栏3次进出
        const eventTime = new Date(Date.now() - Math.random()*7*86400000);
        await pool.query(`
          INSERT INTO fence_events (user_id, fence_id, event_type, lng, lat, accuracy, event_time)
          VALUES ($1, $2, $3, $4, $5, $6, $7)
        `, [uid, fence.id, i%2===0?'enter':'exit', 113.90+Math.random()*0.01, 34.61+Math.random()*0.005, 5+Math.random()*15, eventTime]);
        fenceEventCount++;
      }
    }
  }
  console.log(`   - 生成 ${fenceEventCount} 条围栏事件`);

  // ============================
  // 7. 模拟客户（10个）
  // ============================
  console.log('\n🏢 7. 创建模拟客户...');
  const mockCustomers = [
    {name:'华为技术有限公司', phone:'0755-88888888', address:'深圳市龙岗区坂田街道', lng:114.06, lat:22.65, industry:'科技', level:'A'},
    {name:'腾讯科技', phone:'0755-86013388', address:'深圳市南山区海天二路33号', lng:113.93, lat:22.52, industry:'互联网', level:'A'},
    {name:'阿里巴巴集团', phone:'0571-85022088', address:'杭州市余杭区文一西路969号', lng:120.02, lat:30.28, industry:'互联网', level:'A'},
    {name:'比亚迪股份有限公司', phone:'0755-89888888', address:'深圳市坪山区比亚迪路3009号', lng:114.36, lat:22.69, industry:'汽车', level:'B'},
    {name:'大疆创新', phone:'0755-36383222', address:'深圳市南山区高新南九道', lng:113.94, lat:22.53, industry:'无人机', level:'A'},
    {name:'中兴通讯', phone:'0755-26770000', address:'深圳市南山区高新技术产业园', lng:113.95, lat:22.54, industry:'通信', level:'B'},
    {name:'字节跳动', phone:'010-83448658', address:'北京市海淀区知春路甲48号', lng:116.33, lat:39.98, industry:'互联网', level:'B'},
    {name:'小米科技', phone:'010-60606666', address:'北京市海淀区清河中街68号', lng:116.33, lat:40.03, industry:'消费电子', level:'B'},
    {name:'宁德时代', phone:'0593-8902888', address:'宁德市蕉城区漳湾镇新港路2号', lng:119.55, lat:26.67, industry:'新能源', level:'A'},
    {name:'京东集团', phone:'010-89118888', address:'北京市亦庄经济开发区科创十一街18号', lng:116.58, lat:39.80, industry:'电商', level:'C'},
  ];
  const customerIds = [];
  for (const c of mockCustomers) {
    const r = await pool.query(`
      INSERT INTO customers (id, name, phone, address, lng, lat, industry, level, status, is_active, created_by)
      VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, 'active', true, $8)
      RETURNING id, name
    `, [c.name, c.phone, c.address, c.lng, c.lat, c.industry, c.level, allUserIds[Math.floor(Math.random()*allUserIds.length)]]);
    customerIds.push(r.rows[0]);
    console.log(`   - ${r.rows[0].name}`);
  }

  // ============================
  // 8. 拜访记录（每个客户1-3条）
  // ============================
  console.log('\n📞 8. 生成拜访记录...');
  let visitCount = 0;
  for (const c of customerIds) {
    const visitCounts = 1 + Math.floor(Math.random() * 3);
    for (let i = 0; i < visitCounts; i++) {
      const visitTime = new Date(Date.now() - Math.random()*14*86400000);
      await pool.query(`
        INSERT INTO visit_records (id, user_id, customer_id, visit_type, status, content, signin_lng, signin_lat, signin_address, created_at)
        VALUES (gen_random_uuid(), $1, $2, 'field', 'completed', $3, $4, $5, $6, $7)
      `, [
        allUserIds[Math.floor(Math.random()*allUserIds.length)],
        c.id,
        `客户拜访-${['方案交流','合同签署','产品演示','售后回访'][Math.floor(Math.random()*4)]}`,
        113.90+Math.random()*0.02, 34.61+Math.random()*0.01,
        '模拟拜访地址-' + Math.random().toString(36).slice(2,8),
        visitTime
      ]);
      visitCount++;
    }
  }
  console.log(`   - 生成 ${visitCount} 条拜访记录`);

  // ============================
  // 9. 审批记录
  // ============================
  console.log('\n📑 9. 生成审批记录...');
  const approvalTypes = [
    {type:'leave', title:'请假', reason:'年假', duration:1},
    {type:'leave', title:'病假', reason:'身体不适', duration:2},
    {type:'business_trip', title:'出差', reason:'客户拜访', duration:3},
    {type:'business_trip', title:'会议出差', reason:'行业会议', duration:1},
    {type:'overtime', title:'加班', reason:'项目赶工', duration:4},
    {type:'expense', title:'报销', reason:'差旅费', amount:1500},
    {type:'expense', title:'采购', reason:'办公用品', amount:800},
  ];
  let approvalCount = 0;
  for (const uid of allUserIds) {
    // 每人2-3条审批
    const n = 2 + Math.floor(Math.random() * 2);
    for (let i = 0; i < n; i++) {
      const t = approvalTypes[Math.floor(Math.random() * approvalTypes.length)];
      const createdTime = new Date(Date.now() - Math.random()*10*86400000);
      await pool.query(`
        INSERT INTO approvals (id, applicant_id, type, title, reason, status, duration, amount, created_at)
        VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8)
      `, [uid, t.type, t.title, t.reason, Math.random()>0.3?'approved':'pending', t.duration||0, t.amount||0, createdTime]);
      approvalCount++;
    }
  }
  console.log(`   - 生成 ${approvalCount} 条审批记录`);

  // ============================
  // 10. 照片记录
  // ============================
  console.log('\n📸 10. 生成模拟照片记录...');
  for (let i = 0; i < 20; i++) {
    const uid = allUserIds[Math.floor(Math.random() * allUserIds.length)];
    await pool.query(`
      INSERT INTO photos (id, user_id, biz_type, url, lng, lat, address, taken_at)
      VALUES (gen_random_uuid(), $1, 'checkin', $2, $3, $4, $5, $6)
    `, [
      uid,
      `https://picsum.photos/seed/${Math.random().toString(36).slice(2)}/400/300`,
      113.90 + Math.random()*0.02,
      34.61 + Math.random()*0.02,
      ['公司前台','会议室','客户现场','外勤打卡'][Math.floor(Math.random()*4)],
      new Date(Date.now() - Math.random()*7*86400000)
    ]);
  }
  console.log(`   - 生成 20 条照片记录`);

  // ============================
  // 11. 工作汇报
  // ============================
  console.log('\n📝 11. 生成工作汇报...');
  for (const uid of allUserIds) {
    for (let day = 0; day < 5; day++) {
      const reportDate = new Date(Date.now() - day * 86400000);
      await pool.query(`
        INSERT INTO reports (id, user_id, type, content, date, created_at)
        VALUES (gen_random_uuid(), $1, 'daily', $2, $3, $3)
      `, [
        uid,
        `今日工作内容：\n1. 完成了${['项目开发','客户拜访','方案评审','合同整理','代码审核','会议沟通'][Math.floor(Math.random()*6)]}\n2. 处理了${Math.floor(Math.random()*5+1)}个问题\n3. 明日计划：${['继续开发','整理文档','跟进客户','方案汇报'][Math.floor(Math.random()*4)]}`,
        reportDate
      ]);
    }
  }
  console.log(`   - 生成 ${allUserIds.length * 5} 条工作汇报`);

  // ============================
  // 完成
  // ============================
  console.log('\n✅ 模拟数据生成完成！');
  console.log('\n📊 数据统计:');
  const stats = await pool.query(`
    SELECT 'users' as tbl, COUNT(*) as cnt FROM users
    UNION ALL SELECT 'departments', COUNT(*) FROM departments
    UNION ALL SELECT 'attendance_rules', COUNT(*) FROM attendance_rules
    UNION ALL SELECT 'attendance_records', COUNT(*) FROM attendance_records
    UNION ALL SELECT 'location_records', COUNT(*) FROM location_records
    UNION ALL SELECT 'geo_fences', COUNT(*) FROM geo_fences
    UNION ALL SELECT 'fence_events', COUNT(*) FROM fence_events
    UNION ALL SELECT 'customers', COUNT(*) FROM customers
    UNION ALL SELECT 'visit_records', COUNT(*) FROM visit_records
    UNION ALL SELECT 'approvals', COUNT(*) FROM approvals
    UNION ALL SELECT 'photos', COUNT(*) FROM photos
    UNION ALL SELECT 'reports', COUNT(*) FROM reports
    ORDER BY tbl
  `);
  for (const row of stats.rows) {
    console.log(`   ${row.tbl.padEnd(20)} ${row.cnt}`);
  }

  pool.end();
}

seed().catch(e => { console.error('❌ 错误:', e.message); process.exit(1); });
