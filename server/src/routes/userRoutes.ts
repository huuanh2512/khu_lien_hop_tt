// @ts-nocheck
import { Router } from 'express';
import { authMiddleware } from '../middlewares/authMiddleware';
import { requireVerifiedCustomer } from '../middlewares/requireVerifiedCustomer';

const router = Router();

router.get(
  '/customer/bookings',
  authMiddleware,
  requireVerifiedCustomer,
  async (req, res) => {
    // TODO: replace with actual booking query
    res.json({ message: 'Customer bookings list' });
  },
);

router.get('/admin/dashboard', authMiddleware, async (req, res) => {
  const user = req.appUser;
  if (!user || user.role !== 'admin') {
    return res.status(403).json({ message: 'Forbidden' });
  }

  // TODO: replace with actual admin dashboard data source
  return res.json({ message: 'Admin dashboard data' });
});

export default router;
