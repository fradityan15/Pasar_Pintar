import { supabase } from '@/lib/supabase'

function unwrap({ data, error }) {
  if (error) throw new Error(error.message)
  return data
}

export const listAddresses = async () =>
  unwrap(await supabase.from('addresses').select('*').order('is_default', { ascending: false }).order('created_at'))

export const listActivePaymentMethods = async () =>
  unwrap(
    await supabase
      .from('payment_methods')
      .select('id, name, category, account_number, account_name, qr_image_url')
      .eq('is_active', true)
      .order('name'),
  )

export async function saveAddress(userId, a, makeDefault) {
  return unwrap(
    await supabase
      .from('addresses')
      .insert({ ...a, user_id: userId, is_default: makeDefault })
      .select()
      .single(),
  )
}

// Checkout atomik di database: cek stok, buat pesanan, kurangi stok, kosongkan keranjang.
export async function createOrder(addressId, paymentMethodId, productIds = null, shippingMethod = 'regular') {
  return unwrap(await supabase.rpc('create_order', {
    p_address_id: addressId,
    p_payment_method_id: paymentMethodId,
    p_product_ids: productIds,
    p_shipping_method: shippingMethod,
  }))
}

export async function cancelOrder(orderId, reason = null) {
  unwrap(await supabase.rpc('cancel_order', { p_order_id: orderId, p_reason: reason }))
}

export async function confirmOrderReceived(orderId) {
  unwrap(await supabase.rpc('confirm_order_received', { p_order_id: orderId }))
}

export async function listMyOrders(userId) {
  return unwrap(
    await supabase
      .from('orders')
      .select('id, order_no, status, total, created_at, order_items(product_name, quantity)')
      .eq('user_id', userId)
      .order('created_at', { ascending: false }),
  )
}

export async function getOrder(id, userId) {
  return unwrap(
    await supabase
      .from('orders')
      .select('*, payment_methods(name, category, account_number, account_name, qr_image_url), order_items(id, product_id, product_name, unit_price, quantity, products(product_images(url, sort_order)))')
      .eq('id', id)
      .eq('user_id', userId)
      .maybeSingle(),
  )
}
