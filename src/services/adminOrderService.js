import { supabase } from '@/lib/supabase'

const take = ({ data, error, count }) => {
  if (error) throw new Error(error.message)
  return { data, count }
}
const rpc = async (fn, args) => {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw new Error(error.message)
  return data
}

export async function listOrders({ status = '', q = '', umkmId = '', month = '', page = 1, pageSize = 15 } = {}) {
  const orderItemsRelation = umkmId ? 'order_items!inner(umkm_id, umkm(name))' : 'order_items(umkm_id, umkm(name))'
  let query = supabase
    .from('orders')
    .select(`id, order_no, status, payment_method, total, created_at, profiles(full_name), payment_methods(name), ${orderItemsRelation}`, { count: 'exact' })
    .order('created_at', { ascending: false })
    .range((page - 1) * pageSize, page * pageSize - 1)
  if (status) query = query.eq('status', status)
  if (umkmId) query = query.eq('order_items.umkm_id', umkmId)
  if (month && month !== 'all') {
    const [year, monthNumber] = month.split('-').map(Number)
    const start = new Date(Date.UTC(year, monthNumber - 1, 1))
    const end = new Date(Date.UTC(year, monthNumber, 1))
    const startMonth = `${start.getUTCFullYear()}-${String(start.getUTCMonth() + 1).padStart(2, '0')}`
    const endMonth = `${end.getUTCFullYear()}-${String(end.getUTCMonth() + 1).padStart(2, '0')}`
    query = query
      .gte('created_at', `${startMonth}-01T00:00:00+07:00`)
      .lt('created_at', `${endMonth}-01T00:00:00+07:00`)
  }
  const term = q.trim().replace(/[%,()]/g, ' ')
  if (term) query = query.ilike('order_no', `%${term}%`)
  const { data, count } = take(await query)
  return { items: data, total: count ?? 0 }
}

export async function getOrderAdmin(id) {
  return take(
    await supabase
      .from('orders')
      .select('*, payment_methods(name, category, account_number, account_name, qr_image_url), profiles(full_name, phone), order_items(id, product_name, unit_price, quantity)')
      .eq('id', id)
      .maybeSingle(),
  ).data
}

export const confirmOrderPaymentAdmin = (id, note = null) =>
  rpc('admin_confirm_order_payment', { p_order_id: id, p_note: note })
