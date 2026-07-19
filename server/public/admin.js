let TOKEN = '';
let refreshTimer = null;
let fenceMap = null, fenceMarkers = [], fenceCircle = null, fencePolyline = null, fencePolygon = null;
let fenceMode = 'circle', polygonPoints = [];

async function api(method, path, data) {
  const opts = { method, headers: { 'Authorization': `Bearer ${TOKEN}`, 'Content-Type': 'application/json' } };
  if (data) opts.body = JSON.stringify(data);
  const r = await fetch(path, opts);
  if (!r.ok) { let msg; try { const e = await r.json(); msg = e.message || e.code; } catch (_) { msg = await r.text(); } throw new Error(`${r.status}: ${msg}`); }
  return r.json();
}

document.getElementById('loginBtn').onclick = login;
document.getElementById('loginPwd').onkeydown = e => { if (e.key === 'Enter') login(); };

async function login() {
  const phone = document.getElementById('loginPhone').value;
  const pwd = document.getElementById('loginPwd').value;
  try {
    const data = await api('POST', '/api/v1/auth/login', { phone, password: pwd });
    TOKEN = data.token;
    document.getElementById('loginView').style.display = 'none';
    document.getElementById('mainView').style.display = 'block';
    showTab('dashboard');
  } catch (e) { alert('登录失败: ' + e.message); }
}

function showTab(tab) {
  document.querySelectorAll('.tab-content').forEach(el => el.style.display = 'none');
  const el = document.getElementById(tab);
  if (el) el.style.display = 'block';
  document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
  const btn = document.querySelector(`[data-tab="${tab}"]`);
  if (btn) btn.classList.add('active');
  if (refreshTimer) { clearInterval(refreshTimer); refreshTimer = null; }
  if (tab === 'dashboard') { loadDashboard(); refreshTimer = setInterval(loadDashboard, 15000); }
  if (tab === 'monitor') { loadMonitor(); refreshTimer = setInterval(loadMonitor, 10000); }
  if (tab === 'tracks') loadTracks();
  if (tab === 'rules') loadRules();
  if (tab === 'reports') loadReports();
  if (tab === 'org') loadOrg();
  if (tab === 'fences') { loadFences(); setTimeout(initFenceMap, 300); }
  if (tab === 'customers') loadCustomers();
  if (tab === 'photos') loadPhotos();
  if (tab === 'users') loadUsers();
}

// ====================================================================
//  🚧 围栏管理
// ====================================================================
async function loadFences() {
  const el = document.getElementById('fencesContent');
  el.innerHTML = '<p>加载中...</p>';
  try {
    const [fences, events] = await Promise.all([
      api('GET', '/api/v1/fences'),
      api('GET', '/api/v1/fences/events'),
    ]);
    const fenceList = Array.isArray(fences) ? fences : [];
    const eventList = events.events || [];

    el.innerHTML = `
      <h2>🚧 围栏管理</h2>
      <div style="display:flex;gap:20px">
        <div style="flex:3">
          <div class="card" style="padding:16px">
            <div style="display:flex;gap:8px;margin-bottom:12px">
              <button class="${fenceMode==='circle'?'':'success'}" onclick="setFenceMode('circle')">⭕ 圆形</button>
              <button class="${fenceMode==='polygon'?'':'success'}" onclick="setFenceMode('polygon')">🔷 多边形</button>
              <span id="fenceHelp" style="margin-left:12px;color:#666;font-size:13px;line-height:32px">点击地图选择围栏位置</span>
            </div>
            <div id="fenceMapContainer" class="fence-map"></div>
            <div style="display:flex;gap:16px;margin-top:12px">
              <input type="text" id="fenceNameCreate" placeholder="围栏名称" style="flex:1;padding:8px;border:1px solid #d9d9d9;border-radius:6px" />
              <div id="fenceRadiusDiv" style="flex:2;display:flex;align-items:center;gap:8px">
                <span style="font-size:13px;white-space:nowrap">半径: <span id="radiusVal">300</span>m</span>
                <input type="range" id="radiusSlider" min="50" max="5000" value="300" oninput="updateRadius(this.value)" style="flex:1" />
              </div>
              <div id="polygonControls" style="flex:2;display:none;gap:8px;align-items:center">
                <span id="pointCount" style="font-size:13px">已选 0 个点</span>
                <button class="danger" onclick="undoPoint()" style="padding:4px 10px;font-size:12px">撤销</button>
                <button class="success" onclick="finishPolygon()" id="finishPolyBtn" disabled style="padding:4px 10px;font-size:12px">完成</button>
                <button onclick="clearPolygon()" style="background:#666;padding:4px 10px;font-size:12px">清空</button>
              </div>
              <button onclick="saveFence()" style="white-space:nowrap">💾 保存</button>
            </div>
            <span id="fenceResult" style="margin-left:12px;font-size:13px"></span>
          </div>
          <div class="card" style="padding:16px;margin-top:12px">
            <h4 style="margin-bottom:8px">围栏列表 (${fenceList.length})</h4>
            ${fenceList.length === 0 ? '<p style="color:#999;text-align:center">暂无围栏</p>' :
              fenceList.map(f => `<div style="border:1px solid #f0f0f0;border-radius:8px;padding:12px;margin-bottom:8px;display:flex;align-items:center;justify-content:space-between">
                <div style="flex:1"><strong>${f.name}</strong>
                  <span class="tag ${f.shapeType==='polygon'?'tag-green':'tag-blue'}" style="margin-left:8px">${f.shapeType==='polygon'?'多边形':'圆形'}</span>
                  <div style="font-size:12px;color:#666;margin-top:4px">${f.shapeType==='circle'?`⚪ (${f.centerLat?.toFixed(4)},${f.centerLng?.toFixed(4)}) ${f.radiusMeters}m`:`🔷 ${(f.coordinates||[]).length}个折点`}</div>
                </div>
                <button class="danger" onclick="viewFence(${f.id})" style="padding:4px 10px;font-size:12px;margin-right:4px;background:#666">📍</button>
                <button onclick="editFence(${f.id})" style="padding:4px 10px;font-size:12px;margin-right:4px">✏️</button>
                <button class="danger" onclick="deleteFence(${f.id})" style="padding:4px 10px;font-size:12px">删除</button>
              </div>`).join('')}
          </div>
        </div>
        <div style="flex:2">
          <div class="card" style="padding:16px">
            <h4 style="margin-bottom:8px">进出事件 (${Math.min(eventList.length,100)})</h4>
            <table class="data-table" style="font-size:12px">
              <tr><th>用户</th><th>围栏</th><th>事件</th><th>时间</th></tr>
              ${eventList.length === 0 ? '<tr><td colspan="4" style="text-align:center;color:#999">暂无</td></tr>' :
                eventList.slice(0,100).map(e => `<tr>
                  <td>${e.userId?.slice(0,8)}</td><td>${e.fenceName}</td>
                  <td><span class="tag ${e.eventType==='enter'?'tag-green':'tag-red'}">${e.eventType==='enter'?'⏺进入':'⏹离开'}</span></td>
                  <td>${new Date(e.createdAt).toLocaleString()}</td>
                </tr>`).join('')}
            </table>
          </div>
        </div>
      </div>`;
  } catch(e) { el.innerHTML = `<p style="color:red">加载失败: ${e.message}</p>`; }
}

