let TOKEN = '';
let refreshTimer = null;
let fenceMap = null, fenceMarkers = [], fenceCircle = null, fencePolyline = null, fencePolygon = null;
let fenceMode = 'circle', polygonPoints = [];
let monitorMap = null, monitorTimer = null, monitorWS = null, monitorMks = [];
let trackMap = null, trackPolyline = null, trackMarker = null;
let trackAnim = null, trackPlaying = false, trackIdx = 0, trackSpeed = 1;
let trackPoints = [];
const TRACK_SPEEDS = [1, 2, 5, 10];

// 从localStorage恢复登录
const savedToken = localStorage.getItem('admin_token');
if (savedToken) {
  TOKEN = savedToken;
  window._userId = localStorage.getItem('admin_userId') || '';
  window._userPhone = localStorage.getItem('admin_userPhone') || '';
  document.getElementById('loginView').style.display = 'none';
  document.getElementById('mainView').style.display = 'block';
  showTab('dashboard');
}

async function api(method, path, data) {
  const opts = { method, headers: { 'Authorization': `Bearer ${TOKEN}`, 'Content-Type': 'application/json' } };
  if (data) opts.body = JSON.stringify(data);
  const r = await fetch(path, opts);
  if (r.status === 401) {
    localStorage.removeItem('admin_token');
    localStorage.removeItem('admin_userId');
    localStorage.removeItem('admin_userPhone');
    TOKEN = '';
    document.getElementById('loginView').style.display = 'block';
    document.getElementById('mainView').style.display = 'none';
    throw new Error('登录已过期，请重新登录');
  }
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
    window._userId = data.userId;
    window._userPhone = data.phone;
    localStorage.setItem('admin_token', data.token);
    localStorage.setItem('admin_userId', data.userId);
    localStorage.setItem('admin_userPhone', data.phone);
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
  if (tab === 'monitor') { loadMonitor(); refreshTimer = setInterval(() => { if (window._monitorMap) refreshMonitor(); else loadMonitor(); }, 10000); }
  if (tab === 'tracks') loadTracks();
  if (tab === 'rules') loadRules();
  if (tab === 'reports') loadReports();
  if (tab === 'org') loadOrg();
  if (tab === 'fences') { 
    loadFences().then(() => {
      initFenceMap();
      // 添加搜索框
      addFenceSearch();
    });
  }
  if (tab === 'customers') loadCustomers();
  if (tab === 'photos') loadPhotos();
  if (tab === 'users') loadUsers();
}

// ========== 高德地图工具 ==========
function makeMap(containerId, center=[113.90, 34.61], zoom=13) {
  const m = new AMap.Map(containerId, { zoom, center, resizeEnable: true, scrollWheel: true });
  AMap.plugin(['AMap.ToolBar', 'AMap.Scale', 'AMap.PlaceSearch', 'AMap.AutoComplete'], function() {
    m.addControl(new AMap.ToolBar());
    m.addControl(new AMap.Scale());
  });
  return m;
}

