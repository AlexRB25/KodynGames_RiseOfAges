-- Rise of Ages: monedas, gemas, Game Pass Premium (pase de temporada) y tienda.
-- Pégalo completo en Supabase > SQL Editor y pulsa Run (después de esquema.sql).
-- Se puede volver a ejecutar: no borra nada de los jugadores.
--
-- Cómo funciona (más detalle en docs/TEMPORADAS.md):
--   * Monedas: se ganan jugando y en el pase. Sirven en la tienda.
--   * Gemas: se compran con dinero (paquetes) y algunas salen en el pase.
--            Sirven para cosas especiales de la tienda.
--   * Experiencia de temporada (xp): se gana en cada partida, aparte de los puntos de rango.
--     Cada nivel del pase pide tier_xp. Hay dos filas de premios: gratis y premium.
--   * Game Pass Premium: se paga con dinero (Stripe; luego Google Play), NUNCA con gemas.
--     Abre la fila premium y da +20 % de xp. Precio por moneda en roa_premium_prices.
--   * Jugar en línea es gratis para todos (no hace falta el pase).
--   * Tienda: ofertas del día (5 artículos con descuento, distintos para cada jugador y
--     cada día), regalo diario de monedas, paquetes de monedas que se pagan con gemas y
--     "saltar nivel" del pase con gemas.
--
-- Seguridad: el jugador solo LEE y pide acciones por funciones que revisan todo
-- (reclamar, comprar, equipar). La xp de las partidas con rango la da el servidor del
-- juego; la de las partidas contra bots tiene tope diario. Las gemas y el Premium los
-- entrega solo el servidor después de que Stripe confirma el pago.

-- =====================================================================================
-- Monedero y lo que lleva puesto el jugador
-- =====================================================================================
alter table public.roa_profiles add column if not exists coins integer not null default 0;
alter table public.roa_profiles add column if not exists gems integer not null default 0;
alter table public.roa_profiles add column if not exists title text not null default '';
alter table public.roa_profiles add column if not exists image text not null default '';
alter table public.roa_profiles add column if not exists banner text not null default '';
alter table public.roa_profiles drop constraint if exists roa_profiles_coins_check;
alter table public.roa_profiles add constraint roa_profiles_coins_check check (coins >= 0);
alter table public.roa_profiles drop constraint if exists roa_profiles_gems_check;
alter table public.roa_profiles add constraint roa_profiles_gems_check check (gems >= 0);

-- Pagos con dinero de todos los juegos Kodyn (Zombie War ya la crea; aquí por si acaso).
create table if not exists public.kodyn_purchases (
  id bigint generated always as identity primary key,
  game text not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  product text not null,
  provider text not null,
  provider_ref text not null,
  amount numeric(12, 2) not null default 0,
  currency text not null default 'USD',
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (provider, provider_ref)
);
alter table public.kodyn_purchases enable row level security;
drop policy if exists "kodyn mis compras" on public.kodyn_purchases;
create policy "kodyn mis compras" on public.kodyn_purchases
  for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on public.kodyn_purchases from anon, authenticated;

-- =====================================================================================
-- Catálogo: todo lo que se puede tener
-- =====================================================================================
-- kind:
--   imagen      imagen de perfil      detail {"file": "civs/maya/unidades/aldeano/nivel1.png"} (dentro de assets/)
--   estandarte  fondo de tu tarjeta   detail {"bg": "#7a1f12", "edge": "#f5c24c", "mark": "#f5c24c"}
--   titulo      texto bajo tu nombre  (el nombre del artículo es el título)
--   civ         civilización          detail {"civ": "inca"}  (si existe aquí y no es free, hay que tenerla)
--   skin        vestimenta            detail {"civ": "maya", "unit": "aldeano"}  (el juego la usará cuando haya arte)
-- free = la tiene todo el mundo sin comprarla.
create table if not exists public.roa_items (
  id text primary key,
  kind text not null check (kind in ('imagen', 'estandarte', 'titulo', 'civ', 'skin')),
  name text not null,
  detail jsonb not null default '{}'::jsonb,
  rarity text not null default 'comun' check (rarity in ('comun', 'raro', 'epico', 'legendario')),
  free boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.roa_owned (
  user_id uuid not null references auth.users (id) on delete cascade,
  item_id text not null references public.roa_items (id) on delete cascade,
  source text not null default '',           -- 'pase t1 nivel 10 premium', 'tienda', 'regalo'…
  created_at timestamptz not null default now(),
  primary key (user_id, item_id)
);

-- =====================================================================================
-- Temporadas y pase
-- =====================================================================================
create table if not exists public.roa_seasons (
  id text primary key,
  name text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  tiers integer not null default 50,
  tier_xp integer not null default 500,          -- xp por nivel del pase
  premium_bonus numeric not null default 0.20    -- +20 % de xp con Premium
);

-- El Premium ya no se compra con gemas (precio en dinero en roa_premium_prices).
alter table public.roa_seasons drop column if exists premium_gems;

create table if not exists public.roa_season_rewards (
  season_id text not null references public.roa_seasons (id) on delete cascade,
  tier integer not null,
  track text not null check (track in ('free', 'premium')),
  kind text not null check (kind in ('coins', 'gems', 'item')),
  item_id text references public.roa_items (id),
  amount integer not null default 0,
  primary key (season_id, tier, track)
);

create table if not exists public.roa_season_progress (
  user_id uuid not null references auth.users (id) on delete cascade,
  season_id text not null references public.roa_seasons (id) on delete cascade,
  xp integer not null default 0 check (xp >= 0),
  premium boolean not null default false,
  games integer not null default 0,
  wins integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, season_id)
);

create table if not exists public.roa_season_claims (
  user_id uuid not null references auth.users (id) on delete cascade,
  season_id text not null references public.roa_seasons (id) on delete cascade,
  tier integer not null,
  track text not null,
  claimed_at timestamptz not null default now(),
  primary key (user_id, season_id, tier, track)
);

