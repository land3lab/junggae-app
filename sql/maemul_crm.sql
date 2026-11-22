-- ⑨ 매물장 · ⑩ 고객관리 — Supabase yangseongi 프로젝트 lh 스키마
-- 모든 자료는 등록한 중개사 본인만 봄. 접근은 security definer RPC(mj_*, cr_*, jg_today)로만.
-- 테이블은 RLS on + 정책 없음(직접 조회 불가).

-- ---------- 매물장 ----------
create table if not exists lh.mj_listings(
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references lh.members(id) on delete cascade,
  status text not null default '접수',          -- 접수·광고중·계약진행·계약완료·보류·철회
  deal text not null, kind text not null, region text,
  addr text not null, ho text, bldg text, lat double precision, lng double precision,
  deposit bigint, rent bigint, price bigint, mgmt bigint,   -- 원 단위
  area numeric, supply numeric, floor text, total_floor text,
  rooms int, baths int, dir text, park text, elevator boolean, approve text, move_in text,
  options text, memo text,
  owner_name text, owner_phone text, owner_cond text, consent boolean not null default false,
  ads jsonb not null default '[]'::jsonb,       -- [{ch,start,end,down}]
  gs_id uuid, lh_light text, geo_fail boolean not null default false,
  photo_n int not null default 0, thumb text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  confirmed_at timestamptz not null default now(),
  done_at timestamptz);
alter table lh.mj_listings add column if not exists thumb text;
alter table lh.mj_listings add column if not exists geo_fail boolean not null default false;
create index if not exists mj_listings_member on lh.mj_listings(member_id, status);

create table if not exists lh.mj_photos(
  listing_id uuid not null references lh.mj_listings(id) on delete cascade,
  idx int not null, data text not null, primary key(listing_id, idx));

-- ---------- 고객관리 ----------
create table if not exists lh.cr_customers(
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references lh.members(id) on delete cascade,
  name text not null, phone text, kind text not null, source text, temp text not null default 'B',
  stage text not null default '진행',             -- 진행·계약·종료
  wants jsonb not null default '{}'::jsonb, memo text,
  consent boolean not null default false, consent_at date,
  next_at date, last_contact timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create index if not exists cr_customers_member on lh.cr_customers(member_id, stage);

create table if not exists lh.cr_logs(
  id bigint generated always as identity primary key,
  customer_id uuid not null references lh.cr_customers(id) on delete cascade,
  at date not null default current_date, type text not null, body text,
  listing_ids uuid[] not null default '{}', reaction text,
  created_at timestamptz not null default now());
create index if not exists cr_logs_customer on lh.cr_logs(customer_id, at desc);

create table if not exists lh.cr_deals(
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references lh.cr_customers(id) on delete cascade,
  listing_id uuid references lh.mj_listings(id) on delete set null,
  title text, contract date, middle date, balance date, expiry date, memo text,
  created_at timestamptz not null default now());
create index if not exists cr_deals_customer on lh.cr_deals(customer_id);

alter table lh.mj_listings enable row level security;
alter table lh.mj_photos enable row level security;
alter table lh.cr_customers enable row level security;
alter table lh.cr_logs enable row level security;
alter table lh.cr_deals enable row level security;
revoke all on lh.mj_listings, lh.mj_photos, lh.cr_customers, lh.cr_logs, lh.cr_deals from anon, authenticated;

-- ---------- 내부 함수 ----------
-- 주민등록번호처럼 보이는 숫자는 저장 거부
create or replace function lh._nopii(t text) returns void
language plpgsql immutable as $$
begin
  if coalesce(t,'') ~ '(^|[^0-9])[0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])[-\s]?[1-8][0-9]{6}([^0-9]|$)' then
    raise exception '주민등록번호로 보이는 숫자는 저장할 수 없습니다' using errcode = 'P0001';
  end if;
end $$;

create or replace function lh._won(x text) returns bigint
language sql immutable as $$ select nullif(regexp_replace(coalesce(x,''),'[^0-9]','','g'),'')::bigint $$;
create or replace function lh._num(x text) returns numeric
language sql immutable as $$ select nullif(regexp_replace(coalesce(x,''),'[^0-9.]','','g'),'')::numeric $$;
create or replace function lh._int(x text) returns int
language sql immutable as $$ select nullif(regexp_replace(coalesce(x,''),'[^0-9]','','g'),'')::int $$;

-- ---------- 매물장 RPC ----------
create or replace function public.mj_list(p_token text) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token);
begin
  return coalesce((select jsonb_agg(to_jsonb(l) - 'member_id' order by l.updated_at desc)
    from lh.mj_listings l where l.member_id = m),'[]'::jsonb);