// 围栏地图搜索框
let fencePlaceSearch = null;
function addFenceSearch() {
  const container = document.getElementById('fenceMapContainer');
  if (!container || container.dataset.searchAdded) return;
  container.dataset.searchAdded = '1';
  // 在容器上方添加搜索行
  const parent = container.parentElement;
  const searchRow = document.createElement('div');
  searchRow.style.cssText = 'display:flex;gap:8px;margin-bottom:8px';
  searchRow.innerHTML = `
    <input type="text" id="fenceSearchInput" placeholder="搜索地点/地址" style="flex:1;padding:8px;border:1px solid #d9d9d9;border-radius:6px;font-size:14px" />
    <button id="fenceSearchBtn" style="padding:8px 16px">🔍 搜索</button>
  `;
  parent.insertBefore(searchRow, container);
  // 地点搜索
  AMap.plugin(['AMap.PlaceSearch'], function() {
    fencePlaceSearch = new AMap.PlaceSearch({ type: 'poi', pageSize: 10, pageIndex: 1 });
  });
  document.getElementById('fenceSearchBtn').onclick = function() {
    const kw = document.getElementById('fenceSearchInput').value.trim();
    if (!kw) return;
    fencePlaceSearch.search(kw, function(status, result) {
      if (status === 'complete' && result.poiList && result.poiList.pois.length > 0) {
        const poi = result.poiList.pois[0];
        fenceMap.setCenter([poi.location.lng, poi.location.lat]);
        fenceMap.setZoom(16);
        new AMap.Marker({ position: [poi.location.lng, poi.location.lat], map: fenceMap, title: poi.name });
      }
    });
  };
  document.getElementById('fenceSearchInput').onkeydown = function(e) {
    if (e.key === 'Enter') document.getElementById('fenceSearchBtn').click();
  };
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
                <button class="danger" onclick="viewFence('${f.id}')" style="padding:4px 10px;font-size:12px;margin-right:4px;background:#666">📍</button>
                <button onclick="editFence('${f.id}')" style="padding:4px 10px;font-size:12px;margin-right:4px">✏️</button>
                <button class="danger" onclick="deleteFence('${f.id}')" style="padding:4px 10px;font-size:12px">删除</button>
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
                  <td>${e.userName || e.userId?.slice(0,8)}</td><td>${e.fenceName}</td>
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
  if (fenceMap) fenceMap.destroy();
  fenceMap = makeMap('fenceMapContainer', [113.90, 34.61], 14);
  fenceMap.on('click', function(e) {
    const ll = e.lnglat;
    fenceMode === 'circle' ? placeCircleCenter(ll.lat, ll.lng) : addPolygonPoint(ll.lat, ll.lng);
  });
}

function setFenceMode(mode) {
  fenceMode = mode; clearAllDrawings(); polygonPoints = [];
  document.getElementById('fenceHelp').textContent = mode === 'circle' ? '点击地图选择围栏中心点' : '点击地图依次添加折点';
  document.getElementById('fenceRadiusDiv').style.display = mode === 'circle' ? 'flex' : 'none';
  document.getElementById('polygonControls').style.display = mode === 'polygon' ? 'flex' : 'none';
  loadFences(); setTimeout(initFenceMap, 200);
}

function placeCircleCenter(lat, lng) {
  clearAllDrawings();
  const marker = new AMap.Marker({ position: [lng, lat], draggable: true, map: fenceMap });
  marker.on('dragend', function(e) { updateCirclePreview(e.target.getPosition()); });
  fenceMarkers.push(marker);
  updateCirclePreview({ lat, lng });
  document.getElementById('fenceHelp').textContent = `📍 (${lat.toFixed(4)}, ${lng.toFixed(4)}) 可拖动调整`;
}

function updateCirclePreview(latlng) {
  if (fenceCircle) fenceMap.remove(fenceCircle);
  const r = parseInt(document.getElementById('radiusSlider').value);
  fenceCircle = new AMap.Circle({ center: [latlng.lng, latlng.lat], radius: r, strokeColor: '#1677ff', fillColor: '#1677ff', fillOpacity: 0.1, map: fenceMap });
}
function updateRadius(val) {
  document.getElementById('radiusVal').textContent = val;
  if (fenceMarkers.length > 0) updateCirclePreview(fenceMarkers[0].getPosition());
}

