import { Permissions, Role, rolePermissions } from '../src/auth/permissions.js';

function main() {
  const permValues = new Set(Object.values(Permissions));
  const unknown = [];
  for (const [role, arr] of Object.entries(rolePermissions || {})) {
    for (const p of (arr || [])) {
      if (!permValues.has(p)) unknown.push({ role, permission: p });
    }
  }
  const counts = Object.keys(Role).map(k => {
    const r = Role[k];
    return { role: r, count: (rolePermissions?.[r] || []).length };
  });
  console.log(JSON.stringify({ roles: counts, unknownRefs: unknown, permissionsCount: permValues.size }, null, 2));
  if (unknown.length) process.exit(2);
}
main();
