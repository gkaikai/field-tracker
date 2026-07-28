const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
(async () => {
  const pool = new Pool({ host: 'localhost', port: 5432, database: 'field_tracker', user: 'postgres', password: 'postgres' });
  const hash = await bcrypt.hash('admin123', 10);
  await pool.query('UPDATE users SET password_hash = $1 WHERE phone = $2', [hash, '13800138000']);
  console.log('OK: 13800138000 -> admin123');
  await pool.query('UPDATE users SET password_hash = $1 WHERE phone = $2', [hash, '13632703458']);
  console.log('OK: 13632703458 -> admin123');
  await pool.end();
})();