end $$;

create or replace function public.mj_get(p_token text, p_id uuid) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token); l lh.mj_listings;
begin
  select * into l from lh.mj_listings where id = p_id and member_id = m;
  if l.id is null then raise exception '내 매물장에 없는 매물입니다'; end if;
  return to_jsonb(l) - 'member_id' || jsonb_build_object('photos',
    coalesce((select jsonb_agg(data order by idx) from lh.mj_photos where listing_id = p_id),'[]'::jsonb));
end $$;

create or replace function public.mj_save(p_token text, p_id uuid, p_d jsonb) returns jsonb
language plpgsql security definer set search_path = lh, extensions, public as $$
declare m uuid := lh._auth(p_token); d jsonb := coalesce(p_d,'{}'::jsonb); id_ uuid := p_id; old lh.mj_listings; g jsonb;
  addr_ text := left(trim(coalesce(d->>'addr','')),150); n_ int;
begin
  if addr_ = '' then raise exception '주소를 입력하세요'; end if;
  if coalesce(d->>'deal','') not in ('월세','전세','매매','단기') then raise exception '거래 유형을 고르세요'; end if;
  if coalesce(d->>'kind','') = '' then raise exception '매물 유형을 고르세요'; end if;
  perform lh._nopii(d->>'memo'); perform lh._nopii(d->>'owner_cond'); perform lh._nopii(d->>'options');
  if coalesce(d->>'owner_name','') <> '' or coalesce(d->>'owner_phone','') <> '' then
    if not coalesce((d->>'consent')::boolean,false) then raise exception '의뢰인 개인정보 수집·이용 동의를 체크하세요'; end if;
  end if;
  if id_ is not null then
    select * into old from lh.mj_listings where id = id_;
    if old.id is null or old.member_id <> m then raise exception '내 매물만 고칠 수 있습니다'; end if;
  else
    select count(*) into n_ from lh.mj_listings where member_id = m;
    if n_ >= 1000 then raise exception '매물장은 1인당 1,000건까지입니다'; end if;
  end if;
  if coalesce((d->>'nogeo')::boolean,false) = false and (old.id is null or old.addr is distinct from addr_ or old.lat is null) then
    g := lh._geo(addr_);
  end if;
  if id_ is null then
    insert into lh.mj_listings(member_id, status, deal, kind, addr)
    values (m, case when d->>'status' in ('접수','광고중','계약진행','계약완료','보류','철회') then d->>'status' else '접수' end, d->>'deal', left(d->>'kind',20), addr_)
    returning id into id_;
    select * into old from lh.mj_listings where id = id_;
  end if;
  update lh.mj_listings set
    deal = d->>'deal', kind = left(d->>'kind',20), region = left(nullif(d->>'region',''),20), addr = addr_,
    ho = left(nullif(d->>'ho',''),60), bldg = left(nullif(d->>'bldg',''),60),
    lat = case when g is not null then (g->>'lat')::float8 when old.addr = addr_ then old.lat end,
    lng = case when g is not null then (g->>'lng')::float8 when old.addr = addr_ then old.lng end,
    deposit = lh._won(d->>'deposit'), rent = lh._won(d->>'rent'), price = lh._won(d->>'price'), mgmt = lh._won(d->>'mgmt'),
    area = lh._num(d->>'area'), supply = lh._num(d->>'supply'), floor = left(nullif(d->>'floor',''),20), total_floor = left(nullif(d->>'total_floor',''),20),
    rooms = lh._int(d->>'rooms'), baths = lh._int(d->>'baths'), dir = left(nullif(d->>'dir',''),20), park = left(nullif(d->>'park',''),40),
    elevator = (nullif(d->>'elevator',''))::boolean, approve = left(nullif(d->>'approve',''),20), move_in = left(nullif(d->>'move_in',''),40),
    options = left(nullif(d->>'options',''),300), memo = left(nullif(d->>'memo',''),2000),
    owner_name = left(nullif(d->>'owner_name',''),40), owner_phone = left(nullif(d->>'owner_phone',''),20),
    owner_cond = left(nullif(d->>'owner_cond',''),500), consent = coalesce((d->>'consent')::boolean,false),
    lh_light = coalesce(nullif(d->>'lh_light',''), lh_light), geo_fail = case when old.addr is distinct from addr_ then false else geo_fail end,
    updated_at = now(), confirmed_at = now()
  where id = id_;
  return jsonb_build_object('ok',true,'id',id_,'geo',(select lat is not null from lh.mj_listings where id = id_));
