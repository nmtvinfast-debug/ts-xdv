import express from 'express';
import multer from 'multer';

function parseBearerUserId(req) {
  const raw = req.headers.authorization || '';
  const m = /^Bearer\s+auth_token_([0-9a-f-]{36})$/i.exec(String(raw).trim());
  return m ? m[1] : null;
}

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 12 * 1024 * 1024 },
});

/**
 * OCR ảnh phiếu xuất / yêu cầu phụ tùng — client (Kho) gửi multipart field "image".
 */
export function createOcrRouter() {
  const r = express.Router();

  r.post('/stock-slip', upload.single('image'), async (req, res) => {
    const uid = parseBearerUserId(req);
    if (!uid) return res.status(401).json({ error: 'Chưa đăng nhập' });
    if (!req.file?.buffer?.length) {
      return res.status(400).json({ error: 'Thiếu file ảnh (field: image)' });
    }
    try {
      const { createWorker } = await import('tesseract.js');
      const worker = await createWorker(['vie', 'eng']);
      const {
        data: { text },
      } = await worker.recognize(req.file.buffer);
      await worker.terminate();
      res.json({ text: String(text || '').trim() });
    } catch (err) {
      res.status(500).json({ error: err?.message || String(err) });
    }
  });

  return r;
}
