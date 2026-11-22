-- ⑥ 공실클럽 (RSA 동문 전용) — Supabase yangseongi 프로젝트 lh 스키마
-- 접근은 모두 security definer RPC(gs_*)로만. 테이블은 RLS on + 정책 없음.

alter table lh.members add column if not exists rsa_cohort int;
alter table lh.members add column if not exists rsa_region text;
alter table lh.members add column if not exists gs_ok boolean not null default false;
alter table lh.members add column if not exists gs_admin boolean not null default false;
alter table lh.members add column if not exists gs_req text;
alter table lh.members add column if not exists gs_req_at timestamptz;

-- 동문 명단: 휴대폰 번호 sha256 앞 40자리 + 기수·권역·상태 (이름·번호 원문 없음)
create table if not exists lh.rsa_roster(
  h text primary key, cohort int, region text, status text, synced_at timestamptz not null default now());

create table if not exists lh.gs_listings(
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references lh.members(id) on delete cascade,
  deal text not null, kind text not null, region text not null,
  addr text not null, addr_detail text, lat double precision, lng double precision,
  deposit bigint, rent bigint, price bigint, mgmt bigint,
  area numeric, floor text, rooms text, move_in text,
  fee text, memo text,
  status text not null default '공실',
  photo_n int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  confirmed_at timestamptz not null default now());
create index if not exists gs_listings_member on lh.gs_listings(member_id);
create index if not exists gs_listings_region on lh.gs_listings(region, status);

create table if not exists lh.gs_photos(
  listing_id uuid not null references lh.gs_listings(id) on delete cascade,
  idx int not null, data text not null, primary key(listing_id, idx));

create table if not exists lh.gs_inquiries(
  id bigint generated always as identity primary key,
  listing_id uuid not null references lh.gs_listings(id) on delete cascade,
  from_member uuid not null references lh.members(id) on delete cascade,
  msg text, created_at timestamptz not null default now(), read_at timestamptz);
create index if not exists gs_inq_listing on lh.gs_inquiries(listing_id);
create index if not exists gs_inq_from on lh.gs_inquiries(from_member);

alter table lh.rsa_roster enable row level security;
alter table lh.gs_listings enable row level security;
alter table lh.gs_photos enable row level security;
alter table lh.gs_inquiries enable row level security;
revoke all on lh.rsa_roster, lh.gs_listings, lh.gs_photos, lh.gs_inquiries from anon, authenticated;

-- ---------- 내부 함수 ----------
create or replace function lh._rsa_match(m uuid) returns boolean
language plpgsql security definer set search_path = lh, extensions, public as $$
declare r lh.rsa_roster; ph text;
begin
  select phone into ph from lh.members where id = m;
  select * into r from lh.rsa_roster where h = left(encode(extensions.digest(coalesce(ph,''),'sha256'),'hex'),40);
  if r.h is null then return false; end if;
  update lh.members set rsa_cohort = r.cohort, rsa_region = r.region,
    gs_ok = (gs_ok or r.status in ('개업','소속','추가')) where id = m;
  return r.status in ('개업','소속','추가');
end $$;

create or replace function lh._gs(p_token text) returns uuid
language plpgsql security definer set search_path = lh, extensions, public as $$
declare m uuid := lh._auth(p_token); ok boolean;
begin
  select gs_ok into ok from lh.members where id = m;
  if not ok then raise exception 'GS_NOT_MEMBER' using errcode = 'P0001'; end if;
  return m;
end $$;