-- Partidas contra bots premiadas por día (tope para que no se pueda inflar la xp).
create table if not exists public.roa_daily (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null default current_date,
  bot_games integer not null default 0,
  last_bot_at timestamptz,
  primary key (user_id, day)
);
alter table public.roa_daily add column if not exists gift boolean not null default false;   -- regalo del día reclamado

-- =====================================================================================
-- Tienda y paquetes de gemas
-- =====================================================================================
-- Cada artículo se vende en monedas O en gemas (uno de los dos).
create table if not exists public.roa_shop (
  item_id text primary key references public.roa_items (id) on delete cascade,
  price_coins integer check (price_coins > 0),
  price_gems integer check (price_gems > 0),
  sort integer not null default 0,
  active boolean not null default true,
  check ((price_coins is null) <> (price_gems is null))
);

create table if not exists public.roa_gem_packs (
  id text primary key,
  gems integer not null check (gems > 0),
  bonus integer not null default 0 check (bonus >= 0),   -- gemas de regalo (se suman)
  sort integer not null default 0,
  active boolean not null default true
);

-- Precio de cada paquete en cada moneda. El juego muestra el de la moneda del jugador
-- (por su país); si no hay, cobra en USD. Respeta los mínimos de Stripe (0.50 USD, 10 MXN).
create table if not exists public.roa_gem_prices (
  pack_id text not null references public.roa_gem_packs (id) on delete cascade,
  currency text not null check (currency = upper(currency) and length(currency) = 3),
  amount numeric(12, 2) not null check (amount > 0),
  primary key (pack_id, currency)
);

-- Paquetes de monedas: se pagan con gemas (nunca con dinero directo).
create table if not exists public.roa_coin_packs (
  id text primary key,
  coins integer not null check (coins > 0),
  price_gems integer not null check (price_gems > 0),
  sort integer not null default 0,
  active boolean not null default true
);

-- Precio del Game Pass Premium en cada moneda (dinero real, cobrado con Stripe).
-- Si la moneda del jugador no está, se cobra en USD. Mínimos de Stripe: 0.50 USD, 10 MXN.
create table if not exists public.roa_premium_prices (
  currency text primary key check (currency = upper(currency) and length(currency) = 3),
  amount numeric(12, 2) not null check (amount > 0)
);

-- =====================================================================================
-- Permisos: todos leen el catálogo; cada quien solo lo suyo; nadie escribe directo.
-- =====================================================================================
alter table public.roa_items enable row level security;
alter table public.roa_owned enable row level security;
alter table public.roa_seasons enable row level security;
alter table public.roa_season_rewards enable row level security;
alter table public.roa_season_progress enable row level security;
alter table public.roa_season_claims enable row level security;
alter table public.roa_daily enable row level security;
alter table public.roa_shop enable row level security;
alter table public.roa_gem_packs enable row level security;
alter table public.roa_gem_prices enable row level security;
alter table public.roa_premium_prices enable row level security;
alter table public.roa_coin_packs enable row level security;
drop policy if exists "roa paquetes de monedas visibles" on public.roa_coin_packs;
create policy "roa paquetes de monedas visibles" on public.roa_coin_packs for select to anon, authenticated using (active);

drop policy if exists "roa items visibles" on public.roa_items;
create policy "roa items visibles" on public.roa_items for select to anon, authenticated using (true);
drop policy if exists "roa temporadas visibles" on public.roa_seasons;
create policy "roa temporadas visibles" on public.roa_seasons for select to anon, authenticated using (true);
drop policy if exists "roa premios visibles" on public.roa_season_rewards;
create policy "roa premios visibles" on public.roa_season_rewards for select to anon, authenticated using (true);
drop policy if exists "roa tienda visible" on public.roa_shop;
create policy "roa tienda visible" on public.roa_shop for select to anon, authenticated using (active);
drop policy if exists "roa paquetes visibles" on public.roa_gem_packs;
create policy "roa paquetes visibles" on public.roa_gem_packs for select to anon, authenticated using (active);
drop policy if exists "roa precios visibles" on public.roa_gem_prices;
create policy "roa precios visibles" on public.roa_gem_prices for select to anon, authenticated using (true);
drop policy if exists "roa precio premium visible" on public.roa_premium_prices;
create policy "roa precio premium visible" on public.roa_premium_prices for select to anon, authenticated using (true);
drop policy if exists "roa lo mio" on public.roa_owned;
create policy "roa lo mio" on public.roa_owned for select to authenticated using (user_id = auth.uid());
drop policy if exists "roa mi progreso" on public.roa_season_progress;
create policy "roa mi progreso" on public.roa_season_progress for select to authenticated using (user_id = auth.uid());
drop policy if exists "roa mis reclamos" on public.roa_season_claims;
create policy "roa mis reclamos" on public.roa_season_claims for select to authenticated using (user_id = auth.uid());

revoke insert, update, delete on public.roa_items, public.roa_owned, public.roa_seasons, public.roa_season_rewards,
  public.roa_season_progress, public.roa_season_claims, public.roa_daily, public.roa_shop, public.roa_gem_packs,
  public.roa_gem_prices, public.roa_premium_prices, public.roa_coin_packs from anon, authenticated;

-- =====================================================================================
-- Funciones
-- =====================================================================================

-- Temporada en curso (fila vacía si no hay).
create or replace function public.roa_current_season()
returns public.roa_seasons
language sql
stable
security definer
set search_path = public
as $fn$
  select * from public.roa_seasons
   where now() >= starts_at and now() < ends_at
   order by starts_at desc
   limit 1;
$fn$;

-- Lo que da cada partida. p_kind: 'ranked' (en línea con rango) o 'bots' (un jugador).
-- Cámbialo aquí: vale para el juego y el servidor.
create or replace function public.roa_match_prize(p_kind text, p_won boolean)
returns jsonb
language sql
immutable
as $fn$
  select case
    when p_kind = 'ranked' and p_won then '{"xp": 200, "coins": 60}'::jsonb
    when p_kind = 'ranked' then '{"xp": 80, "coins": 20}'::jsonb
    when p_won then '{"xp": 100, "coins": 25}'::jsonb
    else '{"xp": 40, "coins": 10}'::jsonb
  end;
$fn$;

