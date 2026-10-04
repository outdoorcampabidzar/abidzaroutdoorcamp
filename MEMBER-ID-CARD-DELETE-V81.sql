

-- V81: Hapus Data Anggota / ID Card (admin only).
drop function if exists public.secure_admin_delete_member_id_card(uuid);
create or replace function public.secure_admin_delete_member_id_card(
  p_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted boolean := false;
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak. Hanya administrator yang dapat menghapus Data Anggota.' using errcode = '42501';
  end if;

  delete from public.member_id_cards
  where id = p_id;

  v_deleted := found;
  if not v_deleted then
    raise exception 'Data Anggota tidak ditemukan.';
  end if;

  return true;
end;
$$;

grant execute on function public.secure_admin_delete_member_id_card(uuid) to authenticated;