function initFenceMap() {
  if (!document.getElementById('fenceMapContainer')) return;
  if (fenceMap) fenceMap.remove();
  fenceMap = L.map('fenceMapContainer').setView([22.5431, 114.0579], 13);
  L.tileLayer('https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}', { attribution: '&copy; 高德地图', maxZoom: 18, subdomains: ['webrd01','webrd02','webrd03','webrd04'] }).addTo(fenceMap);
  fenceMap.on('click', e => fenceMode === 'circle' ? placeCircleCenter(e.latlng.lat, e.latlng.lng) : addPolygonPoint(e.latlng.lat, e.latlng.lng));
}

function setFenceMode(mode) {
  fenceMode = mode; clearAllDrawings(); polygonPoints = [];
  document.getElementById('fenceHelp').textContent = mode === 'circle' ? '点击地图选择围栏中心点' : '点击地图依次添加折点';
  document.getElementById('fenceRadiusDiv').style.display = mode === 'circle' ? 'flex' : 'none';
  document.getElementById('polygonControls').style.display = mode === 'polygon' ? 'flex' : 'none';
  loadFences(); setTimeout(initFenceMap, 200);
  document.querySelectorAll('[onclick*="setFenceMode"]').forEach(b => b.className = b.innerText.includes(mode==='circle'?'圆形':'多边形') ? '' : 'success');
}

function placeCircleCenter(lat, lng) {
  clearAllDrawings();
  const marker = L.marker([lat, lng], { draggable: true }).addTo(fenceMap);
  marker.on('dragend', function(e) { updateCirclePreview(e.target.getLatLng()); });
  fenceMarkers.push(marker);
  updateCirclePreview({ lat, lng });
  document.getElementById('fenceHelp').textContent = `📍 (${lat.toFixed(4)}, ${lng.toFixed(4)}) 可拖动调整`;
}

function updateCirclePreview(latlng) {
  if (fenceCircle) fenceMap.removeLayer(fenceCircle);
  const r = parseInt(document.getElementById('radiusSlider').value);
  fenceCircle = L.circle([latlng.lat, latlng.lng], { radius: r, color: '#1677ff', fillColor: '#1677ff', fillOpacity: 0.1 }).addTo(fenceMap);
}
function updateRadius(val) {
  document.getElementById('radiusVal').textContent = val;
  if (fenceMarkers.length > 0) updateCirclePreview(fenceMarkers[0].getLatLng());
}

