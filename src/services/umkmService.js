import { supabase } from '@/lib/supabase'

const take = ({ data, error }) => {
  if (error) throw new Error(error.message)
  return data
}

export async function listUmkm() {
  return take(
    await supabase
      .from('umkm')
      .select('id, name, slug, description, is_verified, regions(name, province)')
      .eq('is_active', true)
      .eq('is_verified', true)
      .eq('status', 'active')
      .order('name'),
  )
}

export async function getUmkmBySlug(slug) {
  return take(
    await supabase
      .from('umkm')
      .select('id, name, slug, description, address, phone, is_verified, regions(name, province)')
      .eq('slug', slug)
      .eq('is_active', true)
      .eq('is_verified', true)
      .eq('status', 'active')
      .maybeSingle(),
  )
}

export async function listUmkmProducts(umkmId) {
  return take(
    await supabase
      .from('products')
      .select('id, name, slug, price, stock, umkm!inner(name, regions(name)), product_images(url, sort_order)')
      .eq('umkm_id', umkmId)
      .eq('is_active', true)
      .eq('umkm.is_active', true)
      .eq('umkm.is_verified', true)
      .eq('umkm.status', 'active')
      .order('created_at', { ascending: false }),
  )
}
