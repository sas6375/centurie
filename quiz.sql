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
