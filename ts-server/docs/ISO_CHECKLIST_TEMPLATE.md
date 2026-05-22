# Checklist ISO nội bộ - TS-XDV (mẫu)

## 1) Kiểm soát truy cập & phân quyền
- [ ] Có phân quyền theo vai trò (RBAC) và workshop isolation
- [ ] Tài khoản có trạng thái (active/locked), ghi log thao tác tạo/sửa/khoá
- [ ] Mật khẩu/token không lộ trong log (mask)

## 2) Kiểm soát quy trình nghiệp vụ
- [ ] RO có state machine, chặn nhảy trạng thái sai
- [ ] Quyết toán/thu tiền chỉ Kế toán thực hiện (hoặc role được phép)
- [ ] Phụ tùng xuất/nhập có chứng từ và audit

## 3) Trace & Audit
- [ ] Mọi request có x-trace-id
- [ ] Audit logs append-only + hash chain verify OK
- [ ] Đóng sổ daily seal và lưu đối chiếu

## 4) Sự cố & khiếu nại
- [ ] Ticket complaint có playbook + SLA + escalation
- [ ] Có báo cáo % đúng SLA, case quá hạn

## 5) Sao lưu & khôi phục
- [ ] Backup DB định kỳ
- [ ] Quy trình restore test định kỳ
