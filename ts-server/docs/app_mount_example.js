// Ví dụ mount route vào Express app hiện tại

const express = require('express');
const { Pool } = require('pg');
const { createAdminWorkshopsRouter } = require('../src/routes/admin_workshops.router');
const { createUsersRouter } = require('../src/routes/users.router');

const app = express();
const db = new Pool({ connectionString: process.env.DATABASE_URL });

app.use(express.json());

// auth middleware hiện tại của bạn phải gắn req.user trước đoạn này
app.use('/api/v1/admin/workshops', createAdminWorkshopsRouter(db));
app.use('/api/v1/users', createUsersRouter(db));

module.exports = app;
