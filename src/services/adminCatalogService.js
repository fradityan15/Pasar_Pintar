import { supabase } from '@/lib/supabase'

const take = ({ data, error }) => {
  if (error) {
    if (error.code === '23505') throw new Error('Nama atau slug sudah dipakai.')
    if (error.code === '23503') throw new Error('Data ini masih dipakai data lain, sehingga tidak bisa dihapus.')
    throw new Error(error.message)
  }
  return data
}

// Kategori
export const listCategoriesAdmin = async () =>
  take(await supabase.from('categories').select('id, parent_id, name, slug, is_active').order('name'))

export async function saveCategory(id, fields) {
  take(id ? await supabase.from('categories').update(fields).eq('id', id) : await supabase.from('categories').insert(fields))
}
export const deleteCategory = async (id) => take(await supabase.from('categories').delete().eq('id', id))

// Daerah
export const listRegions = async () => take(await supabase.from('regions').select('id, name, province').order('name'))
export const saveRegion = async (fields) => take(await supabase.from('regions').insert(fields).select().single())

// UMKM
export const listUmkmAdmin = async () =>
  take(await supabase.from('umkm').select('id, status, name, slug, description, region_id, address, phone, is_verified, is_active, regions(name)').order('name'))

export async function saveUmkm(id, fields) {
  take(id ? await supabase.from('umkm').update(fields).eq('id', id) : await supabase.from('umkm').insert(fields))
}
