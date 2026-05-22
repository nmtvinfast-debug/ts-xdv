-- TS V3 migration (Supabase Postgres)
create extension if not exists pgcrypto;

create table if not exists workshops (
  id uuid primary key,
  name text not null,
  address text,
  created_at timestamptz default now()
);

create table if not exists users (
  id uuid primary key,
  workshop_id uuid references workshops(id) on delete cascade,
  full_name text not null,
  username text unique,
  role text not null,
  phone text,
  is_active boolean default true,
  created_at timestamptz default now()
);
create index if not exists idx_users_workshop on users(workshop_id);

create table if not exists appointments (
  id uuid primary key,
  workshop_id uuid references workshops(id) on delete cascade,
  bien_so text not null,
  ten_kh text,
  sdt_kh text,
  ngay_hen date not null,
  gio_hen text,
  ghi_chu text,
  assigned_cvdv_id uuid references users(id),
  status text default 'active',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_appt_workshop_date on appointments(workshop_id, ngay_hen);
create index if not exists idx_appt_bienso on appointments(bien_so);

create table if not exists work_orders (
  id uuid primary key,
  workshop_id uuid references workshops(id) on delete cascade,
  order_code text not null,
  source text,
  bien_so text,
  ten_kh text,
  sdt_kh text,
  kieu_xe text,
  so_khung text,
  so_km text,
  yeu_cau_kh text,
  cvdv_id uuid references users(id),
  trang_thai text not null default 'cho_sua_chua',
  stop_reason text,
  tong_tien_nhan_cong numeric default 0,
  tong_tien_phu_tung numeric default 0,
  tong_tien numeric default 0,
  checkin_at timestamptz,
  checkout_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create unique index if not exists uq_work_orders_workshop_ordercode on work_orders(workshop_id, order_code);
create index if not exists idx_work_orders_status on work_orders(workshop_id, trang_thai);
create index if not exists idx_work_orders_bienso on work_orders(workshop_id, bien_so);

create table if not exists work_order_jobs (
  id uuid primary key,
  work_order_id uuid references work_orders(id) on delete cascade,
  ma_cv text,
  ten_cv text,
  don_gia numeric default 0,
  thanh_tien numeric default 0,
  ghi_chu text,
  status text default 'active',
  created_at timestamptz default now()
);
create index if not exists idx_jobs_wo on work_order_jobs(work_order_id);

create table if not exists work_order_parts (
  id uuid primary key,
  work_order_id uuid references work_orders(id) on delete cascade,
  ma_pt text,
  ten_pt text,
  so_luong numeric default 1,
  don_vi text,
  don_gia numeric default 0,
  thanh_tien numeric default 0,
  ghi_chu text,
  status text default 'active',
  is_missing boolean default false,
  is_locked boolean default false,
  created_at timestamptz default now()
);
create index if not exists idx_parts_wo on work_order_parts(work_order_id);

create table if not exists work_order_status_history (
  id uuid primary key,
  work_order_id uuid references work_orders(id) on delete cascade,
  from_status text,
  to_status text,
  note text,
  by_user_id uuid references users(id),
  created_at timestamptz default now()
);
create index if not exists idx_hist_wo on work_order_status_history(work_order_id);

create table if not exists payments (
  id uuid primary key,
  work_order_id uuid references work_orders(id) on delete cascade,
  amount numeric default 0,
  method text,
  paid_at timestamptz default now(),
  by_user_id uuid references users(id)
);

create table if not exists gate_passes (
  id uuid primary key,
  work_order_id uuid references work_orders(id) on delete cascade,
  code text not null,
  created_at timestamptz default now()
);

-- Seed demo
do $$
declare wid uuid;
begin
  if not exists (select 1 from workshops) then
    wid := gen_random_uuid();
    insert into workshops(id, name, address) values (wid, 'XDV Demo', 'Thai Nguyen');
    insert into users(id, workshop_id, full_name, username, role, phone) values
      (gen_random_uuid(), wid, 'Ngo Minh Toan', 'toan', 'owner', '000'),
      (gen_random_uuid(), wid, 'Bao Ve 01', 'baove', 'bao_ve', '000'),
      (gen_random_uuid(), wid, 'CSKH 01', 'cskh', 'cskh', '000'),
      (gen_random_uuid(), wid, 'CVDV 01', 'cvdv', 'cvdv', '000'),
      (gen_random_uuid(), wid, 'Quan Doc 01', 'quandoc', 'quan_doc', '000'),
      (gen_random_uuid(), wid, 'KTV 01', 'ktv', 'ktv', '000'),
      (gen_random_uuid(), wid, 'Kho 01', 'kho', 'kho', '000'),
      (gen_random_uuid(), wid, 'Ke Toan 01', 'ketoan', 'ke_toan', '000');
  end if;
end $$;