function addPolygonPoint(lat, lng) {
  polygonPoints.push({ lat, lng });
  const marker = new AMap.Marker({ position: [lng, lat], draggable: true, map: fenceMap });
  marker.on('dragend', function(e) {
    const idx = fenceMarkers.indexOf(this);
    if (idx >= 0) { const pos = e.target.getPosition(); polygonPoints[idx] = { lat: pos.lat, lng: pos.lng }; }
    redrawPolygon();
  });
  fenceMarkers.push(marker);
  redrawPolygon();
}
function redrawPolygon() {
  if (fencePolyline) fenceMap.remove(fencePolyline);
  if (fencePolygon) fenceMap.remove(fencePolygon);
  const pts = polygonPoints.map(p => [p.lng, p.lat]);
  if (polygonPoints.length >= 2) fencePolyline = new AMap.Polyline({ path: pts, strokeColor: '#1677ff', strokeWeight: 2, map: fenceMap });
  if (polygonPoints.length >= 3) {
    fencePolygon = new AMap.Polygon({ path: pts, strokeColor: '#1677ff', fillColor: '#1677ff', fillOpacity: 0.1, map: fenceMap });
    document.getElementById('finishPolyBtn').disabled = false;
  }
  document.getElementById('pointCount').textContent = `已选 ${polygonPoints.length} 个点`;
}
function undoPoint() {
  if (polygonPoints.length === 0) return;
  polygonPoints.pop();
  if (fenceMarkers.length > 0) fenceMap.remove(fenceMarkers.pop());
  redrawPolygon(); document.getElementById('finishPolyBtn').disabled = polygonPoints.length < 3;
}
function finishPolygon() { if (polygonPoints.length < 3) return; document.getElementById('fenceHelp').textContent = `✅ ${polygonPoints.length}个折点，填写名称保存`; }
function clearPolygon() { polygonPoints=[]; clearAllDrawings(); document.getElementById('pointCount').textContent='已选 0 个点'; document.getElementById('finishPolyBtn').disabled=true; }
function clearAllDrawings() {
  fenceMarkers.forEach(m => fenceMap?.remove(m)); fenceMarkers=[];
  if (fenceCircle) { fenceMap?.remove(fenceCircle); fenceCircle=null; }
  if (fencePolyline) { fenceMap?.remove(fencePolyline); fencePolyline=null; }
  if (fencePolygon) { fenceMap?.remove(fencePolygon); fencePolygon=null; }
}
async function saveFence() {
  const name = document.getElementById('fenceNameCreate').value;
  if (!name) { document.getElementById('fenceResult').innerHTML = '❌ 输入名称'; return; }
  const data = { name, shapeType: fenceMode };
  if (fenceMode === 'circle') {
    if (fenceMarkers.length === 0) { document.getElementById('fenceResult').innerHTML = '❌ 点击地图选中心'; return; }
    const pos = fenceMarkers[0].getPosition();
    data.centerLat=pos.lat; data.centerLng=pos.lng; data.radiusMeters=parseInt(document.getElementById('radiusSlider').value);
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

// ==================== 围栏编辑 ====================
window.editFence = async function(id) {
  try {
    const f = await api('GET', `/api/v1/fences/${id}`);
    // 等待围栏页面完全渲染
    await new Promise(resolve => {
      const origShowTab = window._showTabFences || showTab;
      showTab('fences');
      // 等待地图初始化完成
      const check = setInterval(() => {
        const nameEl = document.getElementById('fenceNameCreate');
        if (nameEl && fenceMap) {
          clearInterval(check);
          resolve();
        }
      }, 200);
      setTimeout(() => { clearInterval(check); resolve(); }, 5000);
    });
    // 填充围栏数据
    document.getElementById('fenceNameCreate').value = f.name || '';
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
      const saveEl = document.querySelector('#fenceResult');
      if (saveEl) saveEl.innerHTML = '<button onclick="saveFenceEdit('+id+')">💾 更新围栏</button>';
    }, 500);
  } catch(e) { alert('加载失败: '+e.message); }
};
async function saveFenceEdit(id) {
  const name = document.getElementById('fenceNameCreate').value;
  if (!name) { document.getElementById('fenceResult').innerHTML = '❌ 输入名称'; return; }
  const data = { name, shapeType: fenceMode, isActive: true };
  if (fenceMode === 'circle') {
    if (fenceMarkers.length === 0) { document.getElementById('fenceResult').innerHTML = '❌ 点击地图选中心'; return; }
    const ll = fenceMarkers[0].getPosition();
    data.centerLat=ll.lat; data.centerLng=ll.lng; data.radiusMeters=parseInt(document.getElementById('radiusSlider').value);
  } else {
    if (polygonPoints.length < 3) { document.getElementById('fenceResult').innerHTML = '❌ 至少3个折点'; return; }
    data.coordinates = polygonPoints;
  }
  try { await api('PUT', `/api/v1/fences/${id}`, data); document.getElementById('fenceResult').innerHTML = '✅ 更新成功'; setTimeout(() => { loadFences(); setTimeout(initFenceMap, 300); }, 500); }
  catch(e) { document.getElementById('fenceResult').innerHTML = `❌ ${e.message}`; }
}

