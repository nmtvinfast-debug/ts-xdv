/**

 * Sau nhập/xuất kho: kiểm tra RO đã đủ phát/xuất phụ tùng theo báo giá (issuedQty >= qty).

 */



export function normalizePartsArray(raw) {

  if (raw == null) return [];

  if (Array.isArray(raw)) return raw;

  if (typeof raw === 'string') {

    try {

      const p = JSON.parse(raw);

      return Array.isArray(p) ? p : [];

    } catch {

      return [];

    }

  }

  return [];

}



export function quotedPartsNeedWarehouseIssue(partsArr) {
  for (const p of normalizePartsArray(partsArr)) {
    const qty = Number(p?.qty ?? p?.hours ?? 0);
    if (Number.isFinite(qty) && qty > 0) return true;
  }
  return false;
}

export function repairOrderPartsReadyForSettlement(partsArr) {
  const arr = normalizePartsArray(partsArr);
  if (!quotedPartsNeedWarehouseIssue(arr)) return true;
  return allQuotedPartsFullyIssued(arr);
}

/** CVDV/KTV không được ghi đè issuedQty — giữ số lượt xuất kho đã ghi trên RO. */
export function mergePartsPreserveIssuedQty(oldRaw, newRaw) {
  const oldArr = normalizePartsArray(oldRaw);
  const newArr = normalizePartsArray(newRaw);
  const issuedByCode = {};
  for (const p of oldArr) {
    const code = String(p?.code || '')
      .trim()
      .toLowerCase();
    if (!code) continue;
    const issued = Number(p?.issuedQty ?? p?.issued_qty ?? 0);
    issuedByCode[code] = Number.isFinite(issued) ? issued : 0;
  }
  return newArr.map((p) => {
    const code = String(p?.code || '')
      .trim()
      .toLowerCase();
    if (!code || !(code in issuedByCode)) return p;
    const v = issuedByCode[code];
    return { ...p, issuedQty: v, issued_qty: v };
  });
}

export function allQuotedPartsFullyIssued(partsArr) {

  let anyPositive = false;

  for (const p of partsArr) {

    const qty = Number(p?.qty ?? p?.hours ?? 0);

    if (!Number.isFinite(qty) || qty <= 0) continue;

    anyPositive = true;

    const issued = Number(p?.issuedQty ?? p?.issued_qty ?? 0);

    if (!Number.isFinite(issued) || issued < qty) return false;

  }

  return anyPositive;

}



/** Xe còn trong xưởng (chưa ra cổng / chưa kết thúc hồ sơ) — CVDV cần biết khi đủ PT. */

export function isVehicleInWorkshop(status) {

  const s = String(status || '');

  const leftOrClosed = new Set([

    'DA_RA_CONG',

    'DA_RA_CONG_THIEU_PT',

    'XE_RA_XUONG',

    'DA_THANH_TOAN',

    'HUY',

    'KT_DUYET_RA_CONG',

  ]);

  return !leftOrClosed.has(s);

}



/**

 * Tạo thông báo CVDV / tin nhắn KH khi đủ PT. Gọi sau PATCH parts hoặc từ API Kho.

 * @returns {Promise<{ok:boolean, complete:boolean, notified:string|null, reason?:string, status?:string}>}

 */

