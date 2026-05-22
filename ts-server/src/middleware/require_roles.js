module.exports.requireRoles = (...roles) => {
  return (req, res, next) => {
    const role = (req.user?.role || '').toString().trim().toLowerCase();
    const normalized = role
      .replaceAll(' ', '_')
      .replaceAll('-', '_');

    const accepted = roles.map(r => r.toLowerCase());
    if (!accepted.includes(normalized)) {
      return res.status(403).json({
        ok: false,
        error: 'Bạn không có quyền thực hiện thao tác này.',
      });
    }
    next();
  };
};