create or replace function lh._geo(p_addr text) returns jsonb
language plpgsql security definer set search_path = extensions, lh, public as $$
declare j jsonb; cat text; it jsonb;
begin
  foreach cat in array array['road','parcel'] loop
    begin
      j := lh._get('https://api.vworld.kr/req/search?service=search&request=search&version=2.0&crs=EPSG:4326&size=1&page=1&type=address&category='
        || cat || '&format=json&errorformat=json&query=' || urlencode(left(p_addr,120)) || '&' || lh._vbase());
      it := j #> '{response,result,items,0}';
      if it is not null then
        return jsonb_build_object('lat',(it->'point'->>'y')::float8,'lng',(it->'point'->>'x')::float8,
          'road',it->'address'->>'road','parcel',it->'address'->>'parcel');
      end if;
    exception when others then null;
    end;
  end loop;
  return null;
end $$;

create or replace function lh._gs_row(l lh.gs_listings, viewer uuid) returns jsonb
language sql stable security definer set search_path = lh, public as $$
  select jsonb_build_object('id',l.id,'deal',l.deal,'kind',l.kind,'region',l.region,'addr',l.addr,'addr_detail',l.addr_detail,
    'lat',l.lat,'lng',l.lng,'deposit',l.deposit,'rent',l.rent,'price',l.price,'mgmt',l.mgmt,'area',l.area,'floor',l.floor,
    'rooms',l.rooms,'move_in',l.move_in,'fee',l.fee,'memo',l.memo,'status',l.status,'photo_n',l.photo_n,
    'created_at',l.created_at,'updated_at',l.updated_at,'confirmed_at',l.confirmed_at,
    'mine',l.member_id = viewer,
    'owner',(select jsonb_build_object('name',m.name,'office',m.office,'cohort',m.rsa_cohort,'region',m.rsa_region) from lh.members m where m.id = l.member_id),
    'inq_n',(select count(*) from lh.gs_inquiries q where q.listing_id = l.id))
$$;

-- ---------- 공개 RPC ----------
create or replace function public.gs_me(p_token text) returns jsonb
language plpgsql security definer set search_path = lh, extensions, public as $$
declare m uuid := lh._auth(p_token); r lh.members;
begin
  select * into r from lh.members where id = m;
  if not r.gs_ok then perform lh._rsa_match(m); select * into r from lh.members where id = m; end if;
  return jsonb_build_object('ok',r.gs_ok,'admin',r.gs_admin,'name',r.name,'office',r.office,
    'cohort',r.rsa_cohort,'region',r.rsa_region,'pending',(not r.gs_ok and r.gs_req_at is not null),
    'mine',(select count(*) from lh.gs_listings where member_id = m and status <> '완료'),
    'stale',(select count(*) from lh.gs_listings where member_id = m and status <> '완료' and confirmed_at < now() - interval '14 days'),
    'unread',(select count(*) from lh.gs_inquiries q join lh.gs_listings l on l.id = q.listing_id where l.member_id = m and q.read_at is null),
    'pending_n',case when r.gs_admin then (select count(*) from lh.members where not gs_ok and gs_req_at is not null) end);
end $$;

create or replace function public.gs_request(p_token text, p_note text) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token);
begin
  if lh._rsa_match(m) then return jsonb_build_object('ok',true,'matched',true); end if;
  update lh.members set gs_req = left(coalesce(p_note,''),300), gs_req_at = now() where id = m;
  return jsonb_build_object('ok',true,'matched',false);
end $$;

create or replace function public.gs_admin_list(p_token text) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token);
begin
  if not (select gs_admin from lh.members where id = m) then raise exception '관리자만 볼 수 있습니다'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'office',office,'reg_no',reg_no,'phone',phone,'note',gs_req,'at',gs_req_at) order by gs_req_at)
    from lh.members where not gs_ok and gs_req_at is not null),'[]'::jsonb);
end $$;

create or replace function public.gs_admin_set(p_token text, p_member uuid, p_ok boolean) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token);
begin
  if not (select gs_admin from lh.members where id = m) then raise exception '관리자만 할 수 있습니다'; end if;
  update lh.members set gs_ok = p_ok, gs_req_at = case when p_ok then gs_req_at else null end,
    gs_req = case when p_ok then gs_req else '거절됨: '||coalesce(gs_req,'') end where id = p_member;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.gs_list(p_token text, p_f jsonb) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._gs(p_token); f jsonb := coalesce(p_f,'{}'::jsonb); q text := nullif(trim(f->>'q'),'');
