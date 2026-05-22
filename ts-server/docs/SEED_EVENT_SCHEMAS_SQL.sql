INSERT INTO event_schemas(event_code, schema_json, example_payload, description)
VALUES
('JOB_ASSIGNED_TO_TECH',
 '{
   "type":"object",
   "required":["ro","vehicle"],
   "properties":{
     "ro":{"type":"object","required":["code"],"properties":{"code":{"type":"string"}}},
     "vehicle":{"type":"object","required":["plate"],"properties":{"plate":{"type":"string"}}},
     "meta":{"type":"object"}
   }
 }'::jsonb,
 '{"ro":{"code":"RO-0001"},"vehicle":{"plate":"20A-12345"},"meta":{"assignedByName":"Quản đốc"}}'::jsonb,
 'KTV được giao việc'
)
ON CONFLICT (event_code) DO NOTHING;