end $$;

create or replace function public.mj_photos_set(p_token text, p_id uuid, p_photos jsonb, p_thumb text) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token); i int := 0; x text;
begin
  if not exists(select 1 from lh.mj_listings where id = p_id and member_id = m) then raise exception '내 매물만 고칠 수 있습니다'; end if;
  if jsonb_array_length(coalesce(p_photos,'[]')) > 8 then raise exception '사진은 8장까지입니다'; end if;
  delete from lh.mj_photos where listing_id = p_id;
  for x in select jsonb_array_elements_text(coalesce(p_photos,'[]')) loop
    if left(x,23) <> 'data:image/jpeg;base64,' or length(x) > 400000 then raise exception '사진 형식이나 크기를 확인하세요'; end if;
    insert into lh.mj_photos(listing_id, idx, data) values (p_id, i, x); i := i + 1;
  end loop;
  if p_thumb is not null and (left(p_thumb,23) <> 'data:image/jpeg;base64,' or length(p_thumb) > 30000) then p_thumb := null; end if;
  update lh.mj_listings set photo_n = i, thumb = case when i = 0 then null else p_thumb end, updated_at = now() where id = p_id;
  return jsonb_build_object('ok',true,'n',i);
end $$;

create or replace function public.mj_status(p_token text, p_id uuid, p_status text) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token);
begin
  if p_status not in ('접수','광고중','계약진행','계약완료','보류','철회','확인') then raise exception '상태 값 오류'; end if;
  update lh.mj_listings set
    status = case when p_status = '확인' then status else p_status end,
    done_at = case when p_status = '계약완료' then now() when p_status = '확인' then done_at else null end,
    confirmed_at = now(), updated_at = now()
  where id = p_id and member_id = m;
  if not found then raise exception '내 매물만 바꿀 수 있습니다'; end if;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.mj_ads(p_token text, p_id uuid, p_ads jsonb) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token);
begin
  if jsonb_typeof(coalesce(p_ads,'[]')) <> 'array' or jsonb_array_length(p_ads) > 20 then raise exception '광고 기록 형식 오류'; end if;
  update lh.mj_listings set ads = p_ads, updated_at = now() where id = p_id and member_id = m;
  if not found then raise exception '내 매물만 바꿀 수 있습니다'; end if;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.mj_link(p_token text, p_id uuid, p_gs uuid, p_lh text) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token);
begin
  update lh.mj_listings set gs_id = coalesce(p_gs, gs_id), lh_light = coalesce(nullif(p_lh,''), lh_light) where id = p_id and member_id = m;
  if not found then raise exception '내 매물만 바꿀 수 있습니다'; end if;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.mj_delete(p_token text, p_id uuid) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token);
begin
  delete from lh.mj_listings where id = p_id and member_id = m;
  if not found then raise exception '내 매물만 지울 수 있습니다'; end if;
  return jsonb_build_object('ok',true);
