import { supabase } from '@/lib/supabase'

const PRODUCT_FIELDS =
  'id, name, slug, price, stock, umkm(name, regions(name)), product_images(url, sort_order)'

function check({ data, error, count }) {
  if (error) throw new Error(error.message)
  return { data, count }
}

export async function listCategories() {
  const res = await supabase
    .from('categories')
    .select('id, parent_id, name, slug')
    .eq('is_active', true)
    .order('name')
  return check(res).data
}

/** Daftar produk aktif dengan pencarian, filter kategori (termasuk subkategori), dan halaman. */
export async function listProducts({ q = '', categoryIds = null, page = 1, pageSize = 12 } = {}) {
  let query = supabase
    .from('products')
    .select(PRODUCT_FIELDS, { count: 'exact' })
    .eq('is_active', true)
    .order('created_at', { ascending: false })
    .range((page - 1) * pageSize, page * pageSize - 1)

  const term = q.trim().replace(/[%,()]/g, ' ')
  if (term) query = query.ilike('name', `%${term}%`)
  if (categoryIds?.length) query = query.in('category_id', categoryIds)

  const { data, count } = check(await query)
  return { items: data, total: count ?? 0 }
}

export async function listFeatured(limit = 8) {
  const res = await supabase
    .from('products')
    .select(PRODUCT_FIELDS)
    .eq('is_active', true)
    .order('created_at', { ascending: false })
    .limit(limit)
  return check(res).data
}

export async function getProductBySlug(slug) {
  const { data, error } = await supabase
    .from('products')
    .select('id, name, slug, description, price, stock, weight_gram, umkm(name, slug, logo_url, description, is_verified, regions(name, province)), categories(name), product_images(url, sort_order)')
    .eq('slug', slug)
    .eq('is_active', true)
    .maybeSingle()
  if (error) throw new Error(error.message)
  return data
}