export async function tryNotifyPartsArrivalComplete(pool, row) {

  const id = row.id;

  const partsArr = normalizePartsArray(row.parts);

  if (!allQuotedPartsFullyIssued(partsArr)) {

    return { ok: true, complete: false, notified: null };

  }



  const st = String(row.status || '');

  const bien = String(row.bien_so || '').trim();

  const roCode = String(row.ro_code || '').trim();



  if (st === 'DA_RA_CONG_THIEU_PT') {

    let logs = [];

    const rawLogs = row.chat_logs;

    if (rawLogs == null) logs = [];

    else if (Array.isArray(rawLogs)) logs = [...rawLogs];

    else if (typeof rawLogs === 'string') {

      try {

        const p = JSON.parse(rawLogs);

        logs = Array.isArray(p) ? [...p] : [];

      } catch {

        logs = [];

      }

    }

    const autoMsg =

      '✅ Xưởng: Phụ tùng cho xe đã về đủ theo báo giá. Quý khách vui lòng liên hệ xưởng để hẹn lấy xe / lắp ráp.';

    const last = logs.length > 0 ? logs[logs.length - 1] : null;

    const chatAlreadyDone =

      last &&

      String(last.msg || '').includes('Phụ tùng cho xe đã về đủ theo báo giá') &&

      String(last.role || '') === 'Xưởng';



    if (!chatAlreadyDone) {

      logs.push({

        sender: 'Hệ thống',

        role: 'Xưởng',

        msg: autoMsg,

        time: new Date().toISOString(),

      });

      await pool.query(`UPDATE repair_orders SET chat_logs = $1::jsonb, updated_at = NOW() WHERE id = $2`, [

        JSON.stringify(logs),

        id,

      ]);

    }



    const linkedCustomer = String(row.linked_customer || '').trim();

    const customerPhone = String(row.customer_phone || '').trim();

    const digitsOnly = (s) => String(s || '').replace(/\D/g, '');



    const khDigits = digitsOnly(linkedCustomer) || digitsOnly(customerPhone);

    if (khDigits) {

      const khDup = await pool.query(

        `SELECT id FROM notifications

         WHERE user_id IN (

           SELECT id FROM users

           WHERE regexp_replace(username, '[^0-9]', '', 'g') = $1

           LIMIT 1

         )

           AND (data->>'type') = 'PARTS_READY_FOR_CUSTOMER'

           AND (data->>'repair_order_id') = $2

           AND created_at > NOW() - INTERVAL '24 hours'

         LIMIT 1`,

        [khDigits, id],

      );



      if (khDup.rowCount === 0) {

        const khUser = await pool.query(

          `SELECT id FROM users

           WHERE regexp_replace(username, '[^0-9]', '', 'g') = $1

           LIMIT 1`,

          [khDigits],

        );



        if (khUser.rowCount > 0) {

          const khId = khUser.rows[0].id;

          const title = `Đủ phụ tùng — ${bien || roCode || id}`;

          const body = `RO ${roCode}: Kho đã đủ phát/xuất phụ tùng theo báo giá. Quý khách vui lòng liên hệ CSKH/xưởng để hẹn lắp ráp / lấy xe.`;



          await pool.query(

            `INSERT INTO notifications (user_id, title, body, data) VALUES ($1, $2, $3, $4::jsonb)`,

            [

              khId,

              title,

              body,

              JSON.stringify({

                type: 'PARTS_READY_FOR_CUSTOMER',

                repair_order_id: id,

                bien_so: bien,

                ro_code: roCode,

              }),

            ],

          );

        }

      }

    }



    return {

      ok: true,

      complete: true,

      notified: chatAlreadyDone ? 'customer_chat_skipped_duplicate' : 'customer_chat_and_notify',

      bien_so: bien,

    };

  }



  if (isVehicleInWorkshop(st) && row.cvdv_username && String(row.cvdv_username).trim()) {

    const cvdv = String(row.cvdv_username).trim();

    const cres = await pool.query(`SELECT id FROM users WHERE username = $1 LIMIT 1`, [cvdv]);

    if (cres.rowCount === 0) {

      return { ok: true, complete: true, notified: 'none', reason: 'cvdv_user_not_found' };

    }

    const cvdvId = cres.rows[0].id;

    const dup = await pool.query(

      `SELECT id FROM notifications

       WHERE user_id = $1

         AND (data->>'type') = 'PARTS_READY_IN_SHOP'

         AND (data->>'repair_order_id') = $2

         AND created_at > NOW() - INTERVAL '24 hours'

       LIMIT 1`,

      [cvdvId, id],

    );

    if (dup.rowCount > 0) {

      return { ok: true, complete: true, notified: 'cvdv_skipped_duplicate' };

    }

    const title = `Đủ phụ tùng — ${bien || roCode || id}`;

    const body = `RO ${roCode}: Kho đã đủ phát/xuất phụ tùng theo báo giá. Kiểm tra & liên hệ khách / KTV.`;

    await pool.query(

      `INSERT INTO notifications (user_id, title, body, data) VALUES ($1, $2, $3, $4::jsonb)`,

      [

        cvdvId,

        title,

        body,

        JSON.stringify({

          type: 'PARTS_READY_IN_SHOP',

          repair_order_id: id,

          bien_so: bien,

          ro_code: roCode,

        }),

      ],

    );

    return { ok: true, complete: true, notified: 'cvdv', cvdv_username: cvdv };

  }



  return { ok: true, complete: true, notified: 'none', status: st };

}