-- Tope de partidas contra bots que dan premio cada día y minutos mínimos de partida.
create or replace function public.roa_bot_daily() returns integer language sql immutable as $fn$ select 8 $fn$;
create or replace function public.roa_bot_minutes() returns integer language sql immutable as $fn$ select 5 $fn$;

-- Suma xp de temporada y monedas a un jugador. Devuelve lo ganado.
create or replace function public.roa_award(p_user uuid, p_kind text, p_won boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_prize jsonb := public.roa_match_prize(p_kind, p_won);
  v_season public.roa_seasons;
  v_prog public.roa_season_progress;
  v_xp integer := 0;
  v_coins integer := (v_prize->>'coins')::integer;
begin
  insert into public.roa_profiles (id) values (p_user) on conflict (id) do nothing;
  update public.roa_profiles set coins = coins + v_coins, updated_at = now() where id = p_user;
  v_season := public.roa_current_season();
  if v_season.id is not null then
    insert into public.roa_season_progress (user_id, season_id) values (p_user, v_season.id)
    on conflict (user_id, season_id) do nothing;
    select * into v_prog from public.roa_season_progress
     where user_id = p_user and season_id = v_season.id for update;
    v_xp := round((v_prize->>'xp')::integer * (case when v_prog.premium then 1 + v_season.premium_bonus else 1 end));
    update public.roa_season_progress
       set xp = xp + v_xp, games = games + 1, wins = wins + case when p_won then 1 else 0 end, updated_at = now()
     where user_id = p_user and season_id = v_season.id
    returning * into v_prog;
  end if;
  return jsonb_build_object(
    'xp', v_xp, 'coins', v_coins,
    'season_xp', coalesce(v_prog.xp, 0),
    'tier', case when v_season.id is null then 0 else least(v_season.tiers, coalesce(v_prog.xp, 0) / v_season.tier_xp) end);
end;
$fn$;

-- Lo que el jugador tiene puesto, con lo gratis como respaldo.
create or replace function public.roa_owns(p_user uuid, p_item text)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select exists (select 1 from public.roa_items i where i.id = p_item and i.free)
      or exists (select 1 from public.roa_owned o where o.user_id = p_user and o.item_id = p_item);
$fn$;

-- Todo lo que el juego muestra: monedero, temporada, pase, premios, colección, tienda y paquetes.
-- Tienda: cuántas ofertas al día, cuánto descuento, regalo diario y precio de saltar nivel.
create or replace function public.roa_deal_count() returns integer language sql immutable as $fn$ select 5 $fn$;
create or replace function public.roa_deal_off() returns numeric language sql immutable as $fn$ select 0.25 $fn$;
create or replace function public.roa_gift_coins() returns integer language sql immutable as $fn$ select 50 $fn$;
create or replace function public.roa_skip_gems() returns integer language sql immutable as $fn$ select 30 $fn$;

-- ¿Este artículo está hoy en las ofertas de este jugador? (cambian cada día a las 00:00 UTC)
create or replace function public.roa_is_deal(p_user uuid, p_item text)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select exists (
    select 1 from (
      select s.item_id
        from public.roa_shop s join public.roa_items i on i.id = s.item_id
       where s.active and i.active
       order by md5(s.item_id || current_date::text || p_user::text)
       limit public.roa_deal_count()
    ) d where d.item_id = p_item);
$fn$;

-- Precio con el descuento del día (si es oferta).
create or replace function public.roa_deal_price(p_user uuid, p_item text, p_price integer)
returns integer
language sql
stable
security definer
set search_path = public
as $fn$
  select case when p_price is null then null
              when public.roa_is_deal(p_user, p_item) then ceil(p_price * (1 - public.roa_deal_off()))::integer
              else p_price end;
$fn$;

create or replace function public.roa_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_prof public.roa_profiles;
  v_season public.roa_seasons;
  v_prog public.roa_season_progress;
  v_daily public.roa_daily;
begin
  if v_uid is null then
    raise exception 'Sin sesión';
  end if;
  insert into public.roa_profiles (id) values (v_uid) on conflict (id) do nothing;
  select * into v_prof from public.roa_profiles where id = v_uid;
  v_season := public.roa_current_season();
  if v_season.id is not null then
    insert into public.roa_season_progress (user_id, season_id) values (v_uid, v_season.id)
    on conflict (user_id, season_id) do nothing;
    select * into v_prog from public.roa_season_progress where user_id = v_uid and season_id = v_season.id;
  end if;
  select * into v_daily from public.roa_daily where user_id = v_uid and day = current_date;
  return jsonb_build_object(
    'coins', v_prof.coins,
    'gems', v_prof.gems,
    'title', v_prof.title,
    'image', v_prof.image,
    'banner', v_prof.banner,
    'season', case when v_season.id is null then null
                   else to_jsonb(v_season) || jsonb_build_object('now', now()) end,
    'xp', coalesce(v_prog.xp, 0),
    'premium', coalesce(v_prog.premium, false),
    'rewards', coalesce((select jsonb_agg(jsonb_build_object('tier', r.tier, 'track', r.track, 'kind', r.kind,
                                                             'item', r.item_id, 'amount', r.amount)
                                          order by r.tier, r.track)
                           from public.roa_season_rewards r where r.season_id = v_season.id), '[]'::jsonb),
    'claimed', coalesce((select jsonb_agg(c.track || ':' || c.tier)
                           from public.roa_season_claims c
                          where c.user_id = v_uid and c.season_id = v_season.id), '[]'::jsonb),
    'items', coalesce((select jsonb_object_agg(i.id, jsonb_build_object('kind', i.kind, 'name', i.name,
                                                 'detail', i.detail, 'rarity', i.rarity, 'free', i.free))
                         from public.roa_items i where i.active), '{}'::jsonb),
    'owned', coalesce((select jsonb_agg(o.item_id) from public.roa_owned o where o.user_id = v_uid), '[]'::jsonb),
    'shop', coalesce((select jsonb_agg(jsonb_build_object('item', s.item_id, 'coins', s.price_coins,
                                                          'gems', s.price_gems) order by s.sort, s.item_id)
                        from public.roa_shop s join public.roa_items i on i.id = s.item_id
                       where s.active and i.active), '[]'::jsonb),
    'packs', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'gems', p.gems, 'bonus', p.bonus,
                         'prices', coalesce((select jsonb_object_agg(x.currency, x.amount)
                                               from public.roa_gem_prices x where x.pack_id = p.id), '{}'::jsonb))
                                          order by p.sort, p.gems)
                         from public.roa_gem_packs p where p.active), '[]'::jsonb),
    'premium_prices', coalesce((select jsonb_object_agg(x.currency, x.amount) from public.roa_premium_prices x), '{}'::jsonb),
    'deals', coalesce((select jsonb_agg(jsonb_build_object('item', s.item_id,
                         'coins', public.roa_deal_price(v_uid, s.item_id, s.price_coins),
                         'gems', public.roa_deal_price(v_uid, s.item_id, s.price_gems),
                         'old_coins', s.price_coins, 'old_gems', s.price_gems)
                                          order by md5(s.item_id || current_date::text || v_uid::text))
                         from public.roa_shop s join public.roa_items i on i.id = s.item_id
                        where s.active and i.active and public.roa_is_deal(v_uid, s.item_id)), '[]'::jsonb),
    'deal_off', public.roa_deal_off(),
    'deals_end', date_trunc('day', now()) + interval '1 day',
    'gift_today', coalesce(v_daily.gift, false),
    'gift_coins', public.roa_gift_coins(),
    'coin_packs', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'coins', c.coins, 'gems', c.price_gems)
                                              order by c.sort, c.coins)
                              from public.roa_coin_packs c where c.active), '[]'::jsonb),
    'skip_gems', public.roa_skip_gems(),
    'bot_games_today', coalesce(v_daily.bot_games, 0),
    'bot_daily', public.roa_bot_daily(),
    'prizes', jsonb_build_object(
      'ranked_win', public.roa_match_prize('ranked', true), 'ranked_loss', public.roa_match_prize('ranked', false),
      'bots_win', public.roa_match_prize('bots', true), 'bots_loss', public.roa_match_prize('bots', false))
  );
