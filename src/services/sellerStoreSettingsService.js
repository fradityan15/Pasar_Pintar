import { supabase } from '@/lib/supabase'

const BUCKET = 'seller-assets'
const MAX_IMAGE_SIZE = 4 * 1024 * 1024
const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp'])
const EXTENSIONS = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' }

export async function getStoreSettings(umkmId) {
  const { data, error } = await supabase.rpc('get_my_store_settings', { p_umkm_id: umkmId })
  if (error) throw new Error(error.message)
  return data
}

export async function saveStoreSettings(umkmId, settings) {
  const { error } = await supabase.rpc('save_my_store_settings', {
    p_umkm_id: umkmId,
    p_settings: settings,
  })
  if (error) throw new Error(error.message)
}

export async function uploadStoreAsset(umkmId, file) {
  if (!IMAGE_TYPES.has(file.type)) throw new Error('Format gambar harus JPG, PNG, atau WebP.')
  if (file.size > MAX_IMAGE_SIZE) throw new Error('Ukuran gambar maksimal 4 MB.')

  const path = `${umkmId}/${crypto.randomUUID()}.${EXTENSIONS[file.type]}`
  const { error } = await supabase.storage.from(BUCKET).upload(path, file, {
    contentType: file.type,
    cacheControl: '3600',
  })
  if (error) throw new Error(error.message)
  return supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl
}

export async function deleteStoreAsset(url) {
  if (!url) return
  const marker = `/${BUCKET}/`
  const markerIndex = url.indexOf(marker)
  if (markerIndex < 0) return

  const path = url.slice(markerIndex + marker.length)
  const { error } = await supabase.storage.from(BUCKET).remove([path])
  if (error) throw new Error(error.message)
}