begin
  return coalesce((select jsonb_agg(lh._gs_row(l, m) order by l.confirmed_at desc) from lh.gs_listings l where l.id in (
    select l.id from lh.gs_listings l
     where (case when (f->>'mine')::boolean then l.member_id = m
                 else l.status in ('공실','계약중') and (l.member_id = m or l.confirmed_at > now() - interval '21 days') end)
       and (nullif(f->>'region','') is null or l.region = f->>'region')
       and (nullif(f->>'deal','') is null or l.deal = f->>'deal')
       and (nullif(f->>'kind','') is null or l.kind = f->>'kind')
       and (nullif(f->>'maxDeposit','') is null or coalesce(l.deposit,0) <= (f->>'maxDeposit')::bigint)
       and (nullif(f->>'maxRent','') is null or coalesce(l.rent,0) <= (f->>'maxRent')::bigint)
       and (nullif(f->>'maxPrice','') is null or coalesce(l.price,0) <= (f->>'maxPrice')::bigint)
       and (q is null or (l.addr||' '||coalesce(l.addr_detail,'')||' '||coalesce(l.memo,'')||' '||l.kind) ilike '%'||q||'%')
     order by l.confirmed_at desc limit 400)),'[]'::jsonb);
end $$;

create or replace function public.gs_get(p_token text, p_id uuid) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._gs(p_token); l lh.gs_listings; r jsonb;
begin
  select * into l from lh.gs_listings where id = p_id;
  if l.id is null then raise exception '삭제되었거나 없는 공실입니다'; end if;
  r := lh._gs_row(l, m) || jsonb_build_object('photos',coalesce((select jsonb_agg(data order by idx) from lh.gs_photos where listing_id = p_id),'[]'::jsonb));
  if l.member_id = m then
    r := r || jsonb_build_object('inquiries',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'msg',q.msg,'at',q.created_at,'read',q.read_at is not null,
      'from',jsonb_build_object('name',x.name,'office',x.office,'phone',x.phone,'cohort',x.rsa_cohort)) order by q.created_at desc)
      from lh.gs_inquiries q join lh.members x on x.id = q.from_member where q.listing_id = p_id),'[]'::jsonb));
    update lh.gs_inquiries set read_at = now() where listing_id = p_id and read_at is null;
  else
    r := r || jsonb_build_object('asked',exists(select 1 from lh.gs_inquiries where listing_id = p_id and from_member = m));
    if exists(select 1 from lh.gs_inquiries where listing_id = p_id and from_member = m) then
      r := r || jsonb_build_object('contact',(select jsonb_build_object('phone',phone) from lh.members where id = l.member_id));
    end if;
  end if;
  return r;
end $$;

create or replace function public.gs_save(p_token text, p_id uuid, p_d jsonb) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._gs(p_token); d jsonb := coalesce(p_d,'{}'::jsonb); id_ uuid := p_id; old lh.gs_listings; g jsonb;
  n_ bigint; addr_ text := left(trim(coalesce(d->>'addr','')),150);