end;
$fn$;

-- Entrega un premio del pase (sin revisar nada: lo usan las funciones de abajo).
create or replace function public.roa_give_reward(p_user uuid, p_season text, p_tier integer, p_track text)
returns boolean
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_reward public.roa_season_rewards;
begin
  select * into v_reward from public.roa_season_rewards
   where season_id = p_season and tier = p_tier and track = p_track;
  if v_reward.tier is null then
    return false;
  end if;
  insert into public.roa_season_claims (user_id, season_id, tier, track)
  values (p_user, p_season, p_tier, p_track)
  on conflict do nothing;
  if not found then
    return false;
  end if;
  if v_reward.kind = 'coins' then
    update public.roa_profiles set coins = coins + v_reward.amount, updated_at = now() where id = p_user;
  elsif v_reward.kind = 'gems' then
    update public.roa_profiles set gems = gems + v_reward.amount, updated_at = now() where id = p_user;
  else
    insert into public.roa_owned (user_id, item_id, source)
    values (p_user, v_reward.item_id, 'pase ' || p_season || ' nivel ' || p_tier || ' ' || p_track)
    on conflict do nothing;
  end if;
  return true;
end;
$fn$;

-- Reclamar un premio del pase ('free' o 'premium').
create or replace function public.roa_claim(p_tier integer, p_track text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_season public.roa_seasons;
  v_prog public.roa_season_progress;
begin
  if v_uid is null then
    raise exception 'Sin sesión';
  end if;
  v_season := public.roa_current_season();
  if v_season.id is null then
    raise exception 'No hay temporada en curso';
  end if;
  select * into v_prog from public.roa_season_progress where user_id = v_uid and season_id = v_season.id;
  if not exists (select 1 from public.roa_season_rewards
                  where season_id = v_season.id and tier = p_tier and track = p_track) then
    raise exception 'Ese premio no existe';
  end if;
  if coalesce(v_prog.xp, 0) < p_tier * v_season.tier_xp then
    raise exception 'Aún no llegas a ese nivel del pase';
  end if;
  if p_track = 'premium' and not coalesce(v_prog.premium, false) then
    raise exception 'Necesitas el Game Pass Premium';
  end if;
  if not public.roa_give_reward(v_uid, v_season.id, p_tier, p_track) then
    raise exception 'Ya lo reclamaste';
  end if;
  return public.roa_status();
end;
$fn$;

-- Reclamar todo lo alcanzado de una vez.
create or replace function public.roa_claim_all()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_season public.roa_seasons;
  v_prog public.roa_season_progress;
  v_r record;
begin
  if v_uid is null then
    raise exception 'Sin sesión';
  end if;
  v_season := public.roa_current_season();
  if v_season.id is null then
    raise exception 'No hay temporada en curso';
  end if;
  select * into v_prog from public.roa_season_progress where user_id = v_uid and season_id = v_season.id;
  for v_r in
    select r.tier, r.track from public.roa_season_rewards r
     where r.season_id = v_season.id
       and r.tier * v_season.tier_xp <= coalesce(v_prog.xp, 0)
       and (r.track = 'free' or coalesce(v_prog.premium, false))
     order by r.tier
  loop
    perform public.roa_give_reward(v_uid, v_season.id, v_r.tier, v_r.track);
  end loop;
  return public.roa_status();
end;
$fn$;

-- El Game Pass Premium se paga con dinero: ya no existe la compra con gemas.
drop function if exists public.roa_buy_premium();

-- Solo el servidor, antes de cobrar: temporada en curso y precio del Premium en esa
-- moneda (si no hay, USD). 'owned' = ya lo tiene (no se le cobra otra vez).
create or replace function public.roa_premium_price(p_user uuid, p_currency text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_season public.roa_seasons;
  v_price public.roa_premium_prices;
begin
  v_season := public.roa_current_season();
  if v_season.id is null then
    return jsonb_build_object('error', 'No hay temporada en curso');
  end if;
  if exists (select 1 from public.roa_season_progress
              where user_id = p_user and season_id = v_season.id and premium) then
    return jsonb_build_object('error', 'Ya tienes el Game Pass Premium');
  end if;
  select * into v_price from public.roa_premium_prices where currency = upper(coalesce(p_currency, ''));
  if v_price.currency is null then
    select * into v_price from public.roa_premium_prices where currency = 'USD';
  end if;
  if v_price.currency is null then
    return jsonb_build_object('error', 'No hay precio para el Premium');
  end if;
  return jsonb_build_object('season', v_season.id, 'name', v_season.name,
                            'currency', v_price.currency, 'amount', v_price.amount);
end;
$fn$;

-- Solo el servidor, después de que Stripe (o la tienda del celular) confirma el pago:
-- activa el Premium de esa temporada. El mismo pago no se entrega dos veces.
create or replace function public.roa_grant_premium(
  p_user uuid, p_season text, p_provider text, p_ref text, p_amount numeric, p_currency text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_had boolean;
begin
  if not exists (select 1 from public.roa_seasons where id = p_season) then
    return jsonb_build_object('ok', false, 'error', 'temporada desconocida');
  end if;
  insert into public.kodyn_purchases (game, user_id, product, provider, provider_ref, amount, currency, detail)
  values ('rise_of_ages', p_user, 'premium', p_provider, p_ref, p_amount, upper(p_currency),
          jsonb_build_object('season', p_season))
  on conflict (provider, provider_ref) do nothing;
  if not found then
    return jsonb_build_object('ok', true, 'duplicate', true);
  end if;
  insert into public.roa_profiles (id) values (p_user) on conflict (id) do nothing;
  insert into public.roa_season_progress (user_id, season_id) values (p_user, p_season)
  on conflict (user_id, season_id) do nothing;
  select premium into v_had from public.roa_season_progress where user_id = p_user and season_id = p_season;
  if v_had then
    -- Pagó dos veces (por ejemplo, dos pestañas): queda registrado para revisarlo y reembolsar.
    return jsonb_build_object('ok', true, 'note', 'ya lo tenía: revisar y reembolsar');
  end if;
  update public.roa_season_progress set premium = true, updated_at = now()
   where user_id = p_user and season_id = p_season;
  return jsonb_build_object('ok', true, 'premium', true);
end;
$fn$;

-- Comprar un artículo de la tienda (con monedas o gemas, según su precio).
create or replace function public.roa_buy_item(p_item text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_shop public.roa_shop;
  v_price integer;
begin
  if v_uid is null then
    raise exception 'Sin sesión';
  end if;
  select s.* into v_shop from public.roa_shop s join public.roa_items i on i.id = s.item_id
   where s.item_id = p_item and s.active and i.active;
  if v_shop.item_id is null then
    raise exception 'Ese artículo no está a la venta';
  end if;
  if public.roa_owns(v_uid, p_item) then
    raise exception 'Ya lo tienes';
  end if;
  insert into public.roa_profiles (id) values (v_uid) on conflict (id) do nothing;
  if v_shop.price_coins is not null then
    v_price := public.roa_deal_price(v_uid, p_item, v_shop.price_coins);
    update public.roa_profiles set coins = coins - v_price, updated_at = now()
     where id = v_uid and coins >= v_price;
    if not found then
      raise exception 'No te alcanzan las monedas';
    end if;
  else
    v_price := public.roa_deal_price(v_uid, p_item, v_shop.price_gems);
    update public.roa_profiles set gems = gems - v_price, updated_at = now()
     where id = v_uid and gems >= v_price;
    if not found then
      raise exception 'No te alcanzan las gemas';
    end if;
  end if;
  insert into public.roa_owned (user_id, item_id, source) values (v_uid, p_item, 'tienda');
  return public.roa_status();
end;
$fn$;

-- Regalo del día: unas monedas gratis, una vez por día.
create or replace function public.roa_daily_gift()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Sin sesión';
  end if;
  insert into public.roa_daily (user_id, day) values (v_uid, current_date) on conflict (user_id, day) do nothing;
  update public.roa_daily set gift = true where user_id = v_uid and day = current_date and not gift;
  if not found then
    raise exception 'Ya reclamaste el regalo de hoy';
  end if;
  insert into public.roa_profiles (id) values (v_uid) on conflict (id) do nothing;
  update public.roa_profiles set coins = coins + public.roa_gift_coins(), updated_at = now() where id = v_uid;
  return public.roa_status();
end;
$fn$;

-- Comprar un paquete de monedas con gemas.
create or replace function public.roa_buy_coins(p_pack text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_pack public.roa_coin_packs;
begin
  if v_uid is null then
    raise exception 'Sin sesión';
  end if;
  select * into v_pack from public.roa_coin_packs where id = p_pack and active;
  if v_pack.id is null then
    raise exception 'Ese paquete no está a la venta';
  end if;
  insert into public.roa_profiles (id) values (v_uid) on conflict (id) do nothing;
  update public.roa_profiles set gems = gems - v_pack.price_gems, coins = coins + v_pack.coins, updated_at = now()
   where id = v_uid and gems >= v_pack.price_gems;
  if not found then
    raise exception 'No te alcanzan las gemas';
  end if;
  return public.roa_status();
end;
$fn$;

-- Saltar un nivel del pase con gemas: llega justo al inicio del siguiente nivel.
create or replace function public.roa_skip_tier()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_season public.roa_seasons;
  v_xp integer;
  v_tier integer;
begin
  if v_uid is null then
    raise exception 'Sin sesión';
  end if;
  v_season := public.roa_current_season();
  if v_season.id is null then
    raise exception 'No hay temporada en curso';
  end if;
  insert into public.roa_season_progress (user_id, season_id) values (v_uid, v_season.id)
  on conflict (user_id, season_id) do nothing;
  select xp into v_xp from public.roa_season_progress where user_id = v_uid and season_id = v_season.id for update;
  v_tier := least(v_season.tiers, v_xp / v_season.tier_xp);
  if v_tier >= v_season.tiers then
    raise exception 'Ya estás en el último nivel del pase';
  end if;
  insert into public.roa_profiles (id) values (v_uid) on conflict (id) do nothing;
  update public.roa_profiles set gems = gems - public.roa_skip_gems(), updated_at = now()
   where id = v_uid and gems >= public.roa_skip_gems();
  if not found then
    raise exception 'No te alcanzan las gemas';
  end if;
  update public.roa_season_progress set xp = (v_tier + 1) * v_season.tier_xp, updated_at = now()
   where user_id = v_uid and season_id = v_season.id;
  return public.roa_status();
end;
$fn$;

-- Ponerse una imagen, estandarte o título ('' = quitarlo).
create or replace function public.roa_equip(p_kind text, p_item text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_item text := coalesce(p_item, '');
begin
  if v_uid is null then
    raise exception 'Sin sesión';
  end if;
  if p_kind not in ('imagen', 'estandarte', 'titulo') then
    raise exception 'No se puede equipar eso';
  end if;
  if v_item <> '' and (not public.roa_owns(v_uid, v_item)
                       or not exists (select 1 from public.roa_items where id = v_item and kind = p_kind)) then
    raise exception 'No lo tienes';
  end if;
  insert into public.roa_profiles (id) values (v_uid) on conflict (id) do nothing;
  update public.roa_profiles
     set image = case when p_kind = 'imagen' then v_item else image end,
         banner = case when p_kind = 'estandarte' then v_item else banner end,
         title = case when p_kind = 'titulo' then v_item else title end,
         updated_at = now()
   where id = v_uid;
  return public.roa_status();
end;
$fn$;

-- Premio de una partida contra bots (la pide el juego al terminar).
-- Tope por día, partida de al menos roa_bot_minutes() minutos de juego y no más
-- seguido que eso entre una y otra (así no se puede inflar).
create or replace function public.roa_bot_result(p_won boolean, p_seconds integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_row public.roa_daily;
  v_min integer := public.roa_bot_minutes();
  v_out jsonb;
begin
  if v_uid is null then
    raise exception 'Sin sesión';
  end if;
  if coalesce(p_seconds, 0) < v_min * 60 then
    return jsonb_build_object('ok', false, 'why', 'short');
  end if;
  insert into public.roa_daily (user_id, day) values (v_uid, current_date) on conflict (user_id, day) do nothing;
  select * into v_row from public.roa_daily where user_id = v_uid and day = current_date for update;
  if v_row.bot_games >= public.roa_bot_daily() then
    return jsonb_build_object('ok', false, 'why', 'limit');
  end if;
  if v_row.last_bot_at is not null and now() - v_row.last_bot_at < make_interval(mins => v_min) then
    return jsonb_build_object('ok', false, 'why', 'soon');
  end if;
  update public.roa_daily set bot_games = bot_games + 1, last_bot_at = now()
   where user_id = v_uid and day = current_date;
  v_out := public.roa_award(v_uid, 'bots', coalesce(p_won, false));
  return v_out || jsonb_build_object('ok', true, 'left', public.roa_bot_daily() - v_row.bot_games - 1);
end;
$fn$;

-- Solo el servidor: ¿puede usar esta civilización en una partida con rango?
create or replace function public.roa_can_use_civ(p_user uuid, p_civ text)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select not exists (select 1 from public.roa_items i
                      where i.kind = 'civ' and i.detail->>'civ' = p_civ and not i.free
                        and not exists (select 1 from public.roa_owned o where o.user_id = p_user and o.item_id = i.id));
$fn$;

-- Solo el servidor, después de que Stripe confirma el pago: entrega un paquete de gemas.
-- Si el mismo pago llega dos veces, no entrega dos veces.
create or replace function public.roa_grant_gems(
  p_user uuid, p_pack text, p_provider text, p_ref text, p_amount numeric, p_currency text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_pack public.roa_gem_packs;
  v_total integer;
begin
  select * into v_pack from public.roa_gem_packs where id = p_pack;
  if v_pack.id is null then
    return jsonb_build_object('ok', false, 'error', 'paquete desconocido');
  end if;
  v_total := v_pack.gems + v_pack.bonus;
  insert into public.kodyn_purchases (game, user_id, product, provider, provider_ref, amount, currency, detail)
  values ('rise_of_ages', p_user, p_pack, p_provider, p_ref, p_amount, upper(p_currency),
          jsonb_build_object('gems', v_total))
  on conflict (provider, provider_ref) do nothing;
  if not found then
    return jsonb_build_object('ok', true, 'duplicate', true);
  end if;
  insert into public.roa_profiles (id) values (p_user) on conflict (id) do nothing;
  update public.roa_profiles set gems = gems + v_total, updated_at = now() where id = p_user;
  return jsonb_build_object('ok', true, 'gems', v_total);
end;
$fn$;

-- Solo el servidor: precio de un paquete en una moneda (si no hay, en USD).
create or replace function public.roa_pack_price(p_pack text, p_currency text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  select jsonb_build_object('pack', p.id, 'gems', p.gems + p.bonus, 'currency', x.currency, 'amount', x.amount)
    from public.roa_gem_packs p
    join public.roa_gem_prices x on x.pack_id = p.id
   where p.id = p_pack and p.active
     and x.currency = coalesce((select y.currency from public.roa_gem_prices y
                                 where y.pack_id = p.id and y.currency = upper(coalesce(p_currency, ''))), 'USD');
$fn$;

-- El perfil (roa_profile_json, de esquema.sql) ahora también trae monedero y lo equipado.
create or replace function public.roa_profile_json(p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  select jsonb_build_object(
    'id', r.id,
    'name', coalesce(k.name, 'Jugador'),
    'points', r.points,
    'level', public.roa_level(r.points),
    'games', r.games,
    'wins', r.wins,
    'losses', r.losses,
    'coins', r.coins,
    'gems', r.gems,
    'title', r.title,
    'image', r.image,
    'banner', r.banner,
    'zombie_war', public.roa_played_zombie_war(r.id))
  from public.roa_profiles r
  left join public.kodyn_profiles k on k.id = r.id
  where r.id = p_user;
$fn$;

revoke all on function public.roa_current_season() from public, anon, authenticated;
revoke all on function public.roa_award(uuid, text, boolean) from public, anon, authenticated;
revoke all on function public.roa_owns(uuid, text) from public, anon, authenticated;
revoke all on function public.roa_give_reward(uuid, text, integer, text) from public, anon, authenticated;
revoke all on function public.roa_can_use_civ(uuid, text) from public, anon, authenticated;
revoke all on function public.roa_grant_gems(uuid, text, text, text, numeric, text) from public, anon, authenticated;
revoke all on function public.roa_pack_price(text, text) from public, anon, authenticated;
revoke all on function public.roa_status() from public, anon;
revoke all on function public.roa_claim(integer, text) from public, anon;
revoke all on function public.roa_claim_all() from public, anon;
revoke all on function public.roa_premium_price(uuid, text) from public, anon, authenticated;
revoke all on function public.roa_grant_premium(uuid, text, text, text, numeric, text) from public, anon, authenticated;
revoke all on function public.roa_buy_item(text) from public, anon;
revoke all on function public.roa_equip(text, text) from public, anon;
revoke all on function public.roa_bot_result(boolean, integer) from public, anon;
revoke all on function public.roa_profile_json(uuid) from public, anon, authenticated;
revoke all on function public.roa_is_deal(uuid, text) from public, anon, authenticated;
revoke all on function public.roa_deal_price(uuid, text, integer) from public, anon, authenticated;
revoke all on function public.roa_daily_gift() from public, anon;
revoke all on function public.roa_buy_coins(text) from public, anon;
revoke all on function public.roa_skip_tier() from public, anon;
grant execute on function public.roa_daily_gift() to authenticated;
grant execute on function public.roa_buy_coins(text) to authenticated;
grant execute on function public.roa_skip_tier() to authenticated;
grant execute on function public.roa_award(uuid, text, boolean) to service_role;
grant execute on function public.roa_can_use_civ(uuid, text) to service_role;
grant execute on function public.roa_grant_gems(uuid, text, text, text, numeric, text) to service_role;
grant execute on function public.roa_pack_price(text, text) to service_role;
grant execute on function public.roa_status() to authenticated;
grant execute on function public.roa_claim(integer, text) to authenticated;
grant execute on function public.roa_claim_all() to authenticated;
grant execute on function public.roa_premium_price(uuid, text) to service_role;
grant execute on function public.roa_grant_premium(uuid, text, text, text, numeric, text) to service_role;
grant execute on function public.roa_buy_item(text) to authenticated;
grant execute on function public.roa_equip(text, text) to authenticated;
grant execute on function public.roa_bot_result(boolean, integer) to authenticated;

-- =====================================================================================
-- Contenido inicial (se puede volver a ejecutar: no duplica)
-- =====================================================================================

-- Imágenes de perfil: los aldeanos que ya tienen arte. La maya nivel 1 es de todos.
insert into public.roa_items (id, kind, name, detail, rarity, free)
select 'img_' || c || '_' || n, 'imagen',
       'Aldeano ' || c || ' ' || n,
       jsonb_build_object('file', 'civs/' || c || '/unidades/aldeano/nivel' || n || '.png'),
       case when n >= 5 then 'legendario' when n >= 4 then 'epico' when n >= 2 then 'raro' else 'comun' end,
       c = 'maya' and n = 1
  from unnest(array['maya', 'humano', 'orco']) as c, generate_series(1, 5) as n
on conflict (id) do nothing;

-- Estandartes (fondo de la tarjeta de perfil). El de barro es de todos.
insert into public.roa_items (id, kind, name, detail, rarity, free) values
  ('est_barro', 'estandarte', 'Barro', '{"bg": "#4a2f1c", "edge": "#c9a36a", "mark": "#c9a36a"}', 'comun', true),
  ('est_selva', 'estandarte', 'Selva', '{"bg": "#1f4d2b", "edge": "#9fdc6a", "mark": "#e8d27a"}', 'comun', false),
  ('est_tierra', 'estandarte', 'Tierra roja', '{"bg": "#7a2e16", "edge": "#f0a050", "mark": "#ffd08a"}', 'raro', false),
  ('est_oro', 'estandarte', 'Oro del sol', '{"bg": "#8a5a10", "edge": "#ffe08a", "mark": "#fff2c0"}', 'epico', false),
  ('est_obsidiana', 'estandarte', 'Obsidiana', '{"bg": "#15141c", "edge": "#9a7cff", "mark": "#c9b8ff"}', 'epico', false),
  ('est_quetzal', 'estandarte', 'Quetzal', '{"bg": "#0d5a5a", "edge": "#5fffd0", "mark": "#ffe066"}', 'legendario', false),
  ('est_rojo', 'estandarte', 'Rojo guerrero', '{"bg": "#8a1414", "edge": "#ffcf5a", "mark": "#ffcf5a"}', 'comun', false),
  ('est_azul', 'estandarte', 'Azul maya', '{"bg": "#14467a", "edge": "#7fd0ff", "mark": "#e8f6ff"}', 'comun', false),
  ('est_noche', 'estandarte', 'Noche estrellada', '{"bg": "#101a3c", "edge": "#ffd75a", "mark": "#fff3b0"}', 'raro', false),
  ('est_jaguar', 'estandarte', 'Jaguar', '{"bg": "#b0700f", "edge": "#2a1606", "mark": "#2a1606"}', 'epico', false),
  ('est_jade', 'estandarte', 'Jade real', '{"bg": "#1d6b45", "edge": "#ffd75a", "mark": "#c8ffe0"}', 'legendario', false)
on conflict (id) do nothing;

-- Títulos (el nombre del artículo es el título).
insert into public.roa_items (id, kind, name, rarity) values
  ('tit_recolector', 'titulo', 'Recolector', 'comun'),
  ('tit_constructor', 'titulo', 'Constructor', 'comun'),
  ('tit_cacique', 'titulo', 'Cacique', 'raro'),
  ('tit_senor_guerra', 'titulo', 'Señor de la guerra', 'epico'),
  ('tit_leyenda_t1', 'titulo', 'Leyenda de la temporada 1', 'legendario'),
  ('tit_veterano_t1', 'titulo', 'Veterano de la temporada 1', 'raro'),
  ('tit_comerciante', 'titulo', 'Comerciante', 'comun'),
  ('tit_rey_maiz', 'titulo', 'Rey del maíz', 'raro'),
  ('tit_hijo_sol', 'titulo', 'Hijo del sol', 'epico')
on conflict (id) do nothing;

-- Tienda inicial.
insert into public.roa_shop (item_id, price_coins, price_gems, sort) values
  ('est_rojo', 800, null, 1),
  ('est_azul', 800, null, 2),
  ('tit_comerciante', 500, null, 3),
  ('tit_rey_maiz', 1500, null, 4),
  ('est_noche', null, 150, 5),
  ('est_jaguar', null, 300, 6),
  ('tit_hijo_sol', null, 200, 7),
  ('est_jade', null, 600, 8),
  ('img_maya_4', null, 250, 9)
on conflict (item_id) do nothing;

-- Paquetes de gemas y sus precios.
insert into public.roa_gem_packs (id, gems, bonus, sort) values
  ('gemas_100', 100, 0, 1),
  ('gemas_500', 500, 50, 2),
  ('gemas_1000', 1000, 200, 3),
  ('gemas_2000', 2000, 600, 4),
  ('gemas_5000', 5000, 2000, 5),
  ('gemas_10000', 10000, 5000, 6)
on conflict (id) do nothing;
insert into public.roa_coin_packs (id, coins, price_gems, sort) values
  ('monedas_1000', 1000, 60, 1),
  ('monedas_10000', 10000, 500, 2),
  ('monedas_100000', 100000, 4500, 3)
on conflict (id) do nothing;
insert into public.roa_gem_prices (pack_id, currency, amount) values
  ('gemas_100', 'USD', 0.99), ('gemas_500', 'USD', 4.99), ('gemas_1000', 'USD', 9.99), ('gemas_2000', 'USD', 19.99),
  ('gemas_100', 'MXN', 19), ('gemas_500', 'MXN', 99), ('gemas_1000', 'MXN', 199), ('gemas_2000', 'MXN', 399),
  ('gemas_100', 'EUR', 0.99), ('gemas_500', 'EUR', 4.99), ('gemas_1000', 'EUR', 9.99), ('gemas_2000', 'EUR', 19.99),
  ('gemas_100', 'BRL', 4.90), ('gemas_500', 'BRL', 24.90), ('gemas_1000', 'BRL', 49.90), ('gemas_2000', 'BRL', 99.90),
  ('gemas_100', 'COP', 3900), ('gemas_500', 'COP', 19900), ('gemas_1000', 'COP', 39900), ('gemas_2000', 'COP', 79900),
  ('gemas_5000', 'USD', 49.99), ('gemas_10000', 'USD', 99.99), ('gemas_5000', 'MXN', 999), ('gemas_10000', 'MXN', 1999),
  ('gemas_5000', 'EUR', 49.99), ('gemas_10000', 'EUR', 99.99), ('gemas_5000', 'BRL', 249.90), ('gemas_10000', 'BRL', 499.90),
  ('gemas_5000', 'COP', 199900), ('gemas_10000', 'COP', 399900)
on conflict (pack_id, currency) do nothing;

-- Precio del Game Pass Premium (dinero real).
insert into public.roa_premium_prices (currency, amount) values
  ('USD', 4.99), ('MXN', 99), ('EUR', 4.99), ('BRL', 24.90), ('COP', 19900)
on conflict (currency) do nothing;

-- Temporada 1: empieza el día que corres este archivo y dura 8 semanas, 50 niveles de 500 xp.
insert into public.roa_seasons (id, name, starts_at, ends_at)
values ('t1', 'Temporada 1: El despertar del sol', date_trunc('day', now()), date_trunc('day', now()) + interval '56 days')
on conflict (id) do nothing;

-- Fila gratis (niveles pares): monedas, unas gemas, títulos, imágenes y estandartes.
insert into public.roa_season_rewards (season_id, tier, track, kind, item_id, amount)
select 't1', g, 'free',
       case when g in (6, 12, 16, 26, 36, 46, 50) then 'item' when g in (10, 20, 30, 40) then 'gems' else 'coins' end,
       case g when 6 then 'tit_recolector' when 12 then 'img_maya_2' when 16 then 'est_selva'
              when 26 then 'tit_constructor' when 36 then 'img_maya_3' when 46 then 'est_tierra'
              when 50 then 'tit_veterano_t1' end,
       case when g in (10, 20, 30, 40) then 25 when g in (6, 12, 16, 26, 36, 46, 50) then 0 else 100 end
  from generate_series(2, 50, 2) as g
on conflict do nothing;

-- Fila premium (todos los niveles): más monedas, gemas que regresan, imágenes de
-- humano y orco, estandartes, títulos y la maya legendaria al final.
insert into public.roa_season_rewards (season_id, tier, track, kind, item_id, amount)
select 't1', g, 'premium',
       case when g in (1, 3, 8, 10, 13, 18, 22, 23, 28, 30, 33, 38, 42, 43, 48, 49, 50) then 'item'
            when g in (15, 25, 35, 45) then 'gems' else 'coins' end,
       case g when 1 then 'est_oro' when 3 then 'img_humano_1' when 8 then 'img_orco_1'
              when 10 then 'tit_cacique' when 13 then 'img_humano_2' when 18 then 'img_orco_2'
              when 22 then 'est_obsidiana' when 23 then 'img_humano_3' when 28 then 'img_orco_3'
              when 30 then 'tit_senor_guerra' when 33 then 'img_humano_4' when 38 then 'img_orco_4'
              when 42 then 'est_quetzal' when 43 then 'img_humano_5' when 48 then 'img_orco_5'
              when 49 then 'tit_leyenda_t1' when 50 then 'img_maya_5' end,
       case when g in (15, 25, 35, 45) then 100
            when g in (1, 3, 8, 10, 13, 18, 22, 23, 28, 30, 33, 38, 42, 43, 48, 49, 50) then 0
            when g % 5 = 0 then 300 else 150 end
  from generate_series(1, 50) as g
on conflict do nothing;
