import { supabase } from '@/lib/supabase'
import { slugify } from '@/lib/slug'

function take({ data, error }) {
  if (error) {
    if (error.code === '23505') throw new Error('Akun ini sudah memiliki pendaftaran UMKM, atau nama UMKM sudah digunakan.')
    throw new Error(error.message)
  }
  return data
}

export async function getMyUmkm() {
  const { data, error } = await supabase.rpc('get_my_umkm_application')
  if (error) throw new Error(error.message)
  return data?.[0] ?? null
}

export async function getMyUmkmDashboardMetrics(umkmId) {
  const { data, error } = await supabase.rpc('seller_dashboard_metrics', { p_umkm_id: umkmId })
  if (error) throw new Error(error.message)
  return data
}

export async function applyAsUmkm(fields) {
  const { data: { user }, error: userError } = await supabase.auth.getUser()
  if (userError) throw new Error(userError.message)
  if (!user) throw new Error('Sesi login tidak ditemukan. Silakan masuk kembali.')

  const name = fields.name.trim()
  const slug = slugify(name)
  if (!slug) throw new Error('Nama UMKM harus memiliki huruf atau angka.')
  const payload = {
    user_id: user.id,
    name,
    slug,
    region_id: fields.region_id || null,
    description: fields.description.trim() || null,
    address: fields.address.trim() || null,
    phone: fields.phone.trim() || null,
    status: 'pending',
    is_active: false,
    is_verified: false,
  }

  console.log('Payload Insert:', {
    user_id: Boolean(payload.user_id),
    status: payload.status,
    is_active: payload.is_active,
    is_verified: payload.is_verified,
    has_region_id: Boolean(payload.region_id),
  })

  const { error: insertError } = await supabase.from('umkm').insert(payload)
  if (insertError) {
    const code = insertError.code ? ` (${insertError.code})` : ''
    const details = insertError.details ? ` ${insertError.details}` : ''
    throw new Error(`${insertError.message}${code}${details}`)
  }

  const application = await getMyUmkm()
  if (!application) throw new Error('Pendaftaran terkirim, tetapi data pengajuan belum dapat dimuat.')
  return application
}

function takeProduct({ data, error }) {
  if (error) {
    if (error.code === '23505') throw new Error('Slug produk sudah digunakan. Ubah nama produk lalu coba lagi.')
    throw new Error(error.message)
  }
  return data
}

export async function listMyUmkmProducts(umkmId) {
  return takeProduct(
    await supabase
      .from('products')
      .select('id, name, slug, description, price, stock, category_id, is_active, categories(name), product_images(id, url, sort_order)')
      .eq('umkm_id', umkmId)
      .order('created_at', { ascending: false }),
  ) ?? []
}

export async function saveMyUmkmProduct(id, umkmId, fields) {
  const query = id
    ? supabase.from('products').update(fields).eq('id', id).eq('umkm_id', umkmId).select('id').maybeSingle()
    : supabase.from('products').insert({ ...fields, umkm_id: umkmId }).select('id').single()
  const product = takeProduct(await query)
  if (!product) throw new Error('Produk tidak ditemukan atau bukan milik UMKM Anda.')
  return product.id
}

export async function deleteMyUmkmProduct(id, umkmId) {
  const product = takeProduct(
    await supabase.from('products').delete().eq('id', id).eq('umkm_id', umkmId).select('id').maybeSingle(),
  )
  if (!product) throw new Error('Produk tidak ditemukan atau bukan milik UMKM Anda.')
}
