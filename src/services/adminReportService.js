import { supabase } from '@/lib/supabase'
import { addDays } from '@/lib/csv'

export async function salesReport(from, to) {
  const { data, error } = await supabase.rpc('sales_report', { p_from: from, p_to: to })
  if (error) throw new Error(error.message)
  return data
}

// Produk terlaris dari pesanan berbayar (dihitung di browser, maksimal 2000 baris item).
export async function topProducts(from, to, limit = 5) {
  const { data, error } = await supabase
    .from('order_items')
    .select('product_name, quantity, unit_price, orders!inner(status, payment_status, created_at)')
    .eq('orders.payment_status', 'dibayar')
    .neq('orders.status', 'dibatalkan')
    .gte('orders.created_at', `${from}T00:00:00+07:00`)
    .lt('orders.created_at', `${addDays(to, 1)}T00:00:00+07:00`)
    .limit(2000)
  if (error) throw new Error(error.message)

  const map = new Map()
  for (const r of data) {
    const cur = map.get(r.product_name) ?? { name: r.product_name, qty: 0, revenue: 0 }
    cur.qty += r.quantity
    cur.revenue += r.quantity * Number(r.unit_price)
    map.set(r.product_name, cur)
  }
  return [...map.values()].sort((a, b) => b.qty - a.qty).slice(0, limit)
}
