const express = require('express');
const { requireRoles } = require('../middleware/require_roles');
const svc = require('../services/admin_workshops.service');

function createAdminWorkshopsRouter(db) {
  const router = express.Router();

  router.use(requireRoles('admin_tong', 'admin_global', 'admin'));

  router.get('/', async (req, res) => {
    try {
      const items = await svc.listWorkshops(db, req.query.q || '');
      res.json({ ok: true, items });
    } catch (e) {
      res.status(500).json({ ok: false, error: e.message });
    }
  });

  router.post('/', async (req, res) => {
    try {
      const data = await svc.createWorkshopWithDirector(db, req.body || {});
      res.status(201).json({ ok: true, ...data });
    } catch (e) {
      const code = /tồn tại|thiếu/i.test(e.message) ? 400 : 500;
      res.status(code).json({ ok: false, error: e.message });
    }
  });

  router.patch('/:id', async (req, res) => {
    try {
      const item = await svc.updateWorkshop(db, req.params.id, req.body || {});
      res.json({ ok: true, item });
    } catch (e) {
      const code = /không tìm thấy/i.test(e.message) ? 404 : 400;
      res.status(code).json({ ok: false, error: e.message });
    }
  });

  router.post('/:id/reset_director_password', async (req, res) => {
    try {
      const out = await svc.resetDirectorPassword(db, req.params.id, req.body?.new_password || '');
      res.json({ ok: true, ...out });
    } catch (e) {
      const code = /không hợp lệ|chưa có|không tìm thấy/i.test(e.message) ? 400 : 500;
      res.status(code).json({ ok: false, error: e.message });
    }
  });

  return router;
}

module.exports = { createAdminWorkshopsRouter };