function addPolygonPoint(lat, lng) {
  polygonPoints.push({ lat, lng });
  const marker = L.marker([lat, lng], { draggable: true }).addTo(fenceMap);
  marker.on('dragend', function(e) {
    const idx = fenceMarkers.indexOf(this);
    if (idx >= 0) polygonPoints[idx] = { lat: e.target.getLatLng().lat, lng: e.target.getLatLng().lng };
    redrawPolygon();
  });
  fenceMarkers.push(marker);
  redrawPolygon();
}
function redrawPolygon() {
  if (fencePolyline) fenceMap.removeLayer(fencePolyline);
  if (fencePolygon) fenceMap.removeLayer(fencePolygon);
  if (polygonPoints.length >= 2) {
    fencePolyline = L.polyline(polygonPoints.map(p => [p.lat, p.lng]), { color: '#1677ff', weight: 2 }).addTo(fenceMap);
  }
  if (polygonPoints.length >= 3) {
    fencePolygon = L.polygon(polygonPoints.map(p => [p.lat, p.lng]), { color: '#1677ff', fillColor: '#1677ff', fillOpacity: 0.1 }).addTo(fenceMap);
    document.getElementById('finishPolyBtn').disabled = false;
  }
  document.getElementById('pointCount').textContent = `已选 ${polygonPoints.length} 个点`;
}
function undoPoint() {
  if (polygonPoints.length === 0) return;
  polygonPoints.pop();
  if (fenceMarkers.length > 0) fenceMap.removeLayer(fenceMarkers.pop());
  redrawPolygon(); document.getElementById('finishPolyBtn').disabled = polygonPoints.length < 3;
}
function finishPolygon() {
  if (polygonPoints.length < 3) return;
  document.getElementById('fenceHelp').textContent = `✅ ${polygonPoints.length}个折点，填写名称保存`;
}
function clearPolygon() { polygonPoints=[]; clearAllDrawings(); document.getElementById('pointCount').textContent='已选 0 个点'; document.getElementById('finishPolyBtn').disabled=true; }
function clearAllDrawings() {
  fenceMarkers.forEach(m => fenceMap?.removeLayer(m)); fenceMarkers=[];
  if (fenceCircle) { fenceMap?.removeLayer(fenceCircle); fenceCircle=null; }
  if (fencePolyline) { fenceMap?.removeLayer(fencePolyline); fencePolyline=null; }
  if (fencePolygon) { fenceMap?.removeLayer(fencePolygon); fencePolygon=null; }
}
async function saveFence() {
  const name = document.getElementById('fenceNameCreate').value;
  if (!name) { document.getElementById('fenceResult').innerHTML = '❌ 输入名称'; return; }
  const data = { name, shapeType: fenceMode };
  if (fenceMode === 'circle') {
    if (fenceMarkers.length === 0) { document.getElementById('fenceResult').innerHTML = '❌ 点击地图选中心'; return; }
    const ll = fenceMarkers[0].getLatLng();
    data.centerLat=ll.lat; data.centerLng=ll.lng; data.radiusMeters=parseInt(document.getElementById('radiusSlider').value);
  } else {
    if (polygonPoints.length < 3) { document.getElementById('fenceResult').innerHTML = '❌ 至少3个折点'; return; }
    data.coordinates = polygonPoints;
  }
  try {
    await api('POST', '/api/v1/fences', data);
    document.getElementById('fenceResult').innerHTML = '✅ 创建成功';
    clearAllDrawings(); polygonPoints=[];
    setTimeout(() => { loadFences(); setTimeout(initFenceMap, 300); }, 500);
  } catch(e) { document.getElementById('fenceResult').innerHTML = `❌ ${e.message}`; }
}
async function viewFence(id) {
  try { const f = await api('GET', `/api/v1/fences/${id}`); setFenceMode(f.shapeType || 'circle'); setTimeout(() => {
    if (f.shapeType === 'circle' && f.centerLat) {
      placeCircleCenter(f.centerLat, f.centerLng);
      document.getElementById('radiusSlider').value = f.radiusMeters||300;
      document.getElementById('radiusVal').textContent = f.radiusMeters||300;
    } else if (f.coordinates) f.coordinates.forEach(p => addPolygonPoint(p.lat, p.lng));
  }, 500); } catch(e) { alert('失败: '+e.message); }
}
async function deleteFence(id) { if (!confirm('确定删除？')) return; try { await api('DELETE', `/api/v1/fences/${id}`); loadFences(); setTimeout(initFenceMap, 300); } catch(e) { alert('失败: '+e.message); } }

// ==================== 实时监控 - 地图版 ====================
let monitorMap = null, monitorMarkers = [], monitorTimer = null;
async function loadMonitor() {
  const el = document.getElementById('monitorContent');
  el.innerHTML = `<h2>🖥️ 实时监控</h2>
    <div style="display:flex;gap:12px;margin:12px 0">
      <div class="stat-card blue" style="flex:1;padding:12px;text-align:center"><div class="stat-num" id="mcOnline">0</div><div>在线</div></div>
      <div class="stat-card green" style="flex:1;padding:12px;text-align:center"><div class="stat-num" id="mcMoving">0</div><div>运动中</div></div>
      <div class="stat-card orange" style="flex:1;padding:12px;text-align:center"><div class="stat-num" id="mcStill">0</div><div>静止</div></div>
    </div>
    <div id="monitorMap" style="height:350px;border-radius:8px;margin-bottom:12px;border:1px solid #ddd"></div>
    <div id="monitorTable"></div>`;
  
  try {
    // 初始化地图
    if (typeof L !== 'undefined') {
      setTimeout(() => {
        const mapEl = document.getElementById('monitorMap');
        if (!mapEl) return;
        const m = L.map(mapEl, { zoomControl: true }).setView([22.5431, 114.0579], 12);
        L.tileLayer('https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}', 
          { attribution: '&copy; 高德', maxZoom: 18, subdomains: ['webrd01','webrd02','webrd03','webrd04'] }).addTo(m);
        window._monitorMap = m;
        
        // 加载数据后加标记
        refreshMonitor(m);
        setInterval(() => refreshMonitor(m), 10000);
      }, 200);
    }
  } catch(e) { console.error('Map init error:', e); }
}

