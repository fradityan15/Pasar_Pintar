import { supabase } from '@/lib/supabase'

const FIELDS =
  'id, quantity, product_id, products(id, name, slug, price, stock, is_active, umkm(id, name, slug), product_images(url, sort_order))'

export async function fetchCart() {
  const { data, error } = await supabase.from('cart_items').select(FIELDS).order('id')
  if (error) throw new Error(error.message)
  return data
}

export async function upsertCartItem(userId, productId, quantity) {
  const { error } = await supabase
    .from('cart_items')
    .upsert({ user_id: userId, product_id: productId, quantity }, { onConflict: 'user_id,product_id' })
  if (error) throw new Error(error.message)
}

export async function updateCartQuantity(itemId, quantity) {
  const { error } = await supabase.from('cart_items').update({ quantity }).eq('id', itemId)
  if (error) throw new Error(error.message)
}

export async function deleteCartItem(itemId) {
  const { error } = await supabase.from('cart_items').delete().eq('id', itemId)
  if (error) throw new Error(error.message)
}