// ==================== 实时监控 - 高德版 ====================
function connectMonitorWS() {
  if (monitorWS) { monitorWS.close(); monitorWS = null; }
  if (!TOKEN) return;
  const url = `ws://${location.host}${location.pathname === '/admin.html' || location.pathname === '/admin/' ? '/..' : ''}${location.pathname.replace(/\/admin\.html$|\/admin\/?$/, '')}/ws/location?token=${TOKEN}`;
  const wsUrl = url.replace(/\/+/g, '/').replace(':/', '://');
  try {
    monitorWS = new WebSocket(wsUrl);
    monitorWS.onopen = () => console.log('[WS] 实时连接已建立');
    monitorWS.onmessage = (e) => {
      try {
        const msg = JSON.parse(e.data);
        if (msg.type === 'connected') { console.log('[WS] 已认证为:', msg.userId); return; }
        if (msg.type === 'ack') return;
        if (msg.type === 'location_update') {
          const map = window._monitorMap;
          if (!map) return;
          const uid = msg.userId;
          let found = false;
          monitorMks.forEach(mk => {
            if (mk._uid === uid) {
              mk.setPosition([msg.lng, msg.lat]);
              mk.setLabel({content: `<b>${mk._uname||uid}</b><br>速度: ${(msg.speed||0).toFixed(1)} km/h`, direction: 'right'});
              found = true;
            }
          });
          if (!found) {
            const speed = msg.speed || 0;
            const color = speed > 0 ? '#52c41a' : '#1677ff';
            const mk = new AMap.Marker({
              position: [msg.lng, msg.lat], map,
              content: `<div style="background:${color};color:white;width:30px;height:30px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:bold;border:2px solid white;box-shadow:0 2px 6px rgba(0,0,0,0.3)">${(uid||'?')[0].toUpperCase()}</div>`,
              label: {content: `<b>${uid}</b><br>速度: ${speed.toFixed(1)} km/h`, direction: 'right'}
            });
            mk._uid = uid; mk._uname = uid;
            monitorMks.push(mk);
          }
          window._wsCount = (window._wsCount || 0) + 1;
          if (window._wsCount % 5 === 0) refreshMonitor();
        }
        if (msg.error) console.warn('[WS] 错误:', msg.error);
      } catch(er) {}
    };
    monitorWS.onclose = () => { console.log('[WS] 已断开，5秒后重连'); setTimeout(connectMonitorWS, 5000); };
    monitorWS.onerror = () => { monitorWS?.close(); };
  } catch(e) { console.log('[WS] 连接失败:', e); setTimeout(connectMonitorWS, 10000); }
}

async function loadMonitor() {
  const el = document.getElementById('monitorContent');
  if (window._monitorMap) { refreshMonitor(); return; }
  el.innerHTML = `<h2>🖥️ 实时监控</h2>
    <div style="display:flex;gap:12px;margin:12px 0">
      <div class="stat-card blue" style="flex:1;padding:12px;text-align:center"><div class="stat-num" id="mcOnline">0</div><div>在线</div></div>
      <div class="stat-card green" style="flex:1;padding:12px;text-align:center"><div class="stat-num" id="mcMoving">0</div><div>运动中</div></div>
      <div class="stat-card orange" style="flex:1;padding:12px;text-align:center"><div class="stat-num" id="mcStill">0</div><div>静止</div></div>
    </div>
    <div id="monitorMap" style="height:400px;border-radius:8px;margin-bottom:12px;border:1px solid #ddd"></div>
    <div id="monitorTable"></div>`;
  setTimeout(() => {
    if (!document.getElementById('monitorMap')) return;
    const m = makeMap('monitorMap', [113.90, 34.61], 12);
    window._monitorMap = m;
    refreshMonitor();
    connectMonitorWS();
    if (monitorTimer) clearInterval(monitorTimer);
    monitorTimer = setInterval(refreshMonitor, 10000);
  }, 200);
}

