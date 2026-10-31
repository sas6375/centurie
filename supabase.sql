-- Centurie : base du test en famille
-- À coller dans Supabase > SQL Editor > New query, puis « Run ». Une seule fois.
-- Principe : chacun voit ses propres pronos ; ceux des autres deviennent visibles
-- seulement après la clôture de la question (règle appliquée par la base elle-même).

-- 1. Questions et heures de clôture (heure de Paris = UTC+1)
create table if not exists public.questions (
  id int primary key,
  closes_at timestamptz not null
);
insert into public.questions (id, closes_at) values
  (1,  '2026-10-30 19:00+01'),
  (2,  '2026-10-29 13:00+01'),
  (3,  '2026-10-31 22:00+01'),
  (4,  '2026-10-30 10:00+01'),
  (5,  '2026-11-01 21:00+01'),
  (6,  '2026-11-01 21:00+01'),
  (7,  '2026-10-30 22:00+01'),
  (8,  '2026-10-31 22:00+01'),
  (9,  '2026-10-29 22:00+01'),
  (10, '2026-10-30 20:00+01'),
  (11, '2026-10-29 22:00+01'),
  (12, '2026-11-02 22:00+01'),
  (13, '2026-10-30 20:00+01'),
  (14, '2026-10-30 20:00+01'),
  (15, '2026-10-29 22:00+01'),
  (16, '2026-10-29 22:00+01')
on conflict (id) do update set closes_at = excluded.closes_at;

-- 2. Joueurs (3 initiales, une par appareil)
create table if not exists public.players (
  user_id uuid primary key default auth.uid() references auth.users on delete cascade,
  initials text not null unique check (initials ~ '^[A-Z]{3}$'),
  created_at timestamptz not null default now()
);

-- 3. Pronostics
create table if not exists public.predictions (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  question_id int not null references public.questions,
  option smallint not null check (option between 0 and 3),
  stake int not null check (stake in (50, 100, 250)),
  updated_at timestamptz not null default now(),
  primary key (user_id, question_id)
);

-- 4. Résultats (saisis par l'administrateur)
create table if not exists public.results (
  question_id int primary key references public.questions,
  outcome text not null check (outcome in ('0','1','2','3','x')),
  set_at timestamptz not null default now()
);

-- 5. Administrateurs
create table if not exists public.admins (
  user_id uuid primary key references auth.users on delete cascade
);

alter table public.questions   enable row level security;
alter table public.players     enable row level security;
alter table public.predictions enable row level security;
alter table public.results     enable row level security;
alter table public.admins      enable row level security;

-- Questions et résultats : lisibles par tous
create policy "questions lisibles" on public.questions for select using (true);
create policy "resultats lisibles" on public.results for select using (true);
create policy "resultats admin" on public.results for all
  using (exists (select 1 from public.admins a where a.user_id = auth.uid()))
  with check (exists (select 1 from public.admins a where a.user_id = auth.uid()));
create policy "admin se voit" on public.admins for select using (user_id = auth.uid());

-- Joueurs : initiales visibles par tous, chacun gère sa ligne
create policy "joueurs lisibles" on public.players for select using (true);
create policy "joueur cree sa ligne" on public.players for insert with check (user_id = auth.uid());
create policy "joueur modifie sa ligne" on public.players for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Pronostics : les miens toujours, ceux des autres seulement après la clôture
create policy "pronos visibles" on public.predictions for select using (
  user_id = auth.uid()
  or exists (select 1 from public.questions q where q.id = question_id and q.closes_at <= now())
);
create policy "prono avant cloture (ajout)" on public.predictions for insert with check (
  user_id = auth.uid()
  and exists (select 1 from public.questions q where q.id = question_id and q.closes_at > now())
);
create policy "prono avant cloture (modif)" on public.predictions for update
  using (user_id = auth.uid() and exists (select 1 from public.questions q where q.id = question_id and q.closes_at > now()))
  with check (user_id = auth.uid() and exists (select 1 from public.questions q where q.id = question_id and q.closes_at > now()));
create policy "prono avant cloture (retrait)" on public.predictions for delete using (
  user_id = auth.uid() and exists (select 1 from public.questions q where q.id = question_id and q.closes_at > now())
);

-- Budget : 1 500 jetons au total par joueur
create or replace function public.check_budget() returns trigger language plpgsql as $$
begin
  if (select coalesce(sum(stake), 0) from public.predictions
      where user_id = new.user_id and question_id <> new.question_id) + new.stake > 1500 then
    raise exception 'Budget de 1 500 jetons dépassé';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists predictions_budget on public.predictions;
create trigger predictions_budget before insert or update on public.predictions
  for each row execute function public.check_budget();

-- À lancer PLUS TARD, après avoir choisi tes initiales dans le jeu (remplace SAS si besoin) :
-- insert into public.admins (user_id) select user_id from public.players where initials = 'SAS';

-- 6. « Qui a joué » (façon Doodle) : expose seulement joueur + question, jamais la réponse ni la mise
create or replace function public.participation()
returns table (user_id uuid, question_id int)
language sql stable security definer set search_path = public
as $$ select p.user_id, p.question_id from public.predictions p $$;
revoke all on function public.participation() from public;
grant execute on function public.participation() to anon, authenticated;

-- 7. Questions maison créées depuis le site (admin) + question 17
alter table public.questions add column if not exists text text;
alter table public.questions add column if not exists options text[];
alter table public.questions add column if not exists theme text;
alter table public.questions add column if not exists source text;
drop policy if exists "questions admin" on public.questions;
create policy "questions admin" on public.questions for all
  using (exists (select 1 from public.admins a where a.user_id = auth.uid()))
  with check (exists (select 1 from public.admins a where a.user_id = auth.uid()));
insert into public.questions (id, closes_at, text, options, theme, source) values
  (17, '2026-10-30 20:00+01', 'Qui va le plus aider à la maison ce week-end ?',
   array['OSCAR','EVE','CAPUCINE','LÉONARD'], 'MAISON', 'Jury des parents · dim. soir')
on conflict (id) do update set closes_at = excluded.closes_at, text = excluded.text,
  options = excluded.options, theme = excluded.theme, source = excluded.source;

-- 8. Code secret à 4 chiffres pour retrouver son joueur sur un autre appareil
alter table public.players add column if not exists pin text;
revoke select on public.players from anon, authenticated;
grant select (user_id, initials, created_at) on public.players to anon, authenticated;
grant insert (user_id, initials) on public.players to anon, authenticated;
grant update (user_id, initials) on public.players to anon, authenticated;

create or replace function public.set_pin(p text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p !~ '^[0-9]{4}$' then raise exception 'Code invalide'; end if;
  update public.players set pin = crypt(p, gen_salt('bf')) where user_id = auth.uid();
end $$;

create or replace function public.has_pin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select pin is not null from public.players where user_id = auth.uid()), false)
$$;