async function refreshMonitor(map) {
  try {
    const data = await api('GET', '/api/v1/org/locations/online');
    const users = data.locations || [];
    const moving = users.filter(u => u.speed > 0).length;
    const el = document.getElementById('mcOnline'); if(el) el.textContent = users.length;
    const el2 = document.getElementById('mcMoving'); if(el2) el2.textContent = moving;
    const el3 = document.getElementById('mcStill'); if(el3) el3.textContent = users.length - moving;
    
    // 表格
    let html = '<table class="data-table"><tr><th>用户</th><th>部门</th><th>位置</th><th>速度</th><th>时间</th></tr>';
    users.forEach(u => html += `<tr><td>${u.name||u.userId}</td><td>${u.department||'--'}</td><td>${(u.lat||0).toFixed(4)},${(u.lng||0).toFixed(4)}</td><td>${(u.speed||0).toFixed(1)}km/h</td><td>${new Date(u.timestamp).toLocaleString()}</td></tr>`);
    html += users.length===0?'<tr><td colspan="5" style="text-align:center;color:#999">暂无在线人员</td></tr>':'</table>';
    document.getElementById('monitorTable').innerHTML = html;
    
    // 地图标记
    if (map) {
      map.eachLayer(l => { if (l instanceof L.Marker) map.removeLayer(l); });
      users.forEach(u => {
        if (!u.lat || !u.lng) return;
        const color = u.speed > 0 ? '#52c41a' : '#1677ff';
        const icon = L.divIcon({ 
          html: `<div style="background:${color};color:white;width:30px;height:30px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:bold;border:2px solid white;box-shadow:0 2px 6px rgba(0,0,0,0.3)">${(u.name||u.userId||'?')[0]}</div>`, 
          className: '', iconSize: [30, 30] 
        });
        L.marker([u.lat, u.lng], { icon }).addTo(map).bindPopup(`<b>${u.name||u.userId}</b><br>部门: ${u.department||'--'}<br>速度: ${(u.speed||0).toFixed(1)} km/h`);
      });
    }
  } catch(e) { console.error('Monitor refresh error:', e); }
}

// ==================== 客户管理 ====================
async function loadCustomers() {
  const el = document.getElementById('customersContent');
  try {
    const data = await api('GET', '/api/v1/customers');
    const list = data.customers || [];
    el.innerHTML = `<h2>👥 客户管理</h2>
      <div class="card" style="padding:20px;margin:12px 0">
        <h4>添加客户</h4>
        <div class="form-row"><label>名称</label><input type="text" id="custName" placeholder="必填" /></div>
        <div class="form-row"><label>电话</label><input type="text" id="custPhone" /></div>
        <div class="form-row"><label>地址</label><input type="text" id="custAddr" /></div>
        <div class="form-row"><label>坐标</label><input type="text" id="custLat" placeholder="纬度" style="width:120px" value="22.55" />
          <input type="text" id="custLng" placeholder="经度" style="width:120px" value="114.08" /></div>
        <div class="form-row"><label>标签</label><input type="text" id="custTags" placeholder="逗号分隔" /></div>
        <div class="form-row"><label>备注</label><input type="text" id="custRemark" /></div>
        <button onclick="addCustomer()">➕ 添加</button><span id="custResult" style="margin-left:12px"></span>
      </div>
      <table class="data-table"><tr><th>ID</th><th>名称</th><th>电话</th><th>地址</th><th>标签</th><th>操作</th></tr>
      ${list.length===0?'<tr><td colspan="6" style="text-align:center;color:#999">暂无</td></tr>':
        list.map(c => `<tr>
          <td>${c.id}</td><td>${c.name}</td><td>${c.phone||'--'}</td><td>${c.address||'--'}</td>
          <td>${(c.tags||[]).join(', ')}</td>
          <td><button onclick="deleteCustomer(${c.id})" class="danger" style="padding:4px 10px;font-size:12px">删除</button></td>
        </tr>`).join('')}
      </table>`;
  } catch(e) { el.innerHTML = `<p style="color:red">加载失败: ${e.message}</p>`; }
}
window.addCustomer = async function() {
  const name = document.getElementById('custName').value.trim();
  if (!name) { document.getElementById('custResult').innerHTML = '❌ 名称必填'; return; }
  try {
    await api('POST', '/api/v1/customers', {
      name, phone: document.getElementById('custPhone').value,
      address: document.getElementById('custAddr').value,
      lat: parseFloat(document.getElementById('custLat').value)||22.55,
      lng: parseFloat(document.getElementById('custLng').value)||114.08,
      tags: document.getElementById('custTags').value.split(',').map(s=>s.trim()).filter(Boolean),
      remark: document.getElementById('custRemark').value,
    });
    document.getElementById('custResult').innerHTML = '✅ 添加成功';
    loadCustomers();
  } catch(e) { document.getElementById('custResult').innerHTML = `❌ ${e.message}`; }
};
window.deleteCustomer = async function(id) {
  if (!confirm('确定删除？')) return;
  try { await api('DELETE', `/api/v1/customers/${id}`); loadCustomers(); }
  catch(e) { alert('失败: '+e.message); }
};

