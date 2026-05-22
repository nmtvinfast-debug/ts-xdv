// work_orders_api.js
export function registerWorkOrdersApi(app, supabase, authMiddleware) {
  const mw = authMiddleware || ((_req, _res, next) => next());
  // 1) LIST: /api/work-orders?limit=50&status=cho_sua_chua&q=... (q tìm theo biển số / order_code / sdt / tên KH)
  app.get("/api/work-orders", mw, async (req, res) => {
    try {
      const limit = Math.min(Number(req.query.limit || 50), 200);
      const status = String(req.query.status || "").trim();
      const q = String(req.query.q || "").trim();

      let query = supabase
        .from("work_orders")
        .select("id, order_code, bien_so, ten_kh, sdt_kh, trang_thai, created_at, cvdv_name")
        .order("created_at", { ascending: false })
        .limit(limit);

      if (status) query = query.eq("trang_thai", status);

      if (q) {
        // OR search
        query = query.or(
          `order_code.ilike.%${q}%,bien_so.ilike.%${q}%,ten_kh.ilike.%${q}%,sdt_kh.ilike.%${q}%`
        );
      }

      const { data, error } = await query;
      if (error) return res.status(500).json({ ok: false, message: error.message });

      return res.json({ ok: true, items: data || [] });
    } catch (e) {
      return res.status(500).json({ ok: false, message: e.message });
    }
  });

  // 2) DETAIL: /api/work-orders/:id
  app.get("/api/work-orders/:id", mw, async (req, res) => {
    try {
      const id = req.params.id;

      const woRes = await supabase.from("work_orders").select("*").eq("id", id).maybeSingle();
      if (woRes.error) return res.status(500).json({ ok: false, message: woRes.error.message });
      if (!woRes.data) return res.status(404).json({ ok: false, message: "Không tìm thấy work_order" });

      const jobsRes = await supabase
        .from("work_order_jobs")
        .select("*")
        .eq("work_order_id", id)
        .order("created_at", { ascending: true });

      if (jobsRes.error) return res.status(500).json({ ok: false, message: jobsRes.error.message });

      const partsRes = await supabase
        .from("work_order_parts")
        .select("*")
        .eq("work_order_id", id)
        .order("created_at", { ascending: true });

      if (partsRes.error) return res.status(500).json({ ok: false, message: partsRes.error.message });

      return res.json({
        ok: true,
        wo: woRes.data,
        jobs: jobsRes.data || [],
        parts: partsRes.data || [],
      });
    } catch (e) {
      return res.status(500).json({ ok: false, message: e.message });
    }
  });

  // 3) Update trạng thái: PATCH /api/work-orders/:id/status  {trang_thai:"dang_sua"}
  app.patch("/api/work-orders/:id/status", mw, async (req, res) => {
    try {
      const id = req.params.id;
      const trang_thai = String(req.body.trang_thai || "").trim();
      if (!trang_thai) return res.status(400).json({ ok: false, message: "Thiếu trang_thai" });

      const { error } = await supabase
        .from("work_orders")
        .update({ trang_thai })
        .eq("id", id);

      if (error) return res.status(500).json({ ok: false, message: error.message });
      return res.json({ ok: true });
    } catch (e) {
      return res.status(500).json({ ok: false, message: e.message });
    }
  });

  // 4) Gán CVDV: PATCH /api/work-orders/:id/assign  {cvdv_name:"Nguyễn A"}
  app.patch("/api/work-orders/:id/assign", mw, async (req, res) => {
    try {
      const id = req.params.id;
      const cvdv_name = String(req.body.cvdv_name || "").trim();
      if (!cvdv_name) return res.status(400).json({ ok: false, message: "Thiếu cvdv_name" });

      const { error } = await supabase.from("work_orders").update({ cvdv_name }).eq("id", id);
      if (error) return res.status(500).json({ ok: false, message: error.message });

      return res.json({ ok: true });
    } catch (e) {
      return res.status(500).json({ ok: false, message: e.message });
    }
  });
}
