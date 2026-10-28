import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { supabase } from '@/lib/supabase'

export const useAuthStore = defineStore('auth', () => {
  const user = ref(null)
  const profile = ref(null)
  const ready = ref(false)
  let initPromise = null

  const isLoggedIn = computed(() => !!user.value)
  const isAdmin = computed(() => profile.value?.role === 'admin')

  async function loadProfile() {
    if (!user.value) { profile.value = null; return }
    const { data } = await supabase
      .from('profiles')
      .select('id, full_name, phone, role')
      .eq('id', user.value.id)
      .maybeSingle()
    profile.value = data
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
    if (error) throw new Error(terjemah(error.message))
    // Supabase may hide the duplicate-email error when email confirmation is enabled.
    if (data.user && Array.isArray(data.user.identities) && data.user.identities.length === 0) {
      throw new Error(terjemah('User already registered'))
    }
    // Jika "Confirm email" aktif di Supabase, session kosong sampai email diverifikasi.
    user.value = data.session?.user ?? null
    await loadProfile()
    return { needsConfirmation: !data.session }
  }

  async function signOut() {
    await supabase.auth.signOut()
    user.value = null
    profile.value = null
  }

  return { user, profile, ready, isLoggedIn, isAdmin, init, signIn, signUp, signOut }
})

function terjemah(msg) {
  if (/invalid login/i.test(msg)) return 'Email atau kata sandi salah.'
  if (/already registered|already exists/i.test(msg)) return 'Email ini sudah terdaftar. Silakan gunakan email lain atau langsung Masuk.'
  if (/password should be at least/i.test(msg)) return 'Kata sandi minimal 6 karakter.'
  if (/email not confirmed/i.test(msg)) return 'Email belum diverifikasi. Cek kotak masuk Anda.'
  return msg
}
