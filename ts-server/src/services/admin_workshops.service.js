const bcrypt = require('bcryptjs');

function normalizeCode(name = '') {
  return name
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-zA-Z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .toUpperCase() || 'XDV';
}

async function listWorkshops(db, q = '') {
  const keyword = `%${q || ''}%`;
  const sql = `
    SELECT
      w.id,
      w.name,
      w.code,
      w.address,
      w.backend_url,
      w.contact_phone,
      w.contact_zalo,
      w.contact_email,
      w.director_user_id,
      w.is_active,
      w.created_at,
      w.updated_at,
      u.username AS director_username,
      u.full_name AS director_full_name
    FROM workshops w
    LEFT JOIN users u ON u.id = w.director_user_id
    WHERE ($1 = '%%'
      OR w.name ILIKE $1
      OR COALESCE(w.code,'') ILIKE $1
      OR COALESCE(w.address,'') ILIKE $1)
    ORDER BY w.created_at DESC
  `;
  const { rows } = await db.query(sql, [keyword]);
  return rows;
}

async function createWorkshopWithDirector(db, body) {
  const client = await db.connect();
  try {
    await client.query('BEGIN');

    const name = (body.name || '').trim();
    if (!name) throw new Error('Thiếu tên XDV.');

    const code = (body.code || '').trim() || normalizeCode(name);
    const address = body.address || null;
    const backendUrl = body.backend_url || null;
    const contactPhone = body.contact_phone || null;
    const contactZalo = body.contact_zalo || null;
    const contactEmail = body.contact_email || null;

    const directorUsername = (body.director_username || '').trim();
    const directorPassword = body.director_password || '';
    const directorFullName = (body.director_full_name || 'Giám đốc XDV').trim();

    const workshopRes = await client.query(
      `
      INSERT INTO workshops(name, code, address, backend_url, contact_phone, contact_zalo, contact_email)
      VALUES ($1,$2,$3,$4,$5,$6,$7)
      RETURNING *
      `,
      [name, code, address, backendUrl, contactPhone, contactZalo, contactEmail]
    );
    const workshop = workshopRes.rows[0];

    const branchRes = await client.query(
      `
      INSERT INTO branches(workshop_id, code, name, is_default)
      VALUES ($1, 'MAIN', 'Chi nhánh chính', TRUE)
      RETURNING *
      `,
      [workshop.id]
    );
    const branch = branchRes.rows[0];

    let director = null;
    if (directorUsername && directorPassword) {
      const exists = await client.query(
        `SELECT id FROM users WHERE username = $1 LIMIT 1`,
        [directorUsername]
      );
      if (exists.rowCount > 0) {
        throw new Error('Username Giám đốc đã tồn tại.');
      }

      const passwordHash = await bcrypt.hash(directorPassword, 10);
      const userRes = await client.query(
        `
        INSERT INTO users(username, password_hash, full_name, role, workshop_id, branch_id, is_active)
        VALUES ($1,$2,$3,$4,$5,$6,TRUE)
        RETURNING id, username, full_name, role, workshop_id, branch_id, is_active
        `,
        [directorUsername, passwordHash, directorFullName, 'director', workshop.id, branch.id]
      );
      director = userRes.rows[0];

      await client.query(
        `UPDATE workshops SET director_user_id = $1, updated_at = NOW() WHERE id = $2`,
        [director.id, workshop.id]
      );
    }

    await client.query('COMMIT');
    return { workshop: { ...workshop, director_user_id: director?.id || null }, branch, director };
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

async function updateWorkshop(db, workshopId, body) {
  const sql = `
    UPDATE workshops
    SET
      name = COALESCE($2, name),
      code = COALESCE($3, code),
      address = COALESCE($4, address),
      backend_url = COALESCE($5, backend_url),
      contact_phone = COALESCE($6, contact_phone),
      contact_zalo = COALESCE($7, contact_zalo),
      contact_email = COALESCE($8, contact_email),
      is_active = COALESCE($9, is_active),
      updated_at = NOW()
    WHERE id = $1
    RETURNING *
  `;
  const values = [
    workshopId,
    body.name ?? null,
    body.code ?? null,
    body.address ?? null,
    body.backend_url ?? null,
    body.contact_phone ?? null,
    body.contact_zalo ?? null,
    body.contact_email ?? null,
    typeof body.is_active === 'boolean' ? body.is_active : null,
  ];
  const { rows, rowCount } = await db.query(sql, values);
  if (!rowCount) throw new Error('Không tìm thấy workshop.');
  return rows[0];
}

async function resetDirectorPassword(db, workshopId, newPassword) {
  if (!newPassword || newPassword.length < 4) {
    throw new Error('Mật khẩu mới không hợp lệ.');
  }
  const workshopRes = await db.query(
    `SELECT director_user_id FROM workshops WHERE id = $1 LIMIT 1`,
    [workshopId]
  );
  if (!workshopRes.rowCount || !workshopRes.rows[0].director_user_id) {
    throw new Error('Workshop chưa có Giám đốc.');
  }
  const passwordHash = await bcrypt.hash(newPassword, 10);
  await db.query(
    `UPDATE users SET password_hash = $1 WHERE id = $2`,
    [passwordHash, workshopRes.rows[0].director_user_id]
  );
  return { ok: true };
}

module.exports = {
  listWorkshops,
  createWorkshopWithDirector,
  updateWorkshop,
  resetDirectorPassword,
};
