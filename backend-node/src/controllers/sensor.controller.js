const { pool } = require('../config/database');

async function logSensor(req, res) {
  try {
    const { sensor_type, value, unit, timestamp } = req.body;
    if (!sensor_type || value === undefined) return res.status(400).json({ success: false, message: 'sensor_type dan value wajib diisi.' });
    const validTypes = ['suhu', 'kelembaban', 'gas_co'];
    if (!validTypes.includes(sensor_type)) return res.status(400).json({ success: false, message: `sensor_type harus salah satu dari: ${validTypes.join(', ')}` });
    const result = await pool.query(
      `INSERT INTO sensor_logs (sensor_type, value, unit, timestamp) VALUES ($1, $2, $3, $4) RETURNING *`,
      [sensor_type, value, unit || '', timestamp || new Date().toISOString()]
    );
    return res.status(201).json({ success: true, data: result.rows[0] });
  } catch (err) {
    console.error('LogSensor Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getSensorLogs(req, res) {
  try {
    const { sensor_type, limit } = req.query;
    let query = 'SELECT * FROM sensor_logs WHERE 1=1';
    const params = [];
    if (sensor_type) { params.push(sensor_type); query += ` AND sensor_type = $${params.length}`; }
    query += ' ORDER BY timestamp DESC';
    params.push(parseInt(limit) || 100);
    query += ` LIMIT $${params.length}`;
    const result = await pool.query(query, params);
    return res.status(200).json({ success: true, count: result.rows.length, data: result.rows });
  } catch (err) {
    console.error('GetSensorLogs Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

async function getLatestSensorData(req, res) {
  try {
    const result = await pool.query(`
      SELECT DISTINCT ON (sensor_type) sensor_type, value, unit, timestamp
      FROM sensor_logs ORDER BY sensor_type, timestamp DESC
    `);
    return res.status(200).json({ success: true, data: result.rows });
  } catch (err) {
    console.error('GetLatestSensorData Error:', err.message);
    return res.status(500).json({ success: false, message: 'Terjadi kesalahan server.' });
  }
}

module.exports = { logSensor, getSensorLogs, getLatestSensorData };
