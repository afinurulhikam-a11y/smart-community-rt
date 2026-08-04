const express = require('express');
const router = express.Router();
const {
  getUsers,
  updateUserRole,
  updateUserStatus,
  createUser,
  getPendingUsers,
  deleteUser,
  getUserByNik,
  updateUserCredentials,
} = require('../controllers/user.controller');
const { authMiddleware, roleGuard, requirePermission } = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.get('/', getUsers);
router.get('/by-nik/:nik', getUserByNik);
router.put('/credentials', updateUserCredentials);
router.get('/pending', getPendingUsers);
router.post('/', roleGuard('admin'), createUser);
router.put('/:id/role', roleGuard('admin'), updateUserRole);
router.put('/:id/status', roleGuard('admin'), updateUserStatus);
router.delete('/:id', deleteUser);

module.exports = router;
