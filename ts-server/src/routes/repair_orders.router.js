const express = require('express');

function createRepairOrdersRouter(db) {
  const router = express.Router();

  // ==========================================
  // LẤY DANH SÁCH XE (BẢNG BOARD) - CHỨA RULE 7 (ƯU TIÊN) VÀ RULE 5 (SLA)
  // ==========================================
  router.get('/board', async (req, res) => {
    try {
      // CÂU LỆNH SQL CỰC MẠNH: Tự động tính phút chờ và cộng điểm ưu tiên ngay trong DB
      const sql = `
        SELECT 
          ro.*,
          -- Tính số phút đã trôi qua ở trạng thái hiện tại (Rule 2)
          EXTRACT(EPOCH FROM (NOW() - ro.updated_at))/60 AS minutes_in_state,
          
          -- RULE 7: ĐỘNG CƠ CHẤM ĐIỂM ƯU TIÊN (PRIORITY ENGINE)
          (
            -- Khách đợi tại xưởng (+100đ)
            CASE WHEN ro.status IN ('XE_VAO_XUONG', 'CHO_BAO_GIA', 'CHO_KH_DUYET') THEN 100 ELSE 0 END
            +
            -- Quá hạn SLA 15p chưa phân công (+80đ)
            CASE WHEN (ro.status = 'XE_VAO_XUONG' AND EXTRACT(EPOCH FROM (NOW() - ro.updated_at))/60 > 15) THEN 80 ELSE 0 END
            +
            -- Quá hạn SLA 30p chưa báo giá (+80đ)
            CASE WHEN (ro.status = 'CHO_BAO_GIA' AND EXTRACT(EPOCH FROM (NOW() - ro.updated_at))/60 > 30) THEN 80 ELSE 0 END
          ) AS priority_score

        FROM repair_orders ro
        WHERE ro.status != 'DA_XUAT_XUONG'
        ORDER BY priority_score DESC, ro.updated_at ASC
      `;
      
      const { rows } = await db.query(sql);

      // Chuyển format dữ liệu trả về cho App Flutter
      const items = rows.map(r => ({
        id: r.id,
        ro_code: r.ro_code,
        status: r.status,
        bien_so: r.bien_so,
        customer_name: r.customer_name,
        customer_phone: r.customer_phone,
        position: r.position,
        cvdv_username: r.cvdv_username,
        linked_customer: r.linked_customer,
        link_requested_by: r.link_requested_by,
        jobs: r.jobs ? JSON.stringify(r.jobs) : '[]',
        parts: r.parts ? JSON.stringify(r.parts) : '[]',
        chat_logs: r.chat_logs ? JSON.stringify(r.chat_logs) : '[]',
        timeline: r.timeline || [],
        priority_score: r.priority_score,
        minutes_in_state: Math.floor(r.minutes_in_state),
        created_at: r.created_at,
        updated_at: r.updated_at
      }));

      res.json({ ok: true, items });
    } catch (e) {
      console.error(e);
      res.status(500).json({ ok: false, error: e.message });
    }
  });

  // ==========================================
  // TIẾP NHẬN XE MỚI (BẢO VỆ)
  // ==========================================
  router.post('/', async (req, res) => {
    try {
      const body = req.body;
      const roCode = 'RO' + Math.floor(1000 + Math.random() * 9000);
      const initialTimeline = JSON.stringify([{ 
        status: 'XE_VAO_XUONG', 
        time: new Date().toISOString(), 
        note: 'Bảo vệ tiếp nhận xe' 
      }]);

      // RULE 1: Lưu time_in
      const sql = `
        INSERT INTO repair_orders (
          ro_code, status, bien_so, customer_name, customer_phone, position, 
          timeline, time_in, created_at, updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, NOW(), NOW(), NOW())
        RETURNING *
      `;
      const values = [
        roCode, 'XE_VAO_XUONG', body.bien_so, body.customer_name, 
        body.customer_phone, body.position, initialTimeline
      ];

      const { rows } = await db.query(sql, values);
      res.status(201).json({ ok: true, item: rows[0] });
    } catch (e) {
      console.error(e);
      res.status(500).json({ ok: false, error: e.message });
    }
  });

  // ==========================================
  // CẬP NHẬT TRẠNG THÁI & LƯU VẾT TIMESTAMP (RULE 1, 4, 11)
  // ==========================================
  router.patch('/:id', async (req, res) => {
    const client = await db.connect();
    try {
      await client.query('BEGIN');
      const body = req.body;
      const orderId = req.params.id;

      // Lấy data cũ để so sánh
      const oldRes = await client.query('SELECT * FROM repair_orders WHERE id = $1 FOR UPDATE', [orderId]);
      if (oldRes.rowCount === 0) throw new Error('Không tìm thấy RO');
      const oldOrder = oldRes.rows[0];

      let newStatus = body.status || oldOrder.status;
      let timeline = oldOrder.timeline || [];
      let updates = [];
      let values = [];
      let vIdx = 1;

      // RULE 11: NẾU ĐỔI TRẠNG THÁI -> GHI TIMELINE VÀ CHỐT TIMESTAMP
      if (newStatus !== oldOrder.status) {
        timeline.push({ 
          status: newStatus, 
          time: new Date().toISOString(), 
          note: body.status_note || 'Cập nhật trạng thái' 
        });
        
        updates.push(`timeline = $${vIdx++}::jsonb`);
        values.push(JSON.stringify(timeline));

        // RULE 1: Bắt Mốc thời gian (Timestamps)
        if (newStatus === 'CHO_BAO_GIA' && !oldOrder.time_quote_created) {
          updates.push(`time_quote_created = NOW()`);
        }
        if (newStatus === 'CHO_KH_DUYET') {
          updates.push(`time_quote_sent = NOW()`);
        }
        if (newStatus === 'CHO_PHAN_CONG') {
          updates.push(`time_quote_approved = NOW()`);
        }
        if (newStatus === 'DANG_SUA' && !oldOrder.time_start) {
          updates.push(`time_start = NOW()`);
        }
        if (newStatus === 'CHO_QUYET_TOAN') {
          updates.push(`time_done = NOW()`);
        }
        if (newStatus === 'DA_THANH_TOAN') {
          updates.push(`time_paid = NOW()`);
        }
        if (newStatus === 'DA_XUAT_XUONG') {
          updates.push(`time_out = NOW()`);
        }

        // Cập nhật status
        updates.push(`status = $${vIdx++}`);
        values.push(newStatus);
      }

      // Cập nhật các trường dữ liệu khác
      if (body.jobs) { updates.push(`jobs = $${vIdx++}::jsonb`); values.push(body.jobs); }
      if (body.parts) { updates.push(`parts = $${vIdx++}::jsonb`); values.push(body.parts); }
      if (body.chat_logs) { updates.push(`chat_logs = $${vIdx++}::jsonb`); values.push(body.chat_logs); }
      if (body.cvdv_username) { updates.push(`cvdv_username = $${vIdx++}`); values.push(body.cvdv_username); }
      if (body.linked_customer !== undefined) { updates.push(`linked_customer = $${vIdx++}`); values.push(body.linked_customer); }
      if (body.link_requested_by !== undefined) { updates.push(`link_requested_by = $${vIdx++}`); values.push(body.link_requested_by); }

      updates.push(`updated_at = NOW()`);

      // Gắn ID vào cuối mảng values
      values.push(orderId);

      const sql = `
        UPDATE repair_orders 
        SET ${updates.join(', ')} 
        WHERE id = $${vIdx} 
        RETURNING *
      `;

      const { rows } = await client.query(sql, values);
      await client.query('COMMIT');
      
      res.json({ ok: true, item: rows[0] });
    } catch (e) {
      await client.query('ROLLBACK');
      console.error(e);
      res.status(500).json({ ok: false, error: e.message });
    } finally {
      client.release();
    }
  });

  router.delete('/:id', async (req, res) => {
    try {
      await db.query('DELETE FROM repair_orders WHERE id = $1', [req.params.id]);
      res.json({ ok: true, success: true });
    } catch (e) {
      res.status(500).json({ ok: false, error: e.message });
    }
  });

  return router;
}

module.exports = { createRepairOrdersRouter };