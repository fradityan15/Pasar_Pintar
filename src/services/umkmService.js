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
      .maybeSingle(),
  )
}

export async function listUmkmProducts(umkmId) {
  return take(
    await supabase
      .from('products')
      .select('id, name, slug, price, stock, umkm(name, regions(name)), product_images(url, sort_order)')
      .eq('umkm_id', umkmId)
      .eq('is_active', true)
      .order('created_at', { ascending: false }),
  )
}
