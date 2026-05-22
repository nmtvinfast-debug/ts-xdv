import express from 'express';
import { createAuthMiddleware } from '../middleware/user_permissions.js';
import { sqlWorkshopMatch } from '../lib/workshop_scope.js';
import {
  parseBearerActor,
  sanitizeRepairOrderPatchBody,
  repairOrderMilestoneSqlFragments,
  appendRepairOrderAuditHistory,
  applyPauseResumeOnStatusChange,
  enrichRepairOrderRow,
  lightenRepairOrderForList,
} from '../lib/ro_time_rules.js';
import {
  tryNotifyPartsArrivalComplete,
  repairOrderPartsReadyForSettlement,
  mergePartsPreserveIssuedQty,
} from '../lib/part_arrival_notify.js';
import { tryNotifyCvdvQuanDocApproved } from '../lib/cvdv_qd_notify.js';

function parseBearerUserId(req) {
  const raw = req.headers.authorization || '';
  const m = /^Bearer\s+auth_token_([0-9a-f-]{36})$/i.exec(String(raw).trim());
  return m ? m[1] : null;
}

export function createRepairOrdersRouter(pool) {
  const r = express.Router();
  const auth = createAuthMiddleware(pool);

  r.get('/', auth, async (req, res) => {
    try {
      const scope = sqlWorkshopMatch('', req.user, 1);
      const vals = scope.value !== undefined ? [scope.value] : [];
      const result = await pool.query(
        `SELECT * FROM repair_orders WHERE 1=1${scope.clause} ORDER BY time_in DESC`,
        vals,
      );
      res.json(
        result.rows.map((row) => enrichRepairOrderRow(lightenRepairOrderForList(row))),
      );
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.get('/:id', auth, async (req, res) => {
    try {
      const scope = sqlWorkshopMatch('', req.user, 2);
      const vals = [req.params.id];
      if (scope.value !== undefined) vals.push(scope.value);
      const result = await pool.query(
        `SELECT * FROM repair_orders WHERE id = $1${scope.clause}`,
        vals,
      );
      if (result.rowCount === 0) return res.status(404).json({ error: 'Không tìm thấy RO' });
      res.json(enrichRepairOrderRow(result.rows[0]));
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.post('/', auth, async (req, res) => {
    let { ro_code, bien_so, customer_name, customer_phone, cvdv_username, customer_note, position, images } = req.body || {};
    if (!ro_code) ro_code = `RO-${Date.now().toString().slice(-6)}`;
    if (!customer_note && position) customer_note = `Vị trí: ${position}`;
    try {
      const result = await pool.query(
        `INSERT INTO repair_orders (ro_code, bien_so, customer_name, customer_phone, cvdv_username, customer_note, images, xdv_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
        [
          ro_code,
          bien_so,
          customer_name,
          customer_phone,
          cvdv_username,
          customer_note,
          images ? JSON.stringify(images) : '[]',
          req.user.xdv_id ?? null,
        ],
      );
      const row = result.rows[0];
      const actor = parseBearerActor(req);
      if (actor) {
        const firstAudit = appendRepairOrderAuditHistory(
          { audit_history: row.audit_history || [] },
          null,
          row.status || 'XE_VAO_XUONG',
          customer_note || null,
          actor,
          'create_ro',
        );
        await pool.query(
          `UPDATE repair_orders SET audit_history = $1::jsonb, last_status_changed_at = COALESCE(last_status_changed_at, time_in, NOW()) WHERE id = $2`,
          [JSON.stringify(firstAudit), row.id],
        );
        row.audit_history = firstAudit;
      } else {
        await pool.query(
          `UPDATE repair_orders SET last_status_changed_at = COALESCE(last_status_changed_at, time_in, NOW()) WHERE id = $1`,
          [row.id],
        );
      }
      const refreshed = await pool.query(`SELECT * FROM repair_orders WHERE id = $1`, [row.id]);
      const outRow = refreshed.rows[0] || row;
      res.status(201).json(enrichRepairOrderRow(outRow));
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  const handlePatchRepairOrder = async (req, res) => {
    const { id } = req.params;
    const pauseReason = req.body.pause_reason;
    const updates = sanitizeRepairOrderPatchBody(req.body);
    const actor = parseBearerActor(req);
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const scope = sqlWorkshopMatch('', req.user, 2);
      const curVals = [id];
      if (scope.value !== undefined) curVals.push(scope.value);
      const cur = await client.query(
        `SELECT * FROM repair_orders WHERE id = $1${scope.clause} FOR UPDATE`,
        curVals,
      );
      if (cur.rowCount === 0) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Không tìm thấy RO' });
      }
      const oldRow = cur.rows[0];
      const oldStatus = oldRow.status;
      const newStatus = updates.status !== undefined ? updates.status : oldStatus;

      let actorRole = '';
      if (actor?.user_id) {
        const roleRes = await client.query(`SELECT role FROM users WHERE id = $1 LIMIT 1`, [actor.user_id]);
        if (roleRes.rowCount > 0) {
          actorRole = String(roleRes.rows[0].role || '')
            .toUpperCase()
            .replace(/\s/g, '')
            .replace('Ố', 'O')
            .replace('Ấ', 'A');
        }
      }
      const warehouseRoles = new Set(['KHO', 'ADMIN', 'GIAMDOC']);
      const canEditIssuedQty = warehouseRoles.has(actorRole);

      if (Object.prototype.hasOwnProperty.call(updates, 'parts') && !canEditIssuedQty) {
        updates.parts = mergePartsPreserveIssuedQty(oldRow.parts, updates.parts);
      }

      const partsForSettlementCheck = Object.prototype.hasOwnProperty.call(updates, 'parts')
        ? updates.parts
        : oldRow.parts;
      if (updates.status !== undefined && newStatus === 'CHO_QUYET_TOAN' && newStatus !== oldStatus) {
        if (!repairOrderPartsReadyForSettlement(partsForSettlementCheck)) {
          await client.query('ROLLBACK');
          return res.status(400).json({
            error:
              'Kho chưa xuất đủ phụ tùng theo báo giá. Chỉ chuyển kế toán sau khi Kho xác nhận xuất ở tab «Xuất kho».',
          });
        }
      }

      if (updates.ktv_username !== undefined) {
        const oldK = String(oldRow.ktv_username || '')
          .trim()
          .toLowerCase();
        const newK = String(updates.ktv_username ?? '')
          .trim()
          .toLowerCase();
        if (oldK !== newK) updates.fault_diagnosis_at = null;
      }

      if (updates.status !== undefined && newStatus !== oldStatus) {
        const note = updates.status_note ?? updates.customer_note ?? updates.urgent_note;
        updates.audit_history = appendRepairOrderAuditHistory(oldRow, oldStatus, newStatus, note, actor);
        const newPauses = applyPauseResumeOnStatusChange(oldRow, oldStatus, newStatus, pauseReason, actor);
        if (newPauses) updates.pauses = newPauses;
        else if (Object.prototype.hasOwnProperty.call(updates, 'pauses')) delete updates.pauses;
      }

      const fields = [];
      const values = [];
      let i = 1;
      for (const [key, value] of Object.entries(updates)) {
        fields.push(`${key} = $${i}`);
        values.push(typeof value === 'object' && value !== null ? JSON.stringify(value) : value);
        i++;
      }
      if (fields.length === 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Không có dữ liệu cập nhật' });
      }

      const extraSql = [];
      if (updates.status !== undefined && newStatus !== oldStatus) {
        extraSql.push('last_status_changed_at = NOW()');
        for (const frag of repairOrderMilestoneSqlFragments(newStatus)) {
          extraSql.push(frag);
        }
        if (newStatus === 'CHO_QD_KIEM_TRA') {
          extraSql.push('fault_diagnosis_at = COALESCE(fault_diagnosis_at, NOW())');
        }
      }
      const hadCvdv = oldRow.cvdv_username && String(oldRow.cvdv_username).trim() !== '';
      const nextCvdv = updates.cvdv_username;
      const willHaveCvdv = nextCvdv !== undefined && nextCvdv !== null && String(nextCvdv).trim() !== '';
      if (!hadCvdv && willHaveCvdv) {
        extraSql.push('time_receive = COALESCE(time_receive, NOW())');
      }
      for (const frag of extraSql) {
        fields.push(frag);
      }
      fields.push(`updated_at = NOW()`);
      const query = `UPDATE repair_orders SET ${fields.join(', ')} WHERE id = $${i} RETURNING *`;
      values.push(id);
      const result = await client.query(query, values);
      const rowOut = result.rows[0];
      if (
        updates.status !== undefined &&
        newStatus !== oldStatus &&
        newStatus === 'CHO_KH_DUYET'
      ) {
        const linked = String(rowOut.linked_customer || '').trim().toLowerCase();
        if (linked) {
          const ures = await client.query(
            `SELECT id FROM users WHERE LOWER(TRIM(username)) = $1 AND COALESCE(is_active, true) = true LIMIT 1`,
            [linked],
          );
          if (ures.rowCount > 0) {
            const customerId = ures.rows[0].id;
            const dup = await client.query(
              `SELECT id FROM notifications
               WHERE user_id = $1 AND (data->>'type') = 'QUOTE_PENDING_APPROVAL'
                 AND (data->>'repair_order_id') = $2
                 AND created_at > NOW() - INTERVAL '48 hours'
               LIMIT 1`,
              [customerId, id],
            );
            if (dup.rowCount === 0) {
              const bien = String(rowOut.bien_so || '').trim();
              const roCode = String(rowOut.ro_code || '').trim();
              await client.query(
                `INSERT INTO notifications (user_id, title, body, data) VALUES ($1, $2, $3, $4::jsonb)`,
                [
                  customerId,
                  `Duyệt báo giá — ${bien || roCode}`,
                  `RO ${roCode}: xưởng đã gửi báo giá. Mở «Xe của tôi» để xem chi tiết và duyệt.`,
                  JSON.stringify({
                    type: 'QUOTE_PENDING_APPROVAL',
                    repair_order_id: id,
                    bien_so: bien,
                    ro_code: roCode,
                  }),
                ],
              );
            }
          }
        }
      }
      if (
        updates.status !== undefined &&
        newStatus !== oldStatus &&
        newStatus === 'CHO_CVDV_CHOT' &&
        oldStatus === 'CHO_QD_KIEM_TRA'
      ) {
        try {
          await tryNotifyCvdvQuanDocApproved(client, rowOut, { fromStatus: oldStatus });
        } catch (notifyErr) {
          console.warn('[tryNotifyCvdvQuanDocApproved]', notifyErr?.message || notifyErr);
        }
      }
      await client.query('COMMIT');
      if (Object.prototype.hasOwnProperty.call(updates, 'parts')) {
        try {
          await tryNotifyPartsArrivalComplete(pool, rowOut);
        } catch (notifyErr) {
          console.warn('[tryNotifyPartsArrivalComplete]', notifyErr?.message || notifyErr);
        }
      }
      res.json(enrichRepairOrderRow(result.rows[0]));
    } catch (err) {
      await client.query('ROLLBACK');
      res.status(500).json({ error: err.message });
    } finally {
      client.release();
    }
  };

  r.patch('/:id', auth, handlePatchRepairOrder);
  r.put('/:id', auth, handlePatchRepairOrder);

  r.delete('/:id', auth, async (req, res) => {
    try {
      const scope = sqlWorkshopMatch('', req.user, 2);
      const vals = [req.params.id];
      if (scope.value !== undefined) vals.push(scope.value);
      const result = await pool.query(
        `DELETE FROM repair_orders WHERE id = $1${scope.clause} RETURNING id`,
        vals,
      );
      if (result.rowCount === 0) return res.status(404).json({ error: 'Không tìm thấy RO' });
      res.json({ message: 'Đã xóa xe nhập nhầm' });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  /**
   * Kho gọi sau khi cập nhật parts (nhập đủ → issuedQty đủ): báo CVDV (xe trong xưởng) hoặc tin nhắn app KH (DA_RA_CONG_THIEU_PT).
   */
  r.post('/:id/part-arrival-notify', async (req, res) => {
    const actorId = parseBearerUserId(req);
    if (!actorId) return res.status(401).json({ error: 'Chưa đăng nhập' });
    const { id } = req.params;
    try {
      const ures = await pool.query(`SELECT role FROM users WHERE id = $1`, [actorId]);
      if (ures.rowCount === 0) return res.status(401).json({ error: 'User không tồn tại' });
      const role = String(ures.rows[0].role || '')
        .toUpperCase()
        .replace(/\s/g, '')
        .replace('Ố', 'O')
        .replace('Ấ', 'A');
      const allowed = new Set(['KHO', 'ADMIN', 'GIAMDOC']);
      if (!allowed.has(role)) {
        return res.status(403).json({ error: 'Chỉ tài khoản Kho / Admin / Giám đốc được gọi API này' });
      }

      const roRes = await pool.query(`SELECT * FROM repair_orders WHERE id = $1`, [id]);
      if (roRes.rowCount === 0) return res.status(404).json({ error: 'Không tìm thấy RO' });
      const row = roRes.rows[0];
      const result = await tryNotifyPartsArrivalComplete(pool, row);
      return res.json(result);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  return r;
}