// ==================== 水印照片 ====================
async function loadPhotos() {
  const el = document.getElementById('photosContent');
  try {
    const data = await api('GET', '/api/v1/upload/photos');
    const photos = data.photos || [];
    el.innerHTML = `<h2>📸 水印照片</h2>
      <p style="margin:8px 0;color:#666">共 ${photos.length} 张照片</p>
      <div class="photo-grid">
        ${photos.length===0?'<p style="color:#999;grid-column:1/-1;text-align:center">暂无照片</p>':
          photos.map(p => {
            const url = p.url || p.path || '';
            const time = p.createdAt || '';
            return `<div style="position:relative">
              <img src="${url}" onerror="this.style.display='none'" />
              <div style="position:absolute;bottom:0;left:0;right:0;background:rgba(0,0,0,0.5);color:white;padding:6px;font-size:11px">${time}</div>
            </div>`;
          }).join('')}
      </div>`;
  } catch(e) { el.innerHTML = `<p style="color:red">加载失败: ${e.message}</p>`; }
}

// ==================== 人员管理 ====================
async function loadUsers() {
  const el = document.getElementById('usersContent');
  el.innerHTML = `<h2>👤 人员管理</h2>
    <div class="card" style="padding:20px;margin:12px 0">
      <h4>添加人员</h4>
      <div class="form-row"><label>姓名</label><input type="text" id="userName" /></div>
      <div class="form-row"><label>手机</label><input type="text" id="userPhone" placeholder="必填" /></div>
      <div class="form-row"><label>密码</label><input type="text" id="userPwd" value="test123456" /></div>
      <div class="form-row"><label>角色</label>
        <select id="userRole"><option value="employee">员工</option><option value="manager">经理</option><option value="admin">管理员</option></select></div>
      <button onclick="addUser()">➕ 添加</button><span id="userResult" style="margin-left:12px"></span>
    </div>
    <table class="data-table"><tr><th>手机</th><th>姓名</th><th>角色</th><th>操作</th></tr>
    <tr><td colspan="4" style="text-align:center;color:#999">加载中...</td></tr></table>`;
  try {
    const users = await api('GET', '/api/v1/org/users');
    const list = Array.isArray(users) ? users : (users.users || []);
    const html = list.map(u => `<tr>
      <td>${u.phone||u.userId}</td><td>${u.name||'--'}</td>
      <td><span class="tag ${u.role==='admin'?'tag-red':u.role==='manager'?'tag-blue':'tag-green'}">${u.role||'employee'}</span></td>
      <td><button onclick="deleteUser('${u.phone||u.userId}')" class="danger" style="padding:4px 10px;font-size:12px">删除</button></td>
    </tr>`).join('');
    el.innerHTML = el.innerHTML.replace('加载中...</td></tr>', html || '<tr><td colspan="4" style="text-align:center;color:#999">暂无</td></tr>');
  } catch(e) { /* uses memory users only */ }
}
window.addUser = async function() {
  const phone = document.getElementById('userPhone').value.trim();
  const resultEl = document.getElementById('userResult');
  
  // 手机号完整验证
  if (!phone) { resultEl.innerHTML = '❌ 手机号不能为空'; return; }
  if (!/^\d{11}$/.test(phone)) { resultEl.innerHTML = '❌ 手机号必须是11位数字'; return; }
  if (!/^1\d{10}$/.test(phone)) { resultEl.innerHTML = '❌ 手机号必须以1开头'; return; }
  // 号段验证（中国大陆手机号段）
  const validPrefixes = /^1(3\d|4[5-9]|5[0-35-9]|6[2567]|7[0-8]|8\d|9[0-35-9])\d{8}$/;
  if (!validPrefixes.test(phone)) { resultEl.innerHTML = '❌ 手机号号段无效（如13x/15x/18x等）'; return; }
  
  try {
    await api('POST', '/api/v1/auth/register', {
      phone, password: document.getElementById('userPwd').value || 'test123456',
      name: document.getElementById('userName').value,
      role: document.getElementById('userRole').value,
    });
    document.getElementById('userResult').innerHTML = '✅ 添加成功';
  } catch(e) { document.getElementById('userResult').innerHTML = `❌ ${e.message}`; }
};
window.deleteUser = async function(phone) {
  if (!confirm('确定删除？')) return;
  try { await api('DELETE', `/api/v1/org/users/${phone}`); loadUsers(); }
  catch(e) { alert('失败: '+e.message); }
};

