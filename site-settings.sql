-- AbidzarOutdoorcamp - Pengaturan Website
-- Jalankan seluruh file ini satu kali melalui Supabase SQL Editor.

create table if not exists public.site_settings (
  id text primary key,
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

alter table public.site_settings enable row level security;

drop policy if exists "site settings dapat dibaca publik" on public.site_settings;
create policy "site settings dapat dibaca publik"
on public.site_settings for select to anon, authenticated
using (id = 'main');

revoke insert, update, delete on public.site_settings from anon, authenticated;
grant select on public.site_settings to anon, authenticated;

insert into public.site_settings (id, settings)
values ('main', jsonb_build_object(
  'site_name', 'AbidzarOutdoorcamp',
  'whatsapp_number', '6289509349428',
  'whatsapp_message', 'Halo CS AbidzarOutdoorcamp, saya ingin bertanya mengenai layanan.',
  'admin_1_name', 'Admin 1', 'admin_1_whatsapp', '',
  'admin_2_name', 'Admin 2', 'admin_2_whatsapp', '',
  'admin_3_name', 'Admin 3', 'admin_3_whatsapp', '',
  'address', '', 'business_hours', '', 'google_maps_url', '',
  'instagram_url', '', 'tiktok_url', '',
  'hero_eyebrow', 'Outdoor rental & open trip',
  'hero_title', 'Siapkan petualangan.',
  'hero_subtitle', 'Pesan semuanya di satu tempat.',
  'hero_description', 'Cari perlengkapan di katalog Sewa Item atau pilih perjalanan di katalog Open Trip. Keduanya tetap dapat digabungkan dalam satu keranjang dan satu checkout.',
  'seo_title', 'AbidzarOutdoorcamp — Sewa Outdoor & Open Trip',
  'seo_description', 'Katalog sewa perlengkapan outdoor dan open trip AbidzarOutdoorcamp.',
  'rental_min_days', 1, 'rental_max_days', 30,
  'payment_enabled', false,
  'payment_method', 'qrisorkut',
  'payment_timeout_minutes', 15,
  'late_fee_text', '', 'guarantee_policy', '',
  'cancellation_policy', '', 'refund_policy', '',
  'maintenance_mode', false,
  'maintenance_message', 'Website sedang dalam perawatan. Silakan hubungi kami melalui WhatsApp.'
)) on conflict (id) do nothing;

create or replace function public.admin_save_site_settings(p_settings jsonb)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_is_admin boolean;
  v_settings jsonb;
  v_min_days integer;
  v_max_days integer;
begin
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and lower(trim(coalesce(role, ''))) = 'admin'
  ) into v_is_admin;

  if not v_is_admin then
    raise exception 'Akses administrator diperlukan.';
  end if;

  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    raise exception 'Format pengaturan tidak valid.';
  end if;

  begin
    v_min_days := greatest(1, least(365, coalesce((p_settings->>'rental_min_days')::integer, 1)));
    v_max_days := greatest(v_min_days, least(365, coalesce((p_settings->>'rental_max_days')::integer, 30)));
  exception when invalid_text_representation then
    v_min_days := 1;
    v_max_days := 30;
  end;

  v_settings := p_settings || jsonb_build_object(
    'site_name', left(trim(coalesce(p_settings->>'site_name', '')), 120),
    'whatsapp_number', regexp_replace(coalesce(p_settings->>'whatsapp_number', ''), '[^0-9]', '', 'g'),
    'admin_1_whatsapp', regexp_replace(coalesce(p_settings->>'admin_1_whatsapp', ''), '[^0-9]', '', 'g'),
    'admin_2_whatsapp', regexp_replace(coalesce(p_settings->>'admin_2_whatsapp', ''), '[^0-9]', '', 'g'),
    'admin_3_whatsapp', regexp_replace(coalesce(p_settings->>'admin_3_whatsapp', ''), '[^0-9]', '', 'g'),
    'rental_min_days', v_min_days,
    'rental_max_days', v_max_days,
    'maintenance_mode', coalesce((p_settings->>'maintenance_mode')::boolean, false)
  );

  if v_settings->>'site_name' = '' or v_settings->>'whatsapp_number' = '' then
    raise exception 'Nama website dan nomor WhatsApp wajib diisi.';
  end if;

  insert into public.site_settings (id, settings, updated_at, updated_by)
  values ('main', v_settings, now(), auth.uid())
  on conflict (id) do update set
    settings = excluded.settings,
    updated_at = excluded.updated_at,
    updated_by = excluded.updated_by;

  return v_settings;
end;
$$;

revoke all on function public.admin_save_site_settings(jsonb) from public;
grant execute on function public.admin_save_site_settings(jsonb) to authenticated;
