# Phase 9O - AI Anomaly Detection (Rule-based)

## API
- POST /api/v1/anomaly/scan
- GET /api/v1/anomaly/list

## Rules
1) high_frequency: >=20 actions trong 5 phút
2) off_hours: hành động 22h-5h
3) financial_spike: >=10 settlement trong 10 phút

Có thể mở rộng ML sau này.
