-- Initialize database tables
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
);
CREATE TABLE IF NOT EXISTS users (
id SERIAL PRIMARY KEY,
username VARCHAR(100) UNIQUE NOT NULL,
full_name VARCHAR(200),
department VARCHAR(100),
created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS printers (
id SERIAL PRIMARY KEY,
name VARCHAR(200) UNIQUE NOT NULL,
location VARCHAR(200),
cost_per_page DECIMAL(10,4) DEFAULT 0.05,
created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- Insert sample data
INSERT INTO users (username, full_name, department) VALUES
('john.doe', 'John Doe', 'IT'),
('jane.smith', 'Jane Smith', 'Marketing'),
('bob.wilson', 'Bob Wilson', 'Finance')
ON CONFLICT (username) DO NOTHING;
INSERT INTO printers (name, location, cost_per_page) VALUES
('HP LaserJet Pro', 'Office Floor 1', 0.05),
('Canon ImageRunner', 'Office Floor 2', 0.07)
ON CONFLICT (name) DO NOTHING;