begin
  if addr_ = '' then raise exception '주소를 입력하세요'; end if;
  if coalesce(d->>'deal','') not in ('월세','전세','매매','단기') then raise exception '거래 유형을 고르세요'; end if;
  if coalesce(d->>'kind','') = '' then raise exception '매물 유형을 고르세요'; end if;
  if coalesce(d->>'region','') = '' then raise exception '권역을 고르세요'; end if;
  if id_ is not null then
    select * into old from lh.gs_listings where id = id_;
    if old.id is null or old.member_id <> m then raise exception '내 공실만 고칠 수 있습니다'; end if;
  else
    select count(*) into n_ from lh.gs_listings where member_id = m and status <> '완료';
    if n_ >= 200 then raise exception '공실은 1인당 200건까지 등록할 수 있습니다'; end if;
  end if;
  if old.id is null or old.addr is distinct from addr_ or old.lat is null then g := lh._geo(addr_); end if;
  if id_ is null then
    insert into lh.gs_listings(member_id,deal,kind,region,addr,addr_detail,lat,lng,deposit,rent,price,mgmt,area,floor,rooms,move_in,fee,memo)
    values (m, d->>'deal', left(d->>'kind',20), left(d->>'region',20), addr_, left(d->>'addr_detail',60),
      (g->>'lat')::float8, (g->>'lng')::float8,
      nullif(d->>'deposit','')::bigint, nullif(d->>'rent','')::bigint, nullif(d->>'price','')::bigint, nullif(d->>'mgmt','')::bigint,
      nullif(d->>'area','')::numeric, left(d->>'floor',20), left(d->>'rooms',30), left(d->>'move_in',30), left(d->>'fee',40), left(d->>'memo',1000))
    returning id into id_;
  else
    update lh.gs_listings set deal = d->>'deal', kind = left(d->>'kind',20), region = left(d->>'region',20), addr = addr_,
      addr_detail = left(d->>'addr_detail',60),
      lat = case when g is null and old.addr = addr_ then lat else (g->>'lat')::float8 end,
      lng = case when g is null and old.addr = addr_ then lng else (g->>'lng')::float8 end,
      deposit = nullif(d->>'deposit','')::bigint, rent = nullif(d->>'rent','')::bigint, price = nullif(d->>'price','')::bigint,
      mgmt = nullif(d->>'mgmt','')::bigint, area = nullif(d->>'area','')::numeric, floor = left(d->>'floor',20),
      rooms = left(d->>'rooms',30), move_in = left(d->>'move_in',30), fee = left(d->>'fee',40), memo = left(d->>'memo',1000),
      updated_at = now(), confirmed_at = now() where id = id_;
  end if;
  return jsonb_build_object('ok',true,'id',id_,'geo',g is not null or (old.id is not null and old.lat is not null and old.addr = addr_));
end $$;

create or replace function public.gs_photos_set(p_token text, p_id uuid, p_photos jsonb) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._gs(p_token); i int := 0; x text;
begin
  if not exists(select 1 from lh.gs_listings where id = p_id and member_id = m) then raise exception '내 공실만 고칠 수 있습니다'; end if;
  if jsonb_array_length(coalesce(p_photos,'[]')) > 5 then raise exception '사진은 5장까지입니다'; end if;
  delete from lh.gs_photos where listing_id = p_id;
  for x in select jsonb_array_elements_text(coalesce(p_photos,'[]')) loop
    if left(x,23) <> 'data:image/jpeg;base64,' or length(x) > 400000 then raise exception '사진 형식이나 크기를 확인하세요'; end if;
    insert into lh.gs_photos(listing_id, idx, data) values (p_id, i, x); i := i + 1;
  end loop;
  update lh.gs_listings set photo_n = i, updated_at = now() where id = p_id;
  return jsonb_build_object('ok',true,'n',i);
end $$;

create or replace function public.gs_status(p_token text, p_id uuid, p_status text) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._gs(p_token);
begin
  if p_status not in ('공실','계약중','완료','확인') then raise exception '상태 값 오류'; end if;
  update lh.gs_listings set status = case when p_status = '확인' then status else p_status end,
    confirmed_at = now(), updated_at = now() where id = p_id and member_id = m;
  if not found then raise exception '내 공실만 바꿀 수 있습니다'; end if;
  if p_status = '완료' then delete from lh.gs_photos where listing_id = p_id; update lh.gs_listings set photo_n = 0 where id = p_id; end if;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.gs_delete(p_token text, p_id uuid) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._gs(p_token);
