<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import AdminPageHeader from '@/components/AdminPageHeader.vue'
import ModalDialog from '@/components/ModalDialog.vue'
import { deleteCategory, listCategoriesAdmin, saveCategory } from '@/services/adminCatalogService'
import { slugify } from '@/lib/slug'

const cats = ref([])
const loading = ref(true)
const error = ref('')
const notice = ref('')
const open = ref(false)
const editingId = ref(null)
const saving = ref(false)
const formError = ref('')
const slugTouched = ref(false)
const form = reactive({ name: '', slug: '', parent_id: '', is_active: true })

// Induk lalu anak-anaknya, diurutkan nama.
const rows = computed(() => {
  const parents = cats.value.filter((c) => !c.parent_id)
  const out = []
  for (const p of parents) {
    out.push({ ...p, depth: 0 })
    for (const c of cats.value.filter((x) => x.parent_id === p.id)) out.push({ ...c, depth: 1 })
  }
  return out
})
const parentOptions = computed(() => cats.value.filter((c) => !c.parent_id && c.id !== editingId.value))
const hasChildren = (id) => cats.value.some((c) => c.parent_id === id)

watch(() => form.name, (v) => { if (!slugTouched.value) form.slug = slugify(v) })

async function load() {
  loading.value = true
  error.value = ''
  try { cats.value = await listCategoriesAdmin() }
  catch (e) { error.value = e.message }
  finally { loading.value = false }
}
onMounted(load)

function bukaForm(c = null) {
  editingId.value = c?.id ?? null
  Object.assign(form, { name: c?.name ?? '', slug: c?.slug ?? '', parent_id: c?.parent_id ?? '', is_active: c?.is_active ?? true })
  slugTouched.value = !!c
  formError.value = ''
  open.value = true
}

async function simpan() {
  saving.value = true
  formError.value = ''
  try {
    await saveCategory(editingId.value, {
      name: form.name.trim(), slug: form.slug.trim(), parent_id: form.parent_id || null, is_active: form.is_active,
    })
    open.value = false
    notice.value = 'Kategori disimpan.'
    await load()
  } catch (e) {
    formError.value = e.message
  } finally {
    saving.value = false
  }
}

async function hapus(c) {
  if (!confirm(`Hapus kategori "${c.name}"? Produk di dalamnya menjadi tanpa kategori.`)) return
  notice.value = ''
  try {
    await deleteCategory(c.id)
    notice.value = 'Kategori dihapus.'
    await load()
  } catch (e) {
    error.value = e.message
  }
}
</script>

<template>
  <AdminPageHeader title="Kategori" desc="Kelompokkan produk dalam kategori induk dan subkategori.">
    <button class="btn-primary" type="button" @click="bukaForm()">Tambah kategori</button>
  </AdminPageHeader>

  <div class="card p-5">
    <p v-if="notice" class="mb-3 rounded-xl bg-ok-bg p-3 text-sm text-ok-fg" role="status">{{ notice }}</p>
    <p v-if="error" class="mb-3 rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error }}</p>
    <div v-if="loading" class="h-40 animate-pulse rounded-xl bg-surface"></div>
    <p v-else-if="!rows.length" class="rounded-xl bg-surface p-8 text-center text-sm text-muted">Belum ada kategori.</p>
    <div v-else class="w-full overflow-x-auto">
      <table class="w-full min-w-[520px] text-left text-sm">
        <thead class="text-xs text-muted"><tr><th class="p-3 font-medium">Nama</th><th class="p-3 font-medium">Slug</th><th class="p-3 font-medium">Status</th><th class="p-3"></th></tr></thead>
        <tbody>
          <tr v-for="c in rows" :key="c.id" class="border-t border-line">
            <td class="p-3" :class="c.depth ? 'pl-9' : 'font-semibold'">{{ c.depth ? '↳ ' : '' }}{{ c.name }}</td>
            <td class="p-3 text-muted">{{ c.slug }}</td>
            <td class="p-3"><span class="badge" :class="c.is_active ? 'bg-ok-bg text-ok-fg' : 'bg-surface text-muted'">{{ c.is_active ? 'Aktif' : 'Nonaktif' }}</span></td>
            <td class="whitespace-nowrap p-3 text-right">
              <button class="font-semibold underline" type="button" @click="bukaForm(c)">Ubah</button>
              <button class="ml-3 font-semibold text-bad-fg underline" type="button" :disabled="hasChildren(c.id)" :title="hasChildren(c.id) ? 'Hapus subkategori dulu' : ''" @click="hapus(c)">Hapus</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>

  <ModalDialog :open="open" :title="editingId ? 'Ubah kategori' : 'Tambah kategori'" @close="open = false">
    <form class="flex flex-col gap-3" @submit.prevent="simpan">
      <div><label for="k-nama" class="mb-1.5 block text-sm font-medium">Nama</label><input id="k-nama" v-model="form.name" class="input" required /></div>
      <div><label for="k-slug" class="mb-1.5 block text-sm font-medium">Slug</label><input id="k-slug" v-model="form.slug" class="input" pattern="[a-z0-9]+(-[a-z0-9]+)*" required @input="slugTouched = true" /></div>
      <div>
        <label for="k-induk" class="mb-1.5 block text-sm font-medium">Kategori induk</label>
        <select id="k-induk" v-model="form.parent_id" class="input" :disabled="editingId && hasChildren(editingId)">
          <option value="">Tidak ada (kategori induk)</option>
          <option v-for="p in parentOptions" :key="p.id" :value="p.id">{{ p.name }}</option>
        </select>
      </div>
      <label class="flex items-center gap-2 text-sm"><input v-model="form.is_active" type="checkbox" /> Aktif</label>
      <p v-if="formError" class="rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ formError }}</p>
      <div class="flex justify-end gap-2">
        <button class="btn-outline" type="button" @click="open = false">Batal</button>
        <button class="btn-primary" type="submit" :disabled="saving">{{ saving ? 'Menyimpan…' : 'Simpan' }}</button>
      </div>
    </form>
  </ModalDialog>
</template>