end $$;

-- 주소 위치 못 찾은 매물을 몇 건씩 채움(가져오기 후 반복 호출)
create or replace function public.mj_geo_fill(p_token text) returns jsonb
language plpgsql security definer set search_path = lh, extensions, public as $$
declare m uuid := lh._auth(p_token); r record; g jsonb; n int := 0;
begin
  for r in select id, addr from lh.mj_listings where member_id = m and lat is null and not geo_fail order by created_at limit 3 loop
    g := lh._geo(r.addr);
    if g is null then update lh.mj_listings set geo_fail = true where id = r.id;
    else update lh.mj_listings set lat = (g->>'lat')::float8, lng = (g->>'lng')::float8 where id = r.id; n := n + 1; end if;
  end loop;
  return jsonb_build_object('ok',true,'filled',n,'left',(select count(*) from lh.mj_listings where member_id = m and lat is null and not geo_fail));
end $$;

-- ---------- 고객관리 RPC ----------
create or replace function public.cr_list(p_token text) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token);
begin
  return coalesce((select jsonb_agg(to_jsonb(c) - 'member_id' || jsonb_build_object(
      'log_n',(select count(*) from lh.cr_logs g where g.customer_id = c.id),
      'last_log',(select jsonb_build_object('at',g.at,'type',g.type,'body',left(g.body,80)) from lh.cr_logs g where g.customer_id = c.id order by g.at desc, g.id desc limit 1),
      'shown',(select coalesce(jsonb_agg(distinct x),'[]'::jsonb) from lh.cr_logs g, unnest(g.listing_ids) x where g.customer_id = c.id),
      'deals',(select coalesce(jsonb_agg(to_jsonb(d) - 'customer_id' order by d.created_at),'[]'::jsonb) from lh.cr_deals d where d.customer_id = c.id))
    order by c.updated_at desc) from lh.cr_customers c where c.member_id = m),'[]'::jsonb);
end $$;

create or replace function public.cr_get(p_token text, p_id uuid) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token); c lh.cr_customers;
begin
  select * into c from lh.cr_customers where id = p_id and member_id = m;
  if c.id is null then raise exception '내 고객 목록에 없는 고객입니다'; end if;
  return to_jsonb(c) - 'member_id' || jsonb_build_object(
    'logs',coalesce((select jsonb_agg(to_jsonb(g) - 'customer_id' order by g.at desc, g.id desc) from lh.cr_logs g where g.customer_id = p_id),'[]'::jsonb),
    'deals',coalesce((select jsonb_agg(to_jsonb(d) - 'customer_id' order by d.created_at) from lh.cr_deals d where d.customer_id = p_id),'[]'::jsonb));
end $$;

create or replace function public.cr_save(p_token text, p_id uuid, p_d jsonb) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token); d jsonb := coalesce(p_d,'{}'::jsonb); id_ uuid := p_id; n_ int; ok_ boolean := coalesce((d->>'consent')::boolean,false);
begin
  if trim(coalesce(d->>'name','')) = '' then raise exception '고객 이름(또는 호칭)을 입력하세요'; end if;
  if coalesce(d->>'kind','') not in ('매수','임차','매도','임대','투자','법인','공동중개') then raise exception '고객 종류를 고르세요'; end if;
  if coalesce(d->>'temp','B') not in ('A','B','C','휴면') then raise exception '온도 값 오류'; end if;
  if coalesce(d->>'stage','진행') not in ('진행','계약','종료') then raise exception '단계 값 오류'; end if;
  if not ok_ then raise exception '개인정보 수집·이용 동의를 받았는지 체크하세요'; end if;
  perform lh._nopii(d->>'memo'); perform lh._nopii(d->>'name'); perform lh._nopii((d->'wants')::text);
  if id_ is not null then
    if not exists(select 1 from lh.cr_customers where id = id_ and member_id = m) then raise exception '내 고객만 고칠 수 있습니다'; end if;
  else
    select count(*) into n_ from lh.cr_customers where member_id = m;
    if n_ >= 3000 then raise exception '고객은 1인당 3,000명까지입니다'; end if;
    insert into lh.cr_customers(member_id, name, kind, consent, consent_at) values (m, 'x', d->>'kind', true, current_date) returning id into id_;
  end if;
  update lh.cr_customers set name = left(trim(d->>'name'),40), phone = left(nullif(regexp_replace(coalesce(d->>'phone',''),'[^0-9]','','g'),''),15),
    kind = d->>'kind', source = left(nullif(d->>'source',''),20), temp = coalesce(nullif(d->>'temp',''),'B'),
    stage = coalesce(nullif(d->>'stage',''),'진행'), wants = coalesce(d->'wants','{}'::jsonb), memo = left(nullif(d->>'memo',''),2000),
    consent = true, consent_at = coalesce(consent_at, current_date),
    next_at = nullif(d->>'next_at','')::date, updated_at = now()
  where id = id_;
  return jsonb_build_object('ok',true,'id',id_);