// ==================== 打卡规则编辑/删除 ====================
window.editRule = async function(id) {
  const rules = (await api('GET', '/api/v1/attendance/rules')).rules || [];
  const r = rules.find(x => x.id === id);
  if (!r) return;
  const name = prompt('规则名称:', r.name);
  if (!name) return;
  const start = prompt('上班时间:', r.startTime);
  const end = prompt('下班时间:', r.endTime);
  try {
    await api('PUT', `/api/v1/attendance/rules/${id}`, { name, startTime: start, endTime: end, radius: r.radius, wifiName: r.wifiName });
    loadRules();
  } catch(e) { alert('编辑失败: '+e.message); }
};
window.deleteRule = async function(id) {
  if (!confirm('确定删除此打卡规则？')) return;
  try { await api('DELETE', `/api/v1/attendance/rules/${id}`); loadRules(); }
  catch(e) { alert('删除失败: '+e.message); }
};

// ==================== 围栏编辑 ====================
window.editFence = async function(id) {
  try {
    const f = await api('GET', `/api/v1/fences/${id}`);
    // 先切换到围栏页，等页面渲染后再操作DOM
    showTab('fences');
    setTimeout(() => {
      const nameEl = document.getElementById('fenceNameCreate');
      if (!nameEl) { alert('围栏页面未加载完成'); return; }
      nameEl.value = f.name || '';
      setFenceMode(f.shapeType || 'circle');
      setTimeout(() => {
        if (f.shapeType === 'circle' && f.centerLat) {
          placeCircleCenter(f.centerLat, f.centerLng);
          const rs = document.getElementById('radiusSlider');
          const rv = document.getElementById('radiusVal');
          if (rs) rs.value = f.radiusMeters||300;
          if (rv) rv.textContent = f.radiusMeters||300;
        } else if (f.coordinates) {
          f.coordinates.forEach(p => addPolygonPoint(p.lat, p.lng));
        }
        // 修改保存按钮行为暂存编辑
        const saveBtn = document.querySelector('#fenceResult');
        if (saveBtn) {
          const oldHtml = saveBtn.innerHTML;
          saveBtn.innerHTML = '<button onclick="saveFenceEdit('+id+')">💾 更新围栏</button>';
        }
      }, 500);
    }, 500);
  } catch(e) { alert('加载失败: '+e.message); }
};

async function saveFenceEdit(id) {
  const name = document.getElementById('fenceNameCreate').value;
  if (!name) { document.getElementById('fenceResult').innerHTML = '❌ 输入名称'; return; }
  const data = { name, shapeType: fenceMode, isActive: true };
  if (fenceMode === 'circle') {
    if (fenceMarkers.length === 0) { document.getElementById('fenceResult').innerHTML = '❌ 点击地图选中心'; return; }
    const ll = fenceMarkers[0].getLatLng();
    data.centerLat=ll.lat; data.centerLng=ll.lng; data.radiusMeters=parseInt(document.getElementById('radiusSlider').value);
  } else {
    if (polygonPoints.length < 3) { document.getElementById('fenceResult').innerHTML = '❌ 至少3个折点'; return; }
    data.coordinates = polygonPoints;
  }
  try { await api('PUT', `/api/v1/fences/${id}`, data); document.getElementById('fenceResult').innerHTML = '✅ 更新成功'; setTimeout(() => { loadFences(); setTimeout(initFenceMap, 300); }, 500); }
  catch(e) { document.getElementById('fenceResult').innerHTML = `❌ ${e.message}`; }
}

