<script setup>
import { onBeforeUnmount, ref, watch } from 'vue'
import { searchRajaOngkirAreas } from '@/services/rajaOngkirService'

const props = defineProps({
  id: { type: String, required: true },
  modelValue: { type: String, default: '' },
})
const emit = defineEmits(['update:modelValue'])

const searchText = ref('')
const areas = ref([])
const loading = ref(false)
const error = ref('')
const input = ref(null)
let debounceTimer
let searchRequestId = 0
let ignoreNextModelUpdate = false

function setValidity() {
  input.value?.setCustomValidity(
    props.modelValue ? '' : 'Pilih wilayah dari hasil pencarian RajaOngkir.',
  )
}

watch(() => props.modelValue, (value) => {
  if (ignoreNextModelUpdate) {
    ignoreNextModelUpdate = false
    setValidity()
    return
  }
  searchText.value = value ? `ID wilayah tersimpan: ${value}` : ''
  setValidity()
}, { immediate: true })

function updateModel(value) {
  if (props.modelValue !== value) ignoreNextModelUpdate = true
  emit('update:modelValue', value)
}

function search() {
  clearTimeout(debounceTimer)
  const currentRequestId = ++searchRequestId
  const query = searchText.value.trim()
  areas.value = []
  error.value = ''

  if (query.length < 2) {
    loading.value = false
    return
  }
  debounceTimer = setTimeout(async () => {
    loading.value = true
    try {
      const results = await searchRajaOngkirAreas(query)
      if (currentRequestId === searchRequestId) areas.value = results
    } catch (searchError) {
      if (currentRequestId === searchRequestId) error.value = searchError.message
    } finally {
      if (currentRequestId === searchRequestId) loading.value = false
    }
  }, 350)
}

function updateSearch(event) {
  searchText.value = event.target.value
  updateModel('')
  setValidity()
  search()
}

function selectArea(area) {
  searchText.value = area.label
  areas.value = []
  error.value = ''
  updateModel(area.id)
  setValidity()
}

onBeforeUnmount(() => {
  clearTimeout(debounceTimer)
  searchRequestId += 1
})
</script>

<template>
  <div>
    <label :for="id" class="mb-1 block text-sm font-medium">
      Wilayah pengiriman (RajaOngkir)
    </label>
    <input
      :id="id"
      ref="input"
      :value="searchText"
      class="input w-full"
      type="search"
      autocomplete="off"
      maxlength="80"
      required
      placeholder="Cari kode pos, kelurahan, kecamatan, atau kota"
      aria-autocomplete="list"
      :aria-expanded="areas.length > 0"
      @input="updateSearch"
      @invalid="setValidity"
    />
    <p class="mt-1 text-xs text-slate-500">
      Cari dengan kode pos atau nama wilayah, lalu pilih hasil yang sesuai dengan alamat.
    </p>
    <p v-if="loading" class="mt-2 text-sm text-slate-500" role="status">Mencari wilayah…</p>
    <p v-if="error" class="mt-2 text-sm text-bad-fg" role="alert">{{ error }}</p>
    <ul
      v-if="areas.length"
      class="mt-2 max-h-56 overflow-y-auto rounded-xl border border-slate-200 bg-white shadow-lg"
      role="listbox"
      aria-label="Hasil pencarian wilayah RajaOngkir"
    >
      <li v-for="area in areas" :key="area.id">
        <button
          type="button"
          role="option"
          aria-selected="false"
          class="w-full px-3 py-2 text-left text-sm transition hover:bg-slate-50 focus:bg-slate-50 focus:outline-none"
          @click="selectArea(area)"
        >
          <span class="block font-medium text-slate-900">{{ area.name }}</span>
          <span class="block text-xs text-slate-500">{{ area.label }}</span>
        </button>
      </li>
    </ul>
    <p v-else-if="searchText.trim().length >= 2 && !loading && !error" class="mt-2 text-sm text-slate-500" role="status">
      Tidak ada wilayah yang cocok. Coba kata kunci lain.
    </p>
  </div>
</template>