end $$;

create or replace function public.cr_delete(p_token text, p_ids uuid[]) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token); n int;
begin
  delete from lh.cr_customers where id = any(p_ids) and member_id = m;
  get diagnostics n = row_count;
  return jsonb_build_object('ok',true,'n',n);
end $$;

create or replace function public.cr_log_add(p_token text, p_cid uuid, p_d jsonb) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token); d jsonb := coalesce(p_d,'{}'::jsonb); ids uuid[];
begin
  if not exists(select 1 from lh.cr_customers where id = p_cid and member_id = m) then raise exception '내 고객만 기록할 수 있습니다'; end if;
  if coalesce(d->>'type','') not in ('전화','문자','방문','현장안내','계약','메모') then raise exception '기록 종류를 고르세요'; end if;
  perform lh._nopii(d->>'body');
  select coalesce(array_agg(x::uuid),'{}') into ids from jsonb_array_elements_text(coalesce(d->'listing_ids','[]')) x
    where exists(select 1 from lh.mj_listings l where l.id = x::uuid and l.member_id = m);
  insert into lh.cr_logs(customer_id, at, type, body, listing_ids, reaction)
  values (p_cid, coalesce(nullif(d->>'at','')::date, current_date), d->>'type', left(d->>'body',2000), ids, left(nullif(d->>'reaction',''),300));
  update lh.cr_customers set last_contact = now(), updated_at = now(),
    next_at = case when d ? 'next_at' then nullif(d->>'next_at','')::date else next_at end,
    temp = coalesce(nullif(d->>'temp',''), temp)
  where id = p_cid;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.cr_log_delete(p_token text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token);
begin
  delete from lh.cr_logs g using lh.cr_customers c where g.id = p_id and c.id = g.customer_id and c.member_id = m;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.cr_deal_save(p_token text, p_cid uuid, p_id uuid, p_d jsonb) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token); d jsonb := coalesce(p_d,'{}'::jsonb); id_ uuid := p_id; lid uuid := nullif(d->>'listing_id','')::uuid;
begin
  if not exists(select 1 from lh.cr_customers where id = p_cid and member_id = m) then raise exception '내 고객만 기록할 수 있습니다'; end if;
  if lid is not null and not exists(select 1 from lh.mj_listings where id = lid and member_id = m) then lid := null; end if;
  perform lh._nopii(d->>'memo');
  if id_ is null then insert into lh.cr_deals(customer_id) values (p_cid) returning id into id_;
  elsif not exists(select 1 from lh.cr_deals where id = id_ and customer_id = p_cid) then raise exception '계약 일정을 찾지 못했습니다'; end if;
  update lh.cr_deals set listing_id = lid, title = left(nullif(d->>'title',''),80),
    contract = nullif(d->>'contract','')::date, middle = nullif(d->>'middle','')::date,
    balance = nullif(d->>'balance','')::date, expiry = nullif(d->>'expiry','')::date, memo = left(nullif(d->>'memo',''),500)
  where id = id_;
  update lh.cr_customers set stage = '계약', updated_at = now() where id = p_cid and stage = '진행';
  return jsonb_build_object('ok',true,'id',id_);