begin
  delete from lh.gs_listings where id = p_id and member_id = m;
  if not found then raise exception '내 공실만 지울 수 있습니다'; end if;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.gs_inquire(p_token text, p_id uuid, p_msg text) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._gs(p_token); l lh.gs_listings;
begin
  select * into l from lh.gs_listings where id = p_id;
  if l.id is null then raise exception '삭제되었거나 없는 공실입니다'; end if;
  if l.member_id = m then raise exception '내 공실입니다'; end if;
  if (select count(*) from lh.gs_inquiries where from_member = m and created_at > now() - interval '1 day') >= 60 then
    raise exception '오늘 문의 한도(60건)를 넘었습니다'; end if;
  insert into lh.gs_inquiries(listing_id, from_member, msg) values (p_id, m, left(coalesce(p_msg,''),300));
  return jsonb_build_object('ok',true,'contact',(select jsonb_build_object('name',name,'office',office,'phone',phone) from lh.members where id = l.member_id));
end $$;

create or replace function public.gs_inbox(p_token text) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._gs(p_token); r jsonb;
begin
  r := jsonb_build_object(
    'received',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'listing',jsonb_build_object('id',l.id,'deal',l.deal,'kind',l.kind,'addr',l.addr,'addr_detail',l.addr_detail),
       'msg',q.msg,'at',q.created_at,'read',q.read_at is not null,'from',jsonb_build_object('name',x.name,'office',x.office,'phone',x.phone,'cohort',x.rsa_cohort)) order by q.created_at desc)
       from lh.gs_inquiries q join lh.gs_listings l on l.id = q.listing_id join lh.members x on x.id = q.from_member
      where l.member_id = m and q.created_at > now() - interval '180 days'),'[]'::jsonb),
    'sent',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'listing',jsonb_build_object('id',l.id,'deal',l.deal,'kind',l.kind,'addr',l.addr,'status',l.status),
       'msg',q.msg,'at',q.created_at,'to',jsonb_build_object('name',x.name,'office',x.office,'phone',x.phone,'cohort',x.rsa_cohort)) order by q.created_at desc)
       from lh.gs_inquiries q join lh.gs_listings l on l.id = q.listing_id join lh.members x on x.id = l.member_id
      where q.from_member = m and q.created_at > now() - interval '180 days'),'[]'::jsonb));
  update lh.gs_inquiries q set read_at = now() from lh.gs_listings l where l.id = q.listing_id and l.member_id = m and q.read_at is null;
  return r;
end $$;

-- 권한: 내부 함수는 막고, 공개 RPC만 anon 실행
revoke all on function lh._rsa_match(uuid), lh._gs(text), lh._geo(text), lh._gs_row(lh.gs_listings, uuid) from public, anon, authenticated;
revoke all on function public.gs_me(text), public.gs_request(text,text), public.gs_admin_list(text), public.gs_admin_set(text,uuid,boolean),
  public.gs_list(text,jsonb), public.gs_get(text,uuid), public.gs_save(text,uuid,jsonb), public.gs_photos_set(text,uuid,jsonb),
  public.gs_status(text,uuid,text), public.gs_delete(text,uuid), public.gs_inquire(text,uuid,text), public.gs_inbox(text) from public;
grant execute on function public.gs_me(text), public.gs_request(text,text), public.gs_admin_list(text), public.gs_admin_set(text,uuid,boolean),
  public.gs_list(text,jsonb), public.gs_get(text,uuid), public.gs_save(text,uuid,jsonb), public.gs_photos_set(text,uuid,jsonb),
  public.gs_status(text,uuid,text), public.gs_delete(text,uuid), public.gs_inquire(text,uuid,text), public.gs_inbox(text) to anon, authenticated;

-- 첫 관리자: 허브 개설자(현재 유일한 가입자)
update lh.members set gs_admin = true, gs_ok = true where name = '길문수';
