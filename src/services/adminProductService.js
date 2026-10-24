import { supabase } from '@/lib/supabase'

export const LOW_STOCK = 10
const BUCKET = 'product-images'
const MAX_BYTES = 2 * 1024 * 1024
const TYPES = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' }

const take = ({ data, error, count }) => {
  if (error) throw new Error(error.code === '23505' ? 'Slug sudah dipakai produk lain.' : error.message)
  return { data, count }
}

export async function listAdminProducts({ q = '', status = '', page = 1, pageSize = 15 } = {}) {
  let query = supabase
    .from('products')
    .select('id, name, slug, price, stock, is_active, umkm(name), categories(name), product_images(url, sort_order)', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range((page - 1) * pageSize, page * pageSize - 1)
  if (status === 'aktif') query = query.eq('is_active', true)
  if (status === 'nonaktif') query = query.eq('is_active', false)
  if (status === 'menipis') query = query.eq('is_active', true).lte('stock', LOW_STOCK)
  const term = q.trim().replace(/[%,()]/g, ' ')
  if (term) query = query.ilike('name', `%${term}%`)
  const { data, count } = take(await query)
  return { items: data, total: count ?? 0 }
}

export async function getAdminProduct(id) {
  return take(
    await supabase
      .from('products')
      .select('*, umkm(name), categories(name), product_images(id, url, sort_order)')
      .eq('id', id)
      .maybeSingle(),
  ).data
}

export async function saveProduct(id, fields) {
  const q = id
    ? supabase.from('products').update(fields).eq('id', id).select('id').single()
    : supabase.from('products').insert(fields).select('id').single()
  return take(await q).data.id
}

export async function setProductActive(id, active) {
  take(await supabase.from('products').update({ is_active: active }).eq('id', id))
}

export async function adjustStock(id, change, reason) {
  const { error } = await supabase.rpc('admin_adjust_stock', { p_product_id: id, p_change: change, p_reason: reason })
  if (error) throw new Error(error.code === '23514' ? 'Stok tidak boleh kurang dari 0.' : error.message)
}

// ───────── foto produk (Supabase Storage, bucket product-images) ─────────
export async function uploadImage(productId, file) {
  const ext = TYPES[file.type]
  if (!ext) throw new Error('Format foto harus JPG, PNG, atau WebP.')
  if (file.size > MAX_BYTES) throw new Error('Ukuran foto maksimal 2 MB.')

  const path = `${productId}/${crypto.randomUUID()}.${ext}`
  const up = await supabase.storage.from(BUCKET).upload(path, file, { contentType: file.type, cacheControl: '3600' })
  if (up.error) throw new Error(up.error.message)
  const url = supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl

  const last = take(
    await supabase.from('product_images').select('sort_order').eq('product_id', productId).order('sort_order', { ascending: false }).limit(1),
  ).data[0]
  return take(
    await supabase.from('product_images').insert({ product_id: productId, url, sort_order: (last?.sort_order ?? -1) + 1 }).select('id, url, sort_order').single(),
  ).data
}

export async function deleteImage(img) {
  take(await supabase.from('product_images').delete().eq('id', img.id))
  const marker = `/${BUCKET}/`
  const i = img.url.indexOf(marker)
  if (i >= 0) {
    const { error } = await supabase.storage.from(BUCKET).remove([img.url.slice(i + marker.length)])
    if (error) throw new Error(error.message)
  }
}

// Foto utama = sort_order terkecil.
export async function makeMainImage(productId, imageId) {
  const first = take(
    await supabase.from('product_images').select('sort_order').eq('product_id', productId).order('sort_order').limit(1),
  ).data[0]
  take(await supabase.from('product_images').update({ sort_order: (first?.sort_order ?? 0) - 1 }).eq('id', imageId))
}
