// server.js
const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// Database connection
const pool = new Pool({
  user: process.env.DB_USER || 'postgres',
  host: process.env.DB_HOST || 'localhost',
  database: process.env.DB_NAME || 'printmonitor',
  password: process.env.DB_PASSWORD || 'password',
  port: process.env.DB_PORT || 5432,
});

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Initialize database tables
async function initDB() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS print_jobs (
        id SERIAL PRIMARY KEY,
        job_id VARCHAR(100),
        user_name VARCHAR(100) NOT NULL,
        machine_name VARCHAR(100) NOT NULL,
        printer_name VARCHAR(200) NOT NULL,
        document_name VARCHAR(500),
        page_count INTEGER DEFAULT 0,
        print_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        status VARCHAR(50) DEFAULT 'completed',
        file_size BIGINT DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(100) UNIQUE NOT NULL,
        full_name VARCHAR(200),
        department VARCHAR(100),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS printers (
        id SERIAL PRIMARY KEY,
        name VARCHAR(200) UNIQUE NOT NULL,
        location VARCHAR(200),
        cost_per_page DECIMAL(10,4) DEFAULT 0.05,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    console.log('Database tables initialized');
  } catch (err) {
    console.error('Database initialization error:', err);
  }
}

// Routes

// Accept print job from Windows client
app.post('/api/print-jobs', async (req, res) => {
  try {
    const {
      jobId,
      userName,
      machineName,
      printerName,
      documentName,
      pageCount,
      printTime,
      status,
      fileSize
    } = req.body;

    const result = await pool.query(
      `INSERT INTO print_jobs 
       (job_id, user_name, machine_name, printer_name, document_name, 
        page_count, print_time, status, file_size) 
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) 
       RETURNING *`,
      [jobId, userName, machineName, printerName, documentName, 
       pageCount, printTime || new Date(), status, fileSize]
    );

    res.status(201).json({
      success: true,
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error saving print job:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to save print job'
    });
  }
});

// Get all print jobs with pagination and filters
app.get('/api/print-jobs', async (req, res) => {
  try {
    const {
      page = 1,
      limit = 50,
      user,
      printer,
      startDate,
      endDate,
      search
    } = req.query;

    let query = 'SELECT * FROM print_jobs WHERE 1=1';
    let params = [];
    let paramCount = 0;

    if (user) {
      paramCount++;
      query += ` AND user_name ILIKE $${paramCount}`;
      params.push(`%${user}%`);
    }

    if (printer) {
      paramCount++;
      query += ` AND printer_name ILIKE $${paramCount}`;
      params.push(`%${printer}%`);
    }

    if (startDate) {
      paramCount++;
      query += ` AND print_time >= $${paramCount}`;
      params.push(startDate);
    }

    if (endDate) {
      paramCount++;
      query += ` AND print_time <= $${paramCount}`;
      params.push(endDate);
    }

    if (search) {
      paramCount++;
      query += ` AND (document_name ILIKE $${paramCount} OR user_name ILIKE $${paramCount})`;
      params.push(`%${search}%`);
    }

    query += ' ORDER BY print_time DESC';
    
    // Add pagination
    const offset = (page - 1) * limit;
    paramCount++;
    query += ` LIMIT $${paramCount}`;
    params.push(limit);
    
    paramCount++;
    query += ` OFFSET $${paramCount}`;
    params.push(offset);

    const result = await pool.query(query, params);
    
    // Get total count
    let countQuery = 'SELECT COUNT(*) FROM print_jobs WHERE 1=1';
    let countParams = [];
    let countParamCount = 0;

    if (user) {
      countParamCount++;
      countQuery += ` AND user_name ILIKE $${countParamCount}`;
      countParams.push(`%${user}%`);
    }

    if (printer) {
      countParamCount++;
      countQuery += ` AND printer_name ILIKE $${countParamCount}`;
      countParams.push(`%${printer}%`);
    }

    if (startDate) {
      countParamCount++;
      countQuery += ` AND print_time >= $${countParamCount}`;
      countParams.push(startDate);
    }

    if (endDate) {
      countParamCount++;
      countQuery += ` AND print_time <= $${countParamCount}`;
      countParams.push(endDate);
    }

    if (search) {
      countParamCount++;
      countQuery += ` AND (document_name ILIKE $${countParamCount} OR user_name ILIKE $${countParamCount})`;
      countParams.push(`%${search}%`);
    }

    const countResult = await pool.query(countQuery, countParams);
    const totalCount = parseInt(countResult.rows[0].count);

    res.json({
      success: true,
      data: result.rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalCount,
        pages: Math.ceil(totalCount / limit)
      }
    });
  } catch (err) {
    console.error('Error fetching print jobs:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch print jobs'
    });
  }
});

// Get print statistics
app.get('/api/stats', async (req, res) => {
  try {
    const { startDate, endDate } = req.query;
    
    let dateFilter = '';
    let params = [];
    
    if (startDate && endDate) {
      dateFilter = 'WHERE print_time >= $1 AND print_time <= $2';
      params = [startDate, endDate];
    }

    const [totalJobs, totalPages, topUsers, topPrinters] = await Promise.all([
      pool.query(`SELECT COUNT(*) as count FROM print_jobs ${dateFilter}`, params),
      pool.query(`SELECT SUM(page_count) as total FROM print_jobs ${dateFilter}`, params),
      pool.query(`
        SELECT user_name, COUNT(*) as job_count, SUM(page_count) as page_count 
        FROM print_jobs ${dateFilter}
        GROUP BY user_name 
        ORDER BY page_count DESC 
        LIMIT 10
      `, params),
      pool.query(`
        SELECT printer_name, COUNT(*) as job_count, SUM(page_count) as page_count 
        FROM print_jobs ${dateFilter}
        GROUP BY printer_name 
        ORDER BY job_count DESC 
        LIMIT 10
      `, params)
    ]);

    res.json({
      success: true,
      data: {
        totalJobs: parseInt(totalJobs.rows[0].count),
        totalPages: parseInt(totalPages.rows[0].total || 0),
        topUsers: topUsers.rows,
        topPrinters: topPrinters.rows
      }
    });
  } catch (err) {
    console.error('Error fetching stats:', err);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch statistics'
    });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

// Start server
async function startServer() {
  await initDB();
  app.listen(PORT, () => {
    console.log(`Print Monitor API running on port ${PORT}`);
    console.log(`Health check: http://localhost:${PORT}/health`);
    console.log(`API endpoints: http://localhost:${PORT}/api/`);
  });
}

startServer();