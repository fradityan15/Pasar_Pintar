import { supabase } from '@/lib/supabase'

export async function listSellerOrders(umkmId) {
  const { data, error } = await supabase.rpc('seller_list_orders', { p_umkm_id: umkmId })
  if (error) throw new Error(error.message)
  return data ?? []
}

export async function shipSellerOrder(orderId, umkmId) {
  const { error } = await supabase.rpc('seller_ship_order', {
    p_order_id: orderId,
    p_umkm_id: umkmId,
  })
  if (error) throw new Error(error.message)
}

export async function processSellerOrder(orderId, umkmId) {
  const { error } = await supabase.rpc('seller_process_order', {
    p_order_id: orderId,
    p_umkm_id: umkmId,
  })
  if (error) throw new Error(error.message)
}
