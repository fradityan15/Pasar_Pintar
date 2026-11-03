-- PasarPintar · 004 · Pembatalan otomatis pesanan kedaluwarsa (opsional, tiap jam)
-- Supabase menyediakan pg_cron sebagai extension yang dapat diaktifkan oleh role migrasi.
create extension if not exists pg_cron;

select cron.schedule(
  'expire-unpaid-orders',
  '0 * * * *',
  $$ select public.expire_unpaid_orders(); $$
);

-- Cek jadwal:     select jobid, jobname, schedule from cron.job;
-- Cek hasil run:  select status, return_message, start_time from cron.job_run_details order by start_time desc limit 5;
-- Hapus jadwal:   select cron.unschedule('expire-unpaid-orders');