// ====================================================================
//  📊 数据看板
// ====================================================================
async function loadDashboard() {
  const el = document.getElementById('dashContent');
  try {
    const [loc, att, appr, rules] = await Promise.all([
      api('GET', '/api/v1/org/locations/online').catch(() => ({ locations: [], total: 0 })),
      api('GET', '/api/v1/attendance/records?pageSize=10').catch(() => ({ records: [], pagination: { total: 0 } })),
      api('GET', '/api/v1/approvals').catch(() => ({ approvals: [], pagination: { total: 0 } })),
      api('GET', '/api/v1/attendance/rules').catch(() => ({ rules: [] })),
    ]);
    el.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px">
        <h2 style="margin:0">数据看板</h2><span style="color:#999;font-size:13px">${new Date().toLocaleTimeString()}</span>
      </div>
      <div class="stats-grid">
        <div class="stat-card blue"><div class="stat-num">${loc.total || 0}</div><div>在线人员</div></div>
        <div class="stat-card green"><div class="stat-num">${att.pagination?.total || 0}</div><div>今日打卡</div></div>
        <div class="stat-card orange"><div class="stat-num">${appr.pagination?.total || 0}</div><div>待审批</div></div>
        <div class="stat-card purple"><div class="stat-num">${rules.rules?.length || 0}</div><div>打卡规则</div></div>
      </div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px">
        <div class="card" style="padding:16px"><h4>最近打卡</h4><table class="data-table"><tr><th>用户</th><th>时间</th></tr>${(att.records||[]).slice(0,5).map(r=>`<tr><td>${r.userName||'?'}</td><td>${new Date(r.createdAt).toLocaleString()}</td></tr>`).join('')}</table></div>
        <div class="card" style="padding:16px"><h4>在线人员</h4><table class="data-table"><tr><th>用户</th><th>部门</th></tr>${(loc.locations||[]).slice(0,5).map(l=>`<tr><td>${l.name||l.userId}</td><td>${l.department||'--'}</td></tr>`).join('')}</table></div>
      </div>`;
  } catch(e) { el.innerHTML = `<p style="color:red">加载失败: ${e.message}</p>`; }
}

// ====================================================================
//  📊 数据看板
// ====================================================================

// ====================================================================
//  👣 轨迹查询
// ====================================================================
function loadTracks() {
  const today = new Date().toISOString().split('T')[0];
  document.getElementById('trackContent').innerHTML = `<h2>轨迹查询</h2><div class="card" style="padding:20px;margin:12px 0"><div class="form-row"><label>用户ID</label><input type="text" id="trackUserId" placeholder="留空查自己" /></div><div class="form-row"><label>日期</label><input type="date" id="trackDate" value="${today}" /></div><button onclick="searchTrack()">🔍 查询</button></div><div id="trackResult"></div>`;
}
async function searchTrack() {
  const uid = document.getElementById('trackUserId').value || '-1';
  const date = document.getElementById('trackDate').value;
  const el = document.getElementById('trackResult'); el.innerHTML = '<p>查询中...</p>';
  try {
    const data = await api('GET', `/api/v1/location/track/${uid}?date=${date}`);
    const points = data.points || [];
    if (points.length === 0) { el.innerHTML = '<div class="card" style="padding:20px;text-align:center;color:#999">无数据</div>'; return; }
    const totalKm = points.length > 1 ? points.reduce((sum,p,i)=>i===0?0:sum+haversine(points[i-1].lat,points[i-1].lng,p.lat,p.lng),0) : 0;
    const avgSpeed = points.reduce((s,p)=>s+(p.speed||0),0)/points.length;
    const duration = points.length > 1 ? (new Date(points[points.length-1].timestamp).getTime()-new Date(points[0].timestamp).getTime())/3600000 : 0;
    el.innerHTML = `<div class="stats-grid"><div class="stat-card blue"><div class="stat-num">${points.length}</div><div>点数</div></div><div class="stat-card green"><div class="stat-num">${totalKm.toFixed(2)}</div><div>里程(km)</div></div><div class="stat-card orange"><div class="stat-num">${avgSpeed.toFixed(1)}</div><div>均速(km/h)</div></div><div class="stat-card purple"><div class="stat-num">${duration.toFixed(1)}</div><div>时长(h)</div></div></div>
      <table class="data-table"><tr><th>#</th><th>时间</th><th>经度</th><th>纬度</th><th>速度</th></tr>${points.map((p,i)=>`<tr><td>${i+1}</td><td>${new Date(p.timestamp||p.time).toLocaleString()}</td><td>${(p.lng||0).toFixed(4)}</td><td>${(p.lat||0).toFixed(4)}</td><td>${(p.speed||0).toFixed(1)}</td></tr>`).join('')}</table>`;
  } catch(e) { el.innerHTML = `<p style="color:red">查询失败: ${e.message}</p>`; }
}
function haversine(lat1,lng1,lat2,lng2) { const R=6371; const dLat=(lat2-lat1)*Math.PI/180; const dLng=(lng2-lng1)*Math.PI/180; const a=Math.sin(dLat/2)**2+Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*Math.sin(dLng/2)**2; return R*2*Math.atan2(Math.sqrt(a),Math.sqrt(1-a)); }

// ====================================================================
//  ⚙️ 打卡规则
// ====================================================================
async function loadRules() {
  const el = document.getElementById('rulesContent'); el.innerHTML = '<p>加载中...</p>';
  try {
    const data = await api('GET', '/api/v1/attendance/rules');
    const rules = data.rules || [];
    el.innerHTML = `<h2>打卡规则</h2><div class="card" style="padding:20px;margin:12px 0"><h4>新增</h4><div class="form-row"><label>名称</label><input type="text" id="ruleName" value="默认" /></div><div class="form-row"><label>上班</label><input type="time" id="ruleStart" value="09:00" /></div><div class="form-row"><label>下班</label><input type="time" id="ruleEnd" value="18:00" /></div><div class="form-row"><label>范围(m)</label><input type="number" id="ruleRadius" value="300" /></div><div class="form-row"><label>WiFi</label><input type="text" id="ruleWifi" placeholder="可选" /></div><button onclick="saveRule()">💾 保存</button><span id="ruleResult" style="margin-left:12px"></span></div>
      <table class="data-table"><tr><th>ID</th><th>名称</th><th>上班</th><th>下班</th><th>范围</th><th>操作</th></tr>${
        rules.length===0?'<tr><td colspan="6" style="text-align:center;color:#999">暂无</td></tr>':
        rules.map(r=>`<tr><td>${r.id}</td><td>${r.name}</td><td>${r.startTime}</td><td>${r.endTime}</td><td>${r.radius}m</td>
          <td><button onclick="editRule(${r.id})" style="padding:4px 8px;font-size:12px;margin-right:4px">✏️</button>
          <button onclick="deleteRule(${r.id})" class="danger" style="padding:4px 8px;font-size:12px">🗑️</button></td></tr>`).join('')}</table>`;
  } catch(e) { el.innerHTML = `<p style="color:red">加载失败: ${e.message}</p>`; }
}
async function saveRule() {
  try { await api('POST','/api/v1/attendance/rules',{name:document.getElementById('ruleName').value,startTime:document.getElementById('ruleStart').value,endTime:document.getElementById('ruleEnd').value,radius:parseInt(document.getElementById('ruleRadius').value),wifiName:document.getElementById('ruleWifi').value});
  document.getElementById('ruleResult').innerHTML='✅ 成功'; loadRules(); } catch(e) { document.getElementById('ruleResult').innerHTML=`❌ ${e.message}`; }
}

