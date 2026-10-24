-- PasarPintar · 004 · Pembatalan otomatis pesanan kedaluwarsa (opsional, tiap jam)
-- LANGKAH SEBELUM MENJALANKAN: Supabase Dashboard → Database → Extensions → cari "pg_cron" → aktifkan.

select cron.schedule(
  'expire-unpaid-orders',
  '0 * * * *',
  $$ select public.expire_unpaid_orders(); $$
);

-- Cek jadwal:     select jobid, jobname, schedule from cron.job;
-- Cek hasil run:  select status, return_message, start_time from cron.job_run_details order by start_time desc limit 5;
-- Hapus jadwal:   select cron.unschedule('expire-unpaid-orders');