create or replace function public.claim_player(ini text, p text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare old_id uuid; h text; me uuid := auth.uid();
begin
  select user_id, pin into old_id, h from public.players where initials = upper(ini);
  if old_id is null or h is null or h <> crypt(p, h) then return false; end if;
  if old_id = me then return true; end if;
  delete from public.predictions where user_id = me;
  delete from public.players where user_id = me;
  delete from public.admins where user_id = me;
  update public.predictions set user_id = me where user_id = old_id;
  update public.players set user_id = me where user_id = old_id;
  update public.admins set user_id = me where user_id = old_id;
  return true;
end $$;

revoke all on function public.set_pin(text), public.has_pin(), public.claim_player(text, text) from public;
grant execute on function public.set_pin(text), public.has_pin(), public.claim_player(text, text) to anon, authenticated;
-- 9. Quiz du jour (5 questions, 15 s, réponses cachées côté serveur)
create table if not exists public.quiz (
  id text primary key,            -- date au format AAAA-MM-JJ (heure de Paris)
  title text not null,
  questions jsonb not null        -- [{ "q": "...", "o": ["A","B","C","D"], "src": "..." }]
);
create table if not exists public.quiz_key (
  quiz_id text references public.quiz on delete cascade,
  idx int not null,
  answer int not null,
  explain text,
  primary key (quiz_id, idx)
);
create table if not exists public.quiz_plays (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  quiz_id text not null references public.quiz on delete cascade,
  idx int not null,
  choice int not null,
  ms int not null,
  correct boolean not null,
  points int not null,
  created_at timestamptz not null default now(),
  primary key (user_id, quiz_id, idx)
);
alter table public.quiz enable row level security;
alter table public.quiz_key enable row level security;
alter table public.quiz_plays enable row level security;
drop policy if exists "quiz lisible" on public.quiz;
create policy "quiz lisible" on public.quiz for select using (true);
drop policy if exists "quiz admin" on public.quiz;
create policy "quiz admin" on public.quiz for all
  using (exists (select 1 from public.admins a where a.user_id = auth.uid()))
  with check (exists (select 1 from public.admins a where a.user_id = auth.uid()));
drop policy if exists "cles admin" on public.quiz_key;
create policy "cles admin" on public.quiz_key for all
  using (exists (select 1 from public.admins a where a.user_id = auth.uid()))
  with check (exists (select 1 from public.admins a where a.user_id = auth.uid()));
drop policy if exists "mes reponses" on public.quiz_plays;
create policy "mes reponses" on public.quiz_plays for select using (user_id = auth.uid());

-- Répondre à une question : renvoie la bonne réponse, l'explication et les points
create or replace function public.answer_quiz(qid text, i int, c int, ms int)
returns json language plpgsql security definer set search_path = public as $$
declare k record; ok boolean; pts int; t int := greatest(0, least(ms, 15000));
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  select * into k from public.quiz_key where quiz_id = qid and idx = i;
  if not found then raise exception 'question inconnue'; end if;
  if exists (select 1 from public.quiz_plays where user_id = auth.uid() and quiz_id = qid and idx = i) then
    select correct, points into ok, pts from public.quiz_plays where user_id = auth.uid() and quiz_id = qid and idx = i;
    return json_build_object('correct', ok, 'answer', k.answer, 'explain', k.explain, 'points', pts, 'replay', true);
  end if;
  ok := (c = k.answer and ms <= 15000);
  pts := case when ok then 20 + round(10.0 * (15000 - t) / 15000) else 0 end;
  insert into public.quiz_plays (user_id, quiz_id, idx, choice, ms, correct, points)
  values (auth.uid(), qid, i, c, t, ok, pts);
  return json_build_object('correct', ok, 'answer', k.answer, 'explain', k.explain, 'points', pts, 'replay', false);
end $$;

-- Classement d'un quiz et total des jetons de quiz par joueur (sans révéler les réponses)
create or replace function public.quiz_board(qid text)
returns table (user_id uuid, points int, correct int, answered int)
language sql stable security definer set search_path = public as $$
  select user_id, sum(points)::int, sum(case when correct then 1 else 0 end)::int, count(*)::int
  from public.quiz_plays where quiz_id = qid group by user_id
$$;
create or replace function public.quiz_totals()
returns table (user_id uuid, points int)
language sql stable security definer set search_path = public as $$
  select user_id, sum(points)::int from public.quiz_plays group by user_id
$$;
revoke all on function public.answer_quiz(text,int,int,int), public.quiz_board(text), public.quiz_totals() from public;
grant execute on function public.answer_quiz(text,int,int,int), public.quiz_board(text), public.quiz_totals() to anon, authenticated;

-- Budget de mises = 1 500 + jetons gagnés au quiz
create or replace function public.check_budget() returns trigger language plpgsql as $$
begin
  if (select coalesce(sum(stake), 0) from public.predictions
      where user_id = new.user_id and question_id <> new.question_id) + new.stake
     > 1500 + (select coalesce(sum(points), 0) from public.quiz_plays where user_id = new.user_id) then
    raise exception 'Budget de jetons dépassé';
  end if;
  new.updated_at := now();
  return new;
end $$;

-- Premier quiz : l'actu de la semaine (jouable le 31 octobre)
insert into public.quiz (id, title, questions) values ('2026-10-31', 'L''actu de la semaine', '[
 {"q":"Qui préside la Réserve fédérale américaine, qui a laissé ses taux inchangés mercredi ?","o":["Jerome Powell","Kevin Warsh","Janet Yellen","Christopher Waller"],"src":"Boursorama, 28/10"},
 {"q":"Christine Lagarde a annoncé qu''elle quitterait la présidence de la BCE…","o":["En décembre","En février","À la fin de son mandat, en 2027","Elle reste en poste"],"src":"Euronews, 29/10"},
 {"q":"Le Havre – PSG (1-5) vendredi : quel Parisien a signé un triplé ?","o":["Ousmane Dembélé","Bradley Barcola","Achraf Hakimi","Désiré Doué"],"src":"VAVEL, 30/10"},
 {"q":"Quel champion a déclaré forfait pour le Rolex Paris Masters, blessé au genou ?","o":["Carlos Alcaraz","Jannik Sinner","Alexander Zverev","Novak Djokovic"],"src":"Wikipédia, Paris Masters 2026"},
 {"q":"Quelle est la date de sortie confirmée de GTA VI ?","o":["1er octobre 2026","19 novembre 2026","25 décembre 2026","26 mars 2027"],"src":"Jeux.com, oct. 2026"}
]'::jsonb) on conflict (id) do update set title = excluded.title, questions = excluded.questions;
insert into public.quiz_key (quiz_id, idx, answer, explain) values
 ('2026-10-31', 0, 1, 'Kevin Warsh a succédé à Jerome Powell à la tête de la Fed.'),
 ('2026-10-31', 1, 1, 'Elle partira en février, avant la fin de son mandat prévue en octobre 2027.'),
 ('2026-10-31', 2, 2, 'Achraf Hakimi a marqué trois fois au stade Océane.'),
 ('2026-10-31', 3, 1, 'Jannik Sinner, tenant du titre, s''est retiré à cause du genou droit.'),
 ('2026-10-31', 4, 1, 'Take-Two a confirmé le 19 novembre 2026.')
on conflict (quiz_id, idx) do update set answer = excluded.answer, explain = excluded.explain;