// ====================================================================
//  📈 统计报表
// ====================================================================
async function loadReports() {
  const el = document.getElementById('reportsContent'); el.innerHTML = '<p>加载中...</p>';
  try {
    const att = await api('GET', '/api/v1/attendance/records?pageSize=100');
    const records = att.records || []; const total = records.length; const ci = records.filter(r => r.type === 'checkin').length; const co = records.filter(r => r.type === 'checkout').length;
    el.innerHTML = `<h2>统计报表</h2><div class="stats-grid"><div class="stat-card green"><div class="stat-num">${total}</div><div>总打卡</div></div><div class="stat-card blue"><div class="stat-num">${ci}</div><div>签到</div></div><div class="stat-card orange"><div class="stat-num">${co}</div><div>签退</div></div><div class="stat-card purple"><div class="stat-num">${total>0?(ci/total*100).toFixed(0):0}%</div><div>签到率</div></div></div>
      <div style="margin:12px 0"><button onclick="exportExcel()">📥 导出CSV</button><span style="margin-left:12px;color:#999">${total}条</span></div>
      <table class="data-table"><tr><th>用户</th><th>类型</th><th>时间</th><th>地址</th></tr>${records.slice(0,100).map(r=>`<tr><td>${r.userName||r.userId}</td><td>${r.type==='checkin'?'签到':'签退'}</td><td>${new Date(r.createdAt).toLocaleString()}</td><td>${r.address||'--'}</td></tr>`).join('')}</table>`;
    window._attRecords = records;
  } catch(e) { el.innerHTML = `<p style="color:red">加载失败: ${e.message}</p>`; }
}
function exportExcel() {
  const records = window._attRecords || [];
  let csv = '\ufeff用户,类型,时间,地址\n';
  records.forEach(r => csv+=`"${r.userName||''}","${r.type==='checkin'?'签到':'签退'}","${r.createdAt}","${r.address||''}"\n`);
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `考勤_${new Date().toISOString().split('T')[0]}.csv`; a.click();
  URL.revokeObjectURL(a.href);
}

// ====================================================================
//  🏢 组织架构
// ====================================================================
async function loadOrg() {
  const el = document.getElementById('orgContent'); el.innerHTML = '<p>加载中...</p>';
  try {
    const data = await api('GET', '/api/v1/org/departments');
    const depts = data || [];
    el.innerHTML = `<h2>组织架构</h2><div class="card" style="padding:20px;margin:12px 0"><h4>新增部门</h4><div class="form-row"><label>名称</label><input type="text" id="deptName" placeholder="如：销售部" /></div><div class="form-row"><label>负责人</label><input type="text" id="deptManager" placeholder="姓名" /></div><button onclick="addDept()">➕ 添加</button><span id="deptResult" style="margin-left:12px"></span></div>
      <table class="data-table"><tr><th>ID</th><th>名称</th><th>负责人</th><th>创建时间</th><th>操作</th></tr>${depts.length===0?'<tr><td colspan="5" style="text-align:center;color:#999">暂无</td></tr>':depts.map(d=>`<tr><td>${d.id}</td><td>${'  '.repeat(d.parentId?1:0)}${d.name}</td><td>${d.manager||'--'}</td><td>${new Date(d.createdAt).toLocaleDateString()}</td><td><button onclick="deleteDept(${d.id})" style="background:#ff4d4f;padding:4px 8px;font-size:12px">删除</button></td></tr>`).join('')}</table>`;
  } catch(e) { el.innerHTML = `<p style="color:red">加载失败: ${e.message}</p>`; }
}
async function addDept() {
  const name = document.getElementById('deptName').value;
  if (!name) { document.getElementById('deptResult').innerHTML = '❌ 名称不能为空'; return; }
  try { await api('POST','/api/v1/org/departments',{name,manager:document.getElementById('deptManager').value}); document.getElementById('deptResult').innerHTML='✅ 添加成功'; document.getElementById('deptName').value=''; loadOrg(); } catch(e) { document.getElementById('deptResult').innerHTML=`❌ ${e.message}`; }
}
async function deleteDept(id) { if (!confirm('确定删除？')) return; try { await api('DELETE',`/api/v1/org/departments/${id}`); loadOrg(); } catch(e) { alert('删除失败: '+e.message); } }