async function refreshMonitor() {
  const map = window._monitorMap;
  try {
    const data = await api('GET', '/api/v1/org/locations/online');
    const users = data.locations || [];
    const moving = users.filter(u => u.speed > 0).length;
    const el = document.getElementById('mcOnline'); if(el) el.textContent = users.length;
    const el2 = document.getElementById('mcMoving'); if(el2) el2.textContent = moving;
    const el3 = document.getElementById('mcStill'); if(el3) el3.textContent = users.length - moving;
    let html = '<table class="data-table"><tr><th>用户</th><th>部门</th><th>位置</th><th>速度</th><th>时间</th></tr>';
    users.forEach(u => html += `<tr><td>${u.name||u.userId}</td><td>${u.department||'--'}</td><td>${(u.lat||0).toFixed(4)},${(u.lng||0).toFixed(4)}</td><td>${(u.speed||0).toFixed(1)}km/h</td><td>${new Date(u.timestamp).toLocaleString()}</td></tr>`);
    html += users.length===0?'<tr><td colspan="5" style="text-align:center;color:#999">暂无在线人员</td></tr>':'</table>';
    document.getElementById('monitorTable').innerHTML = html;
    if (map) {
      monitorMks.forEach(mk => map.remove(mk));
      monitorMks = [];
      users.forEach(u => {
        if (!u.lat || !u.lng) return;
        const color = u.speed > 0 ? '#52c41a' : '#1677ff';
        const mk = new AMap.Marker({
          position: [u.lng, u.lat], map,
          content: `<div style="background:${color};color:white;width:30px;height:30px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:bold;border:2px solid white;box-shadow:0 2px 6px rgba(0,0,0,0.3)">${(u.name||u.userId||'?')[0]}</div>`,
          label: {content: `<b>${u.name||u.userId}</b><br>部门: ${u.department||'--'}<br>速度: ${(u.speed||0).toFixed(1)} km/h`, direction: 'right'}
        });
        monitorMks.push(mk);
      });
    }
  } catch(e) { console.error('Refresh error:', e); }
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
          <td><button onclick="deleteCustomer('${c.id}')" class="danger" style="padding:4px 10px;font-size:12px">删除</button></td>
        </tr>`).join('')}
      </table>`;
  } catch(e) { el.innerHTML = `<p style="color:red">加载失败: ${e.message}</p>`; }
}
window.addCustomer = async function() {
  const name = document.getElementById('custName').value.trim();
  const phone = document.getElementById('custPhone').value.trim();
  const btn = document.querySelector('[onclick="addCustomer()"]');
  if (!name) { document.getElementById('custResult').innerHTML = '❌ 名称必填'; return; }
  if (phone && (!/^1\d{10}$/.test(phone))) { document.getElementById('custResult').innerHTML = '❌ 手机号格式不正确（11位数字）'; return; }
  btn.disabled = true; btn.textContent = '⏳ 保存中...';
  try {
    await api('POST', '/api/v1/customers', {
      name, phone,
      address: document.getElementById('custAddr').value,
      lat: parseFloat(document.getElementById('custLat').value)||22.55,
      lng: parseFloat(document.getElementById('custLng').value)||114.08,
      tags: document.getElementById('custTags').value.split(',').map(s=>s.trim()).filter(Boolean),
      remark: document.getElementById('custRemark').value,
    });
    document.getElementById('custResult').innerHTML = '✅ 添加成功';
    document.getElementById('custName').value = '';
    document.getElementById('custPhone').value = '';
    loadCustomers();
  } catch(e) {
    document.getElementById('custResult').innerHTML = `❌ ${e.message}`;
  } finally {
    btn.disabled = false; btn.textContent = '➕ 添加';
  }
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
  if (!phone) { resultEl.innerHTML = '❌ 手机号不能为空'; return; }
  if (!/^\d{11}$/.test(phone)) { resultEl.innerHTML = '❌ 手机号必须是11位数字'; return; }
  if (!/^1\d{10}$/.test(phone)) { resultEl.innerHTML = '❌ 手机号必须以1开头'; return; }
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
//  👣 轨迹查询+地图回放
// ====================================================================
function loadTracks() {
  const today = new Date().toISOString().split('T')[0];
  document.getElementById('trackContent').innerHTML = `<h2>轨迹查询</h2><div class="card" style="padding:20px;margin:12px 0">
    <div class="form-row"><label>选择用户</label>
      <select id="trackUserId" style="flex:2;padding:6px 10px;border:1px solid #d9d9d9;border-radius:6px;font-size:14px">
        <option value="">-- 本人 --</option>
      </select>
    </div>
    <div class="form-row"><label>日期</label><input type="date" id="trackDate" value="${today}" style="flex:2" /></div>
    <button onclick="searchTrack()">🔍 查询</button>
    <span id="trackHint" style="margin-left:12px;font-size:13px;color:#999"></span>
  </div>
  <div id="trackResult"></div>`;
  loadUserOptions();
}
async function loadUserOptions() {
  try {
    const users = await api('GET', '/api/v1/org/users');
    const list = Array.isArray(users) ? users : (users.users || []);
    const sel = document.getElementById('trackUserId');
    if (!sel) return;
    list.forEach(u => {
      const opt = document.createElement('option');
      opt.value = u.id || u.userId;
      opt.textContent = `${u.name||'--'} (${u.phone||'无电话'})`;
      if (u.id === window._userId || u.phone === window._userPhone) opt.selected = true;
      sel.appendChild(opt);
    });
  } catch(e) {}
}
function haversine(lat1,lng1,lat2,lng2) { const R=6371; const dLat=(lat2-lat1)*Math.PI/180; const dLng=(lng2-lng1)*Math.PI/180; const a=Math.sin(dLat/2)**2+Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*Math.sin(dLng/2)**2; return R*2*Math.atan2(Math.sqrt(a),Math.sqrt(1-a)); }

// ==================== 轨迹地图回放（高德版） ====================
async function searchTrack() {
  const inputVal = document.getElementById('trackUserId').value;
  const uid = inputVal || window._userId || 'none';
  const date = document.getElementById('trackDate').value;
  const el = document.getElementById('trackResult');
  if (trackAnim) { clearInterval(trackAnim); trackAnim = null; trackPlaying = false; }
  trackPoints = [];
  el.innerHTML = `<p>查询中... (uid=${uid}, date=${date})</p>`;
  try {
    const url = `/api/v1/location/track/${uid}?date=${date}`;
    const resp = await fetch(url, { headers: { 'Authorization': `Bearer ${TOKEN}` } });
    if (!resp.ok) { const text = await resp.text(); throw new Error(`HTTP ${resp.status}: ${text.slice(0,200)}`); }
    const data = await resp.json();
    trackPoints = data.points || [];
    if (trackPoints.length === 0) { el.innerHTML = '<div class="card" style="padding:20px;text-align:center;color:#999">该日期无轨迹数据</div>'; return; }
    const totalKm = trackPoints.length > 1 ? trackPoints.reduce((s,p,i)=>i===0?0:s+haversine(trackPoints[i-1].lat,trackPoints[i-1].lng,p.lat,p.lng),0) : 0;
    const avgSpeed = trackPoints.reduce((s,p)=>s+(p.speed||0),0)/trackPoints.length;
    const durMs = trackPoints.length > 1 ? new Date(trackPoints[trackPoints.length-1].timestamp).getTime() - new Date(trackPoints[0].timestamp).getTime() : 0;
    el.innerHTML = `
      <div class="stats-grid" style="margin-bottom:12px">
        <div class="stat-card blue"><div class="stat-num">${trackPoints.length}</div><div>定位点数</div></div>
        <div class="stat-card green"><div class="stat-num">${totalKm.toFixed(2)}</div><div>里程(km)</div></div>
        <div class="stat-card orange"><div class="stat-num">${avgSpeed.toFixed(1)}</div><div>均速(km/h)</div></div>
        <div class="stat-card purple"><div class="stat-num">${(durMs/3600000).toFixed(1)}</div><div>时长(h)</div></div>
      </div>
      <div id="trackReplayControls" style="display:flex;align-items:center;gap:12px;margin-bottom:8px;background:white;padding:10px 16px;border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,0.04)">
        <button id="playBtn" onclick="toggleTrackPlay()" style="min-width:80px">▶ 播放</button>
        <span>速度:</span>
        ${TRACK_SPEEDS.map(s => `<button class="speed-btn${s===1?' active':''}" onclick="setTrackSpeed(${s})" style="min-width:40px;padding:4px 8px">${s}x</button>`).join('')}
        <span id="trackProgress" style="color:#666;font-size:13px;margin-left:auto">0 / ${trackPoints.length}</span>
        <span id="trackTimeLabel" style="color:#999;font-size:12px"></span>
      </div>
      <div id="trackMapContainer" style="height:400px;border-radius:10px;overflow:hidden;border:1px solid #ddd"></div>
      <div style="margin-top:12px">
        <button onclick="toggleTrackTable()" style="background:#666">📋 展开数据列表</button>
        <div id="trackTableWrap" style="display:none;margin-top:8px"></div>
      </div>`;

    if (trackMap) trackMap.destroy();
    trackMap = makeMap('trackMapContainer');
    const latlngs = trackPoints.map(p => [p.lng, p.lat]);
    trackPolyline = new AMap.Polyline({ path: latlngs, strokeColor: '#1677ff', strokeWeight: 3, strokeOpacity: 0.7, map: trackMap });
    trackMap.setFitView([trackPolyline]);
    trackIdx = 0; trackPlaying = false;
    new AMap.Marker({ position: latlngs[0], content: '<div style="background:#52c41a;width:12px;height:12px;border-radius:50%;border:2px solid white"></div>', map: trackMap });
    if (latlngs.length > 1) new AMap.Marker({ position: latlngs[latlngs.length-1], content: '<div style="background:#ff4d4f;width:12px;height:12px;border-radius:50%;border:2px solid white"></div>', map: trackMap });
    const tableHtml = `<table class="data-table"><tr><th>#</th><th>时间</th><th>经度</th><th>纬度</th><th>速度</th></tr>${
      trackPoints.map((p,i)=>`<tr><td>${i+1}</td><td>${new Date(p.timestamp||p.time).toLocaleString()}</td><td>${(p.lng||0).toFixed(4)}</td><td>${(p.lat||0).toFixed(4)}</td><td>${(p.speed||0).toFixed(1)}</td></tr>`).join('')}</table>`;
    document.getElementById('trackTableWrap').innerHTML = tableHtml;
    document.getElementById('trackTimeLabel').textContent = new Date(trackPoints[0].timestamp).toLocaleString();
  } catch(e) { el.innerHTML = `<p style="color:red">查询失败: ${e.message}</p>`; }
}

function toggleTrackPlay() {
  const btn = document.getElementById('playBtn');
  if (trackPlaying) { trackPlaying=false; if(trackAnim){clearInterval(trackAnim);trackAnim=null;} btn.textContent='▶ 播放'; return; }
  if (trackIdx >= trackPoints.length - 1) trackIdx = 0;
  trackPlaying = true; btn.textContent = '⏸ 暂停'; trackAnimMove();
  trackAnim = setInterval(trackAnimMove, Math.max(50, 200 / trackSpeed));
}
function trackAnimMove() {
  if (!trackPlaying) return;
  if (trackIdx >= trackPoints.length) { trackPlaying=false; if(trackAnim){clearInterval(trackAnim);trackAnim=null;} document.getElementById('playBtn').textContent='▶ 播放'; return; }
  const p = trackPoints[trackIdx];
  if (trackMarker) trackMap.remove(trackMarker);
  const color = (p.speed||0) > 0 ? '#52c41a' : '#1677ff';
  trackMarker = new AMap.Marker({
    position: [p.lng, p.lat], map: trackMap,
    content: `<div style="background:${color};width:10px;height:10px;border-radius:50%;border:2px solid white"></div>`
  });
  trackIdx++;
  document.getElementById('trackProgress').textContent = `${trackIdx} / ${trackPoints.length}`;
  document.getElementById('trackTimeLabel').textContent = new Date(p.timestamp).toLocaleString();
}
function setTrackSpeed(speed) {
  trackSpeed = speed;
  document.querySelectorAll('.speed-btn').forEach(b => b.classList.toggle('active', parseInt(b.textContent) === speed));
  if (trackPlaying) { if(trackAnim)clearInterval(trackAnim); trackAnim=setInterval(trackAnimMove, Math.max(50, 200 / trackSpeed)); }
}
function toggleTrackTable() { const w=document.getElementById('trackTableWrap'); w.style.display=w.style.display==='none'?'block':'none'; }

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
