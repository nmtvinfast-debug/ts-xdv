-- TS XDV (V4) - Schema tối thiểu chạy được (work_orders + quy trình + kho)
-- Chạy trong Supabase SQL Editor với Role: postgres

create extension if not exists "pgcrypto";

-- 1) workshops
create table if not exists public.workshops (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

-- 2) users (tài khoản nội bộ)
create table if not exists public.users (
  id uuid primary key default gen_random_uuid(),
  workshop_id uuid references public.workshops(id) on delete cascade,
  full_name text not null,
  username text not null,
  role text not null, -- quan_doc, bao_ve, cvdv, ktv, kho, ke_toan, ra_cong, admin
  phone text,
  password_hash text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists ux_users_username on public.users(username);

create index if not exists idx_users_workshop_id on public.users(workshop_id);

-- 3) work_orders (lệnh / báo giá / quy trình)
create table if not exists public.work_orders (
  id uuid primary key default gen_random_uuid(),
  workshop_id uuid references public.workshops(id) on delete cascade,
  order_code text not null,
  source text default 'manual',
  loai text not null default 'lenh_sua_chua', -- bao_gia | lenh_sua_chua
  bien_so text,
  ten_kh text,
  sdt_kh text,
  kieu_xe text,
  so_khung text,
  so_km text,
  yeu_cau_kh text,
  cvdv_user_id uuid references public.users(id),
  trang_thai text not null default 'cho_tiep_nhan',
  tong_tien_nhan_cong numeric not null default 0,
  tong_tien_phu_tung numeric not null default 0,
  tong_tien numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists ux_work_orders_order_code on public.work_orders(order_code);
create index if not exists idx_work_orders_status on public.work_orders(trang_thai);
create index if not exists idx_work_orders_ws on public.work_orders(workshop_id);

-- 4) jobs / parts lines
create table if not exists public.work_order_jobs (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid references public.work_orders(id) on delete cascade,
  ma_cv text,
  ten_cv text,
  gio_cong numeric,
  don_gia numeric,
  thanh_tien numeric,
  ghi_chu text,
  status text not null default 'active',
  created_at timestamptz not null default now()
);

create table if not exists public.work_order_parts (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid references public.work_orders(id) on delete cascade,
  ma_pt text,
  ten_pt text,
  so_luong numeric not null default 1,
  don_vi text,
  don_gia numeric,
  thanh_tien numeric,
  ghi_chu text,
  status text not null default 'active',
  created_at timestamptz not null default now()
);

create index if not exists idx_jobs_wo on public.work_order_jobs(work_order_id);
create index if not exists idx_parts_wo on public.work_order_parts(work_order_id);

-- 5) work_order_events (lịch sử quy trình / audit)
create table if not exists public.work_order_events (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid references public.work_orders(id) on delete cascade,
  actor_user_id uuid references public.users(id),
  from_status text,
  to_status text,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists idx_events_wo on public.work_order_events(work_order_id);

-- 6) inventory (kho)
create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  workshop_id uuid references public.workshops(id) on delete cascade,
  part_code text not null,
  part_name text,
  unit text,
  created_at timestamptz not null default now()
);

create unique index if not exists ux_inventory_items_code on public.inventory_items(part_code);

create table if not exists public.inventory_lots (
  id uuid primary key default gen_random_uuid(),
  workshop_id uuid references public.workshops(id) on delete cascade,
  item_id uuid references public.inventory_items(id) on delete cascade,
  cost numeric not null default 0, -- giá nhập tại thời điểm nhập
  qty_on_hand numeric not null default 0,
  location text default '',
  created_at timestamptz not null default now()
);

create index if not exists idx_lots_item on public.inventory_lots(item_id);

create table if not exists public.inventory_moves (
  id uuid primary key default gen_random_uuid(),
  workshop_id uuid references public.workshops(id) on delete cascade,
  item_id uuid references public.inventory_items(id),
  lot_id uuid references public.inventory_lots(id),
  work_order_id uuid references public.work_orders(id),
  move_type text not null, -- receive | issue | adjust
  qty numeric not null default 0,
  cost numeric not null default 0,
  location text default '',
  note text,
  requested_by_user_id uuid references public.users(id),
  created_by_user_id uuid references public.users(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_moves_wo on public.inventory_moves(work_order_id);
create index if not exists idx_moves_item on public.inventory_moves(item_id);

-- 7) seed workshop + users nếu chưa có
do $$
declare wid uuid;
begin
  if not exists (select 1 from public.workshops) then
    insert into public.workshops(name) values ('Xưởng mặc định') returning id into wid;

    insert into public.users(workshop_id, full_name, username, role, phone, password_hash) values
      (wid, 'Quản đốc 01', 'quandoc', 'quan_doc', '000', ''),
      (wid, 'Bảo vệ 01', 'baove', 'bao_ve', '000', ''),
      (wid, 'CVDV 01', 'cvdv', 'cvdv', '000', ''),
      (wid, 'KTV 01', 'ktv', 'ktv', '000', ''),
      (wid, 'Kho 01', 'kho', 'kho', '000', ''),
      (wid, 'Kế toán 01', 'ketoan', 'ke_toan', '000', ''),
      (wid, 'Ra cổng 01', 'racong', 'ra_cong', '000', '');
  end if;
end $$;

