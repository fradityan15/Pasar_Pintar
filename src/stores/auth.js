import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { supabase } from '@/lib/supabase'

export const useAuthStore = defineStore('auth', () => {
  const user = ref(null)
  const profile = ref(null)
  const ready = ref(false)
  const profileLoading = ref(false)
  const profileError = ref('')
  let initPromise = null
  let profileRequestId = 0

  const isLoggedIn = computed(() => !!user.value)
  const isAdmin = computed(() => ['admin', 'super_admin'].includes(profile.value?.role))
  const isSuperAdmin = computed(() => profile.value?.role === 'super_admin')

  async function loadProfile() {
    const requestId = ++profileRequestId
    const userId = user.value?.id
    profileError.value = ''
    if (!userId) {
      profile.value = null
      profileLoading.value = false
      return true
    }

    profileLoading.value = true
    profile.value = null
    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('id, full_name, phone, role')
        .eq('id', userId)
        .maybeSingle()

      if (requestId !== profileRequestId || user.value?.id !== userId) return false
      if (error) {
        console.error('Gagal memuat profil pengguna:', error)
        profileError.value = 'Profil Anda gagal dimuat. Periksa koneksi lalu coba lagi.'
        return false
      }

      profile.value = data
      return true
    } catch (error) {
      console.error('Gagal memuat profil pengguna:', error)
      if (requestId === profileRequestId && user.value?.id === userId) {
        profileError.value = 'Profil Anda gagal dimuat. Periksa koneksi lalu coba lagi.'
      }
      return false
    } finally {
      if (requestId === profileRequestId) profileLoading.value = false
    }
  }

  /** Dipanggil route guard; aman dipanggil berkali-kali. */
  function init() {
    if (!initPromise) {
      initPromise = (async () => {
        const { data } = await supabase.auth.getSession()
        user.value = data.session?.user ?? null
        await loadProfile()
        ready.value = true
        // Jangan await panggilan Supabase di dalam callback ini (bisa deadlock).
        supabase.auth.onAuthStateChange((_event, session) => {
          user.value = session?.user ?? null
          setTimeout(loadProfile, 0)
        })
      })()
    }
    return initPromise
  }

  async function signIn(email, password) {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw new Error(terjemah(error.message))
    const { data } = await supabase.auth.getSession()
    user.value = data.session?.user ?? null
    await loadProfile()
  }

  async function signUp(fullName, email, password) {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: { data: { full_name: fullName } },
    })
    const duplicateEmail =
      /already registered|already exists/i.test(error?.message ?? '') ||
      (!error && data.user && Array.isArray(data.user.identities) && data.user.identities.length === 0)
    if (duplicateEmail) return { needsConfirmation: true }
    if (error) throw new Error(terjemah(error.message))

    if (data.session) {
      const { error: signOutError } = await supabase.auth.signOut({ scope: 'local' })
      if (signOutError) throw new Error(signOutError.message)
    }
    user.value = null
    profile.value = null
    profileError.value = ''
    return { needsConfirmation: true }
  }

  async function signOut() {
    await supabase.auth.signOut()
    user.value = null
    profile.value = null
    profileError.value = ''
  }

  return {
    user, profile, ready, profileLoading, profileError,
    isLoggedIn, isAdmin, isSuperAdmin, init, loadProfile, signIn, signUp, signOut,
  }
})

function terjemah(msg) {
  if (/invalid login/i.test(msg)) return 'Email atau kata sandi salah.'
  if (/password should be at least/i.test(msg)) return 'Kata sandi minimal 6 karakter.'
  if (/email not confirmed/i.test(msg)) return 'Email belum diverifikasi. Cek kotak masuk Anda.'
  return msg
}