end $$;

create or replace function public.cr_deal_delete(p_token text, p_id uuid) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token);
begin
  delete from lh.cr_deals d using lh.cr_customers c where d.id = p_id and c.id = d.customer_id and c.member_id = m;
  return jsonb_build_object('ok',true);
end $$;

-- ---------- 허브 홈 "오늘 챙길 것" ----------
create or replace function public.jg_today(p_token text) returns jsonb
language plpgsql security definer set search_path = lh, public as $$
declare m uuid := lh._auth(p_token);
begin
  return jsonb_build_object(
    'mj_active',(select count(*) from lh.mj_listings where member_id = m and status in ('접수','광고중','계약진행')),
    'mj_stale',(select count(*) from lh.mj_listings where member_id = m and status in ('접수','광고중','계약진행') and confirmed_at < now() - interval '14 days'),
    'mj_ad_soon',(select count(distinct l.id) from lh.mj_listings l, jsonb_array_elements(l.ads) a where l.member_id = m and l.status = '광고중'
        and not coalesce((a->>'down')::boolean,false) and nullif(a->>'end','')::date <= current_date + 3),
    'mj_not_down',(select count(distinct l.id) from lh.mj_listings l, jsonb_array_elements(l.ads) a where l.member_id = m
        and l.status in ('계약완료','철회','보류') and not coalesce((a->>'down')::boolean,false)),
    'cr_due',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'kind',kind,'temp',temp,'next_at',next_at) order by next_at, temp)
        from (select * from lh.cr_customers where member_id = m and stage <> '종료' and next_at <= current_date order by next_at limit 8) c),'[]'::jsonb),
    'cr_due_n',(select count(*) from lh.cr_customers where member_id = m and stage <> '종료' and next_at <= current_date),
    'cr_events',coalesce((select jsonb_agg(e order by e->>'date') from (
        select jsonb_build_object('name',c.name,'what',w.what,'date',w.dt) e
          from lh.cr_deals d join lh.cr_customers c on c.id = d.customer_id
          cross join lateral (values ('계약',d.contract),('중도금',d.middle),('잔금',d.balance)) w(what,dt)
         where c.member_id = m and w.dt between current_date and current_date + 7
        union all
        select jsonb_build_object('name',c.name,'what','만기 '||case when d.expiry <= current_date + 92 then '3개월' else '6개월' end||' 전','date',d.expiry)
          from lh.cr_deals d join lh.cr_customers c on c.id = d.customer_id
         where c.member_id = m and (d.expiry between current_date + 85 and current_date + 92 or d.expiry between current_date + 176 and current_date + 183)
        limit 10) x),'[]'::jsonb));
end $$;

-- 권한
revoke all on function lh._nopii(text), lh._won(text), lh._num(text), lh._int(text) from public, anon, authenticated;
do $$ declare f text; begin
  foreach f in array array[
    'public.mj_list(text)','public.mj_get(text,uuid)','public.mj_save(text,uuid,jsonb)','public.mj_photos_set(text,uuid,jsonb,text)',
    'public.mj_status(text,uuid,text)','public.mj_ads(text,uuid,jsonb)','public.mj_link(text,uuid,uuid,text)','public.mj_delete(text,uuid)','public.mj_geo_fill(text)',
    'public.cr_list(text)','public.cr_get(text,uuid)','public.cr_save(text,uuid,jsonb)','public.cr_delete(text,uuid[])',
    'public.cr_log_add(text,uuid,jsonb)','public.cr_log_delete(text,bigint)','public.cr_deal_save(text,uuid,uuid,jsonb)','public.cr_deal_delete(text,uuid)',
    'public.jg_today(text)'] loop
    execute 'revoke all on function '||f||' from public';
    execute 'grant execute on function '||f||' to anon, authenticated';
  end loop;
end $$;
