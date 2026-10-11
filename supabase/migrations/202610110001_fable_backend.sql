-- Fable's first production schema. Apply in Supabase SQL editor or with the Supabase CLI.
create extension if not exists pgcrypto;

create table if not exists public.fable_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  profile_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fable_profile_age check (
    case when profile_data ? 'age' then (profile_data->>'age') ~ '^[0-9]{1,2}$' and (profile_data->>'age')::int between 18 and 99 else true end
  )
);

create table if not exists public.fable_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  state jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.fable_legal_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  terms_version text not null,
  privacy_version text not null,
  accepted_at timestamptz not null default now(),
  unique (user_id, terms_version, privacy_version)
);

create table if not exists public.fable_legal_versions (
  id boolean primary key default true check (id),
  terms_version text not null,
  privacy_version text not null,
  updated_at timestamptz not null default now()
);
insert into public.fable_legal_versions(id,terms_version,privacy_version)
values(true,'2026-10-11-v1','2026-10-11-v1') on conflict(id) do update set terms_version=excluded.terms_version,privacy_version=excluded.privacy_version,updated_at=now();

create table if not exists public.fable_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint fable_block_not_self check (blocker_id <> blocked_id)
);

create table if not exists public.fable_suspensions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  suspended_until timestamptz not null,
  reason text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.fable_conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('blind', 'discovery')),
  status text not null default 'active' check (status in ('active', 'ended', 'blocked')),
  reveal_at timestamptz,
  end_requested_by uuid references auth.users(id) on delete set null,
  end_requested_at timestamptz,
  cooldown_until timestamptz,
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

create table if not exists public.fable_conversation_members (
  conversation_id uuid not null references public.fable_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (conversation_id, user_id)
);

create table if not exists public.fable_blind_intros (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  requester_yes boolean not null default true,
  recipient_yes boolean not null default false,
  status text not null default 'pending' check (status in ('pending', 'matched', 'passed', 'expired')),
  conversation_id uuid references public.fable_conversations(id) on delete set null,
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (requester_id, recipient_id, created_at),
  constraint fable_intro_not_self check (requester_id <> recipient_id)
);
create index if not exists fable_intro_inbox_idx on public.fable_blind_intros (recipient_id, status, created_at desc);

create table if not exists public.fable_interest_reactions (
  sender_id uuid not null references auth.users(id) on delete cascade,
  target_id uuid not null references auth.users(id) on delete cascade,
  opener text not null default '',
  status text not null default 'accepted' check (status in ('accepted', 'passed')),
  created_at timestamptz not null default now(),
  primary key (sender_id, target_id),
  constraint fable_interest_not_self check (sender_id <> target_id)
);

create table if not exists public.fable_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.fable_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (length(body) between 1 and 2000),
  ephemeral boolean not null default false,
  created_at timestamptz not null default now(),
  expires_at timestamptz
);
create index if not exists fable_messages_conversation_idx on public.fable_messages (conversation_id, created_at);

create table if not exists public.fable_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid references public.fable_conversations(id) on delete set null,
  reason text not null,
  context jsonb not null default '[]'::jsonb,
  status text not null default 'open' check (status in ('open', 'reviewing', 'dismissed', 'warned', 'suspended', 'escalated')),
  created_at timestamptz not null default now(),
  constraint fable_report_not_self check (reporter_id <> reported_id)
);

create table if not exists public.fable_correction_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  note text not null check (length(note) between 1 and 300),
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'declined')),
  created_at timestamptz not null default now()
);

create table if not exists public.fable_moderator_actions (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.fable_reports(id) on delete cascade,
  moderator_id uuid not null references auth.users(id) on delete cascade,
  action text not null check (action in ('dismissed', 'warned', 'suspended', 'escalated')),
  note text not null default '',
  created_at timestamptz not null default now()
);

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('fable-profile-photos','fable-profile-photos',false,1048576,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false,file_size_limit=1048576,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

create or replace function public.fable_touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end $$;
drop trigger if exists fable_profile_touch on public.fable_profiles;
create trigger fable_profile_touch before update on public.fable_profiles for each row execute function public.fable_touch_updated_at();
drop trigger if exists fable_state_touch on public.fable_state;
create trigger fable_state_touch before update on public.fable_state for each row execute function public.fable_touch_updated_at();

create or replace function public.fable_verified_student(p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from auth.users u where u.id=p_user and u.email_confirmed_at is not null and lower(u.email) like '%@culkomail.in')
$$;

alter table public.fable_profiles enable row level security;
alter table public.fable_legal_versions enable row level security;
alter table public.fable_state enable row level security;
alter table public.fable_legal_acceptances enable row level security;
alter table public.fable_blocks enable row level security;
alter table public.fable_suspensions enable row level security;
alter table public.fable_conversations enable row level security;
alter table public.fable_conversation_members enable row level security;
alter table public.fable_blind_intros enable row level security;
alter table public.fable_interest_reactions enable row level security;
alter table public.fable_messages enable row level security;
alter table public.fable_reports enable row level security;
alter table public.fable_correction_requests enable row level security;
alter table public.fable_moderator_actions enable row level security;

create policy fable_profile_owner_read on public.fable_profiles for select to authenticated using (user_id = (select auth.uid()));
create policy fable_profile_owner_insert on public.fable_profiles for insert to authenticated with check (user_id = (select auth.uid()) and public.fable_verified_student((select auth.uid())) and exists(select 1 from public.fable_legal_acceptances a join public.fable_legal_versions v on a.terms_version=v.terms_version and a.privacy_version=v.privacy_version where a.user_id=(select auth.uid())));
create policy fable_profile_owner_update on public.fable_profiles for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()) and public.fable_verified_student((select auth.uid())) and exists(select 1 from public.fable_legal_acceptances a join public.fable_legal_versions v on a.terms_version=v.terms_version and a.privacy_version=v.privacy_version where a.user_id=(select auth.uid())));
create policy fable_state_owner_all on public.fable_state for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy fable_legal_owner_read on public.fable_legal_acceptances for select to authenticated using (user_id = (select auth.uid()));
create policy fable_block_participant_read on public.fable_blocks for select to authenticated using (blocker_id = (select auth.uid()));
create policy fable_conversation_member_read on public.fable_conversations for select to authenticated using (exists (select 1 from public.fable_conversation_members m where m.conversation_id = id and m.user_id = (select auth.uid())));
create policy fable_members_self_read on public.fable_conversation_members for select to authenticated using (exists (select 1 from public.fable_conversation_members mine where mine.conversation_id = public.fable_conversation_members.conversation_id and mine.user_id = (select auth.uid())));
create policy fable_intro_participant_read on public.fable_blind_intros for select to authenticated using (requester_id = (select auth.uid()) or recipient_id = (select auth.uid()));
create policy fable_reaction_participant_read on public.fable_interest_reactions for select to authenticated using (sender_id = (select auth.uid()) or target_id = (select auth.uid()));
create policy fable_message_member_read on public.fable_messages for select to authenticated using (exists (select 1 from public.fable_conversation_members m join public.fable_conversations c on c.id=m.conversation_id where m.conversation_id=public.fable_messages.conversation_id and m.user_id=(select auth.uid()) and c.status='active'));
create policy fable_report_owner_read on public.fable_reports for select to authenticated using (reporter_id=(select auth.uid()));
create policy fable_correction_owner_read on public.fable_correction_requests for select to authenticated using (user_id=(select auth.uid()));
create policy fable_correction_owner_insert on public.fable_correction_requests for insert to authenticated with check (user_id=(select auth.uid()));
create policy fable_moderator_action_participant_read on public.fable_moderator_actions for select to authenticated using (moderator_id=(select auth.uid()));

create or replace function public.fable_profile(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select profile_data from public.fable_profiles where user_id=p_user
$$;


create or replace function public.fable_public_profile(p_user uuid,p_include_photos boolean default false)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare p jsonb; s jsonb; show_course boolean; show_year boolean; show_photos boolean;
begin
 select profile_data into p from public.fable_profiles where user_id=p_user;
 if p is null then return null; end if;
 select state into s from public.fable_state where user_id=p_user;
 show_course := coalesce((s->'priv'->>'major')::boolean,true);
 show_year := coalesce((s->'priv'->>'year')::boolean,true);
 show_photos := p_include_photos and coalesce((s->'priv'->>'ph')::boolean,true);
 return jsonb_build_object(
   'id',p_user,'firstName',p->>'firstName','n',p->>'firstName','age',p->'age','gender',p->>'gender',
   'course',case when show_course then p->>'course' else null end,'mj',case when show_course then p->>'course' else null end,
   'year',case when show_year then p->>'year' else null end,'yr',case when show_year then p->>'year' else null end,
   'bio',p->>'bio','flex',p->>'flex','interests',coalesce(p->'interests','[]'::jsonb),'int',coalesce(p->'interests','[]'::jsonb),
   'prompts',coalesce(p->'prompts','[]'::jsonb),'intentions',coalesce(p->'intentions','[]'::jsonb),'pets',coalesce(p->'pets','[]'::jsonb),
   'drinking',p->>'drinking','smoking',p->>'smoking','profileComplete',coalesce(p->'profileComplete','0'::jsonb),
   'createdAt',p->>'createdAt','photos',case when show_photos then coalesce(p->'photos','[]'::jsonb) else '[]'::jsonb
 );
end $$;

create or replace function public.fable_can_date(p_a uuid, p_b uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare a jsonb; b jsonb; ga text; gb text; ap text[]; bp text[];
begin
  select profile_data into a from public.fable_profiles where user_id=p_a;
  select profile_data into b from public.fable_profiles where user_id=p_b;
  if a is null or b is null or not public.fable_verified_student(p_a) or not public.fable_verified_student(p_b) then return false; end if;
  if coalesce((a->>'age')::int,0)<18 or coalesce((b->>'age')::int,0)<18 then return false; end if;
  if coalesce((a->>'profileComplete')::int,0)<1 or coalesce((b->>'profileComplete')::int,0)<1 then return false; end if;
  if exists(select 1 from public.fable_blocks x where (x.blocker_id=p_a and x.blocked_id=p_b) or (x.blocker_id=p_b and x.blocked_id=p_a)) then return false; end if;
  if exists(select 1 from public.fable_suspensions x where x.user_id in (p_a,p_b) and x.suspended_until>now()) then return false; end if;
  ga := case b->>'gender' when 'Man' then 'Men' when 'Woman' then 'Women' when 'Non-binary' then 'Non-binary people' else coalesce(b->>'gender','') end;
  gb := case a->>'gender' when 'Man' then 'Men' when 'Woman' then 'Women' when 'Non-binary' then 'Non-binary people' else coalesce(a->>'gender','') end;
  select coalesce(array_agg(value), '{}') into ap from jsonb_array_elements_text(coalesce(a->'datingPreferences','[]'::jsonb));
  select coalesce(array_agg(value), '{}') into bp from jsonb_array_elements_text(coalesce(b->'datingPreferences','[]'::jsonb));
  if cardinality(ap)=0 or cardinality(bp)=0 then return false; end if;
  if not ('Prefer not to say'=any(ap) or 'Everyone'=any(ap) or ga=any(ap) or 'Men & Women'=any(ap) and gb in ('Men','Women')) then return false; end if;
  if not ('Prefer not to say'=any(bp) or 'Everyone'=any(bp) or gb=any(bp) or 'Men & Women'=any(bp) and ga in ('Men','Women')) then return false; end if;
  if not (coalesce(a->'intentions','[]'::jsonb) ?| array(select jsonb_array_elements_text(coalesce(b->'intentions','[]'::jsonb)))) then return false; end if;
  return true;
end $$;

create or replace function public.fable_discover_profiles()
returns setof jsonb language plpgsql stable security definer set search_path = '' as $$
declare me uuid := auth.uid(); mine jsonb;
begin
  if me is null then raise exception 'Sign in required'; end if;
  select profile_data into mine from public.fable_profiles where user_id=me;
  if mine is null or coalesce((mine->>'age')::int,0)<18 then return; end if;
  return query
    select public.fable_public_profile(p.user_id,false) || jsonb_build_object('createdAt',p.created_at)
    from public.fable_profiles p left join public.fable_state s on s.user_id=p.user_id
    where p.user_id<>me and public.fable_can_date(me,p.user_id)
    order by p.created_at desc limit 100;
end $$;

create or replace function public.fable_request_blind_intro()
returns table(intro_id uuid, alias text, status text, conversation_id uuid, shared_interests jsonb)
language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); target uuid; current_intro public.fable_blind_intros%rowtype; day_count int; shared jsonb;
begin
  if me is null then raise exception 'Sign in required'; end if;
  if not exists(select 1 from public.fable_profiles where user_id=me and coalesce((profile_data->>'age')::int,0)>=18 and coalesce((profile_data->>'profileComplete')::int,0)>0) then raise exception 'Complete an adult profile before requesting an introduction'; end if;
  perform pg_advisory_xact_lock(hashtextextended(me::text,0));
  select * into current_intro from public.fable_blind_intros where status='pending' and recipient_id=me order by created_at limit 1;
  if found then
    select coalesce(jsonb_agg(value), '[]'::jsonb) into shared from jsonb_array_elements_text(coalesce((public.fable_profile(me)->'interests'),'[]'::jsonb)) a(value) where value in (select jsonb_array_elements_text(coalesce((public.fable_profile(current_intro.requester_id)->'interests'),'[]'::jsonb)));
    return query select current_intro.id, 'Campus connection', current_intro.status, current_intro.conversation_id, shared; return;
  end if;
  select * into current_intro from public.fable_blind_intros where status='pending' and requester_id=me order by created_at desc limit 1;
  if found then return query select current_intro.id, 'Campus connection', current_intro.status, current_intro.conversation_id, '[]'::jsonb; return; end if;
  select count(*) into day_count from public.fable_blind_intros where requester_id=me and created_at>=date_trunc('day',now());
  if day_count>=4 then return; end if;
  if exists(select 1 from public.fable_conversation_members m join public.fable_conversations c on c.id=m.conversation_id where m.user_id=me and c.status='active' and c.kind='blind') then raise exception 'Finish or end your current blind date first'; end if;
  select p.user_id into target from public.fable_profiles p where p.user_id<>me and public.fable_can_date(me,p.user_id) and not exists(select 1 from public.fable_conversations c join public.fable_conversation_members m on m.conversation_id=c.id where m.user_id=me and c.cooldown_until>now()) and not exists(select 1 from public.fable_blind_intros i where i.status in ('pending','matched') and ((i.requester_id=me and i.recipient_id=p.user_id) or (i.requester_id=p.user_id and i.recipient_id=me))) and not exists(select 1 from public.fable_conversations c join public.fable_conversation_members m on m.conversation_id=c.id where c.status='active' and m.user_id=me and exists(select 1 from public.fable_conversation_members other where other.conversation_id=c.id and other.user_id=p.user_id)) order by random() limit 1;
  if target is null then return; end if;
  insert into public.fable_blind_intros(requester_id,recipient_id) values(me,target) returning * into current_intro;
  select coalesce(jsonb_agg(value), '[]'::jsonb) into shared from jsonb_array_elements_text(coalesce((public.fable_profile(me)->'interests'),'[]'::jsonb)) a(value) where value in (select jsonb_array_elements_text(coalesce((public.fable_profile(target)->'interests'),'[]'::jsonb)));
  return query select current_intro.id, 'Campus connection', current_intro.status, current_intro.conversation_id, shared;
end $$;

create or replace function public.fable_respond_blind_intro(p_intro_id uuid,p_accept boolean)
returns table(status text, conversation_id uuid, matched_user uuid)
language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); x public.fable_blind_intros%rowtype; c uuid;
begin
  if me is null then raise exception 'Sign in required'; end if;
  select * into x from public.fable_blind_intros where id=p_intro_id and status='pending' and (requester_id=me or recipient_id=me) for update;
  if not found then raise exception 'This invitation is no longer available'; end if;
  if not public.fable_can_date(x.requester_id,x.recipient_id) then raise exception 'This invitation is no longer available'; end if;
  if not p_accept then update public.fable_blind_intros set status='passed',responded_at=now() where id=x.id; return query select 'passed'::text,null::uuid,null::uuid; return; end if;
  if me=x.requester_id then update public.fable_blind_intros set requester_yes=true where id=x.id returning * into x; else update public.fable_blind_intros set recipient_yes=true,responded_at=now() where id=x.id returning * into x; end if;
  if x.requester_yes and x.recipient_yes then
    insert into public.fable_conversations(kind,reveal_at,cooldown_until) values('blind',now(),now()+interval '3 days') returning id into c;
    insert into public.fable_conversation_members values(c,x.requester_id),(c,x.recipient_id);
    update public.fable_blind_intros set status='matched',conversation_id=c,responded_at=now() where id=x.id;
    return query select 'matched'::text,c,case when me=x.requester_id then x.recipient_id else x.requester_id end;
  else
    return query select 'pending'::text,null::uuid,case when me=x.requester_id then x.recipient_id else x.requester_id end;
  end if;
end $$;

create or replace function public.fable_send_interest(p_target_id uuid,p_opener text)
returns table(matched boolean, conversation_id uuid)
language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); c uuid;
begin
  if me is null or me=p_target_id or not public.fable_can_date(me,p_target_id) then raise exception 'This profile is not available'; end if;
  insert into public.fable_interest_reactions(sender_id,target_id,opener,status) values(me,p_target_id,left(coalesce(p_opener,''),300),'accepted') on conflict(sender_id,target_id) do update set opener=excluded.opener,status='accepted',created_at=now();
  if exists(select 1 from public.fable_interest_reactions where sender_id=p_target_id and target_id=me and status='accepted') then
    select x.conversation_id into c from public.fable_conversation_members a join public.fable_conversation_members b on a.conversation_id=b.conversation_id join public.fable_conversations x on x.id=a.conversation_id where a.user_id=me and b.user_id=p_target_id and x.status='active' limit 1;
    if c is null then insert into public.fable_conversations(kind,reveal_at) values('discovery',now()) returning id into c; insert into public.fable_conversation_members values(c,me),(c,p_target_id); end if;
    return query select true,c;
  else return query select false,null::uuid; end if;
end $$;

create or replace function public.fable_interest_inbox()
returns setof jsonb language plpgsql stable security definer set search_path = '' as $$
declare me uuid:=auth.uid();
begin
 return query select jsonb_build_object('sender_id',r.sender_id,'opener',r.opener,'created_at',r.created_at,'profile',public.fable_public_profile(r.sender_id,false))
 from public.fable_interest_reactions r where r.target_id=me and r.status='accepted'
 and not exists(select 1 from public.fable_interest_reactions answer where answer.sender_id=me and answer.target_id=r.sender_id and answer.status in ('accepted','passed'))
 and not exists(select 1 from public.fable_blocks b where (b.blocker_id=me and b.blocked_id=r.sender_id) or (b.blocker_id=r.sender_id and b.blocked_id=me))
 order by r.created_at;
end $$;

create or replace function public.fable_respond_interest(p_sender_id uuid,p_accept boolean)
returns table(matched boolean,conversation_id uuid)
language plpgsql security definer set search_path = '' as $$
declare me uuid:=auth.uid(); c uuid;
begin
 if not exists(select 1 from public.fable_interest_reactions where sender_id=p_sender_id and target_id=me and status='accepted') then raise exception 'This hello is no longer available'; end if;
 if not p_accept then
   update public.fable_interest_reactions set status='passed' where sender_id=p_sender_id and target_id=me;
   return query select false,null::uuid; return;
 end if;
 insert into public.fable_interest_reactions(sender_id,target_id,opener,status) values(me,p_sender_id,'','accepted') on conflict(sender_id,target_id) do update set status='accepted',created_at=now();
 if public.fable_can_date(me,p_sender_id) then
   select x.conversation_id into c from public.fable_conversation_members a join public.fable_conversation_members b on a.conversation_id=b.conversation_id join public.fable_conversations x on x.id=a.conversation_id where a.user_id=me and b.user_id=p_sender_id and x.status='active' limit 1;
   if c is null then insert into public.fable_conversations(kind,reveal_at) values('discovery',now()) returning id into c; insert into public.fable_conversation_members values(c,me),(c,p_sender_id); end if;
   return query select true,c;
 else return query select false,null::uuid; end if;
end $$;

create or replace function public.fable_list_conversations()
returns setof jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid:=auth.uid();
begin
 delete from public.fable_messages where expires_at is not null and expires_at<now();
 update public.fable_conversations set status='ended',ended_at=now(),cooldown_until=null where kind='blind' and status='active' and end_requested_at<=now()-interval '24 hours';
 delete from public.fable_messages m using public.fable_conversations c where c.id=m.conversation_id and c.kind='blind' and c.status='ended' and c.end_requested_at<=now()-interval '24 hours';
 return query select jsonb_build_object('id',c.id,'kind',c.kind,'status',c.status,'created_at',c.created_at,'cooldown_until',c.cooldown_until,'end_requested_by',c.end_requested_by,'end_requested_at',c.end_requested_at,'member_id',other.user_id,'profile',public.fable_public_profile(other.user_id,true),'last_message',lm.body,'last_message_at',lm.created_at)
 from public.fable_conversations c join public.fable_conversation_members mine on mine.conversation_id=c.id and mine.user_id=me join public.fable_conversation_members other on other.conversation_id=c.id and other.user_id<>me
 left join lateral (select m.body,m.created_at from public.fable_messages m where m.conversation_id=c.id order by m.created_at desc limit 1) lm on true where c.status='active' order by coalesce(lm.created_at,c.created_at) desc;
end $$;

create or replace function public.fable_list_messages(p_conversation_id uuid)
returns setof jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid:=auth.uid();
begin
 if not exists(select 1 from public.fable_conversation_members m join public.fable_conversations c on c.id=m.conversation_id where m.conversation_id=p_conversation_id and m.user_id=me and c.status='active') then raise exception 'Conversation unavailable'; end if;
 delete from public.fable_messages where conversation_id=p_conversation_id and expires_at is not null and expires_at<now();
 return query select jsonb_build_object('id',m.id,'sender_id',m.sender_id,'body',m.body,'ephemeral',m.ephemeral,'created_at',m.created_at,'mine',m.sender_id=me) from public.fable_messages m where m.conversation_id=p_conversation_id order by m.created_at;
end $$;

create or replace function public.fable_send_message(p_conversation_id uuid,p_text text,p_ephemeral boolean default false)
returns table(id uuid,sender_id uuid,body text,ephemeral boolean,created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare me uuid:=auth.uid(); result public.fable_messages%rowtype;
begin
 if exists(select 1 from public.fable_suspensions where user_id=me and suspended_until>now()) then raise exception 'Account messaging is temporarily suspended'; end if;
 if length(trim(coalesce(p_text,''))) not between 1 and 2000 then raise exception 'Message must be between 1 and 2000 characters'; end if;
 if not exists(select 1 from public.fable_conversation_members m join public.fable_conversations c on c.id=m.conversation_id where m.conversation_id=p_conversation_id and m.user_id=me and c.status='active') then raise exception 'Conversation unavailable'; end if;
 insert into public.fable_messages(conversation_id,sender_id,body,ephemeral,expires_at) values(p_conversation_id,me,trim(p_text),coalesce(p_ephemeral,false),case when p_ephemeral then now()+interval '24 hours' else null end) returning * into result;
 return query select result.id,result.sender_id,result.body,result.ephemeral,result.created_at;
end $$;

create or replace function public.fable_submit_report(p_conversation_id uuid,p_reason text,p_context jsonb)
returns table(id uuid,status text,created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare me uuid:=auth.uid(); target uuid; result public.fable_reports%rowtype;
begin
 if p_conversation_id is null or not exists(select 1 from public.fable_conversation_members where conversation_id=p_conversation_id and user_id=me) then raise exception 'Conversation unavailable'; end if;
 select user_id into target from public.fable_conversation_members where conversation_id=p_conversation_id and user_id<>me limit 1;
 insert into public.fable_reports(reporter_id,reported_id,conversation_id,reason,context) values(me,target,left(coalesce(p_reason,'Safety concern'),80),case when jsonb_typeof(p_context)='array' then p_context else '[]'::jsonb end) returning * into result;
 return query select result.id,result.status,result.created_at;
end $$;

create or replace function public.fable_block_user(p_target_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare me uuid:=auth.uid();
begin
 if me is null or me=p_target_id then raise exception 'Invalid account'; end if;
 insert into public.fable_blocks(blocker_id,blocked_id) values(me,p_target_id) on conflict do nothing;
 update public.fable_conversations c set status='blocked',ended_at=now() where c.id in(select a.conversation_id from public.fable_conversation_members a join public.fable_conversation_members b on a.conversation_id=b.conversation_id where a.user_id=me and b.user_id=p_target_id) and c.status='active';
 update public.fable_blind_intros set status='passed' where status='pending' and ((requester_id=me and recipient_id=p_target_id) or (requester_id=p_target_id and recipient_id=me));
end $$;

create or replace function public.fable_request_correction(p_note text)
returns table(id uuid,status text,created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare result public.fable_correction_requests%rowtype;
begin
 if length(trim(coalesce(p_note,''))) not between 1 and 300 then raise exception 'Add a short correction note'; end if;
 insert into public.fable_correction_requests(user_id,note) values(auth.uid(),trim(p_note)) returning * into result;
 return query select result.id,result.status,result.created_at;
end $$;

create or replace function public.fable_accept_legal(p_terms_version text,p_privacy_version text)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if length(coalesce(p_terms_version,''))>40 or length(coalesce(p_privacy_version,''))>40 or p_terms_version='' or p_privacy_version='' then raise exception 'Legal document version required'; end if;
 if not exists(select 1 from public.fable_legal_versions where id=true and terms_version=p_terms_version and privacy_version=p_privacy_version) then raise exception 'Please reload and accept the current legal documents'; end if;
 insert into public.fable_legal_acceptances(user_id,terms_version,privacy_version) values(auth.uid(),p_terms_version,p_privacy_version) on conflict(user_id,terms_version,privacy_version) do nothing;
end $$;

create or replace function public.fable_end_date(p_conversation_id uuid,p_continue boolean default false)
returns table(status text)
language plpgsql security definer set search_path = '' as $$
declare me uuid:=auth.uid(); c public.fable_conversations%rowtype;
begin
 select * into c from public.fable_conversations where id=p_conversation_id and kind='blind' and status='active' and exists(select 1 from public.fable_conversation_members where conversation_id=id and user_id=me) for update;
 if not found then raise exception 'Date unavailable'; end if;
 if p_continue and c.end_requested_by is not null then update public.fable_conversations set end_requested_by=null,end_requested_at=null where id=c.id; return query select 'continued'::text; return; end if;
 if c.end_requested_at<=now()-interval '24 hours' or (c.end_requested_by is not null and c.end_requested_by<>me) then update public.fable_conversations set status='ended',ended_at=now(),cooldown_until=null where id=c.id; delete from public.fable_messages where conversation_id=c.id; return query select 'ended'::text; return; end if;
 update public.fable_conversations set end_requested_by=me,end_requested_at=now() where id=c.id;
 return query select 'requested'::text;
end $$;

create or replace function public.fable_export_data()
returns jsonb language plpgsql security definer set search_path = '' as $
declare me uuid:=auth.uid(); result jsonb;
begin
 if me is null then raise exception 'Sign in required'; end if;
 delete from public.fable_messages where expires_at is not null and expires_at<now() and conversation_id in(select cm.conversation_id from public.fable_conversation_members cm where cm.user_id=me);
 select jsonb_build_object(
  'exportedAt',now(),'profile',p.profile_data,'settings',s.state,
  'legalAcceptances',coalesce((select jsonb_agg(to_jsonb(a) order by a.accepted_at) from public.fable_legal_acceptances a where a.user_id=me),'[]'::jsonb),
  'blindIntroductions',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at) from public.fable_blind_intros i where i.requester_id=me or i.recipient_id=me),'[]'::jsonb),
  'interests',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at) from public.fable_interest_reactions r where r.sender_id=me or r.target_id=me),'[]'::jsonb),
  'blocks',coalesce((select jsonb_agg(to_jsonb(b) order by b.created_at) from public.fable_blocks b where b.blocker_id=me),'[]'::jsonb),
  'reports',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at) from public.fable_reports r where r.reporter_id=me),'[]'::jsonb),
  'correctionRequests',coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at) from public.fable_correction_requests c where c.user_id=me),'[]'::jsonb),
  'moderatorActions',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at) from public.fable_moderator_actions a where a.moderator_id=me),'[]'::jsonb),
  'conversations',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'kind',c.kind,'status',c.status,'created_at',c.created_at,'ended_at',c.ended_at,'messages',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'sender_id',m.sender_id,'body',m.body,'ephemeral',m.ephemeral,'created_at',m.created_at) order by m.created_at) from public.fable_messages m where m.conversation_id=c.id),'[]'::jsonb)) order by c.created_at) from public.fable_conversations c where exists(select 1 from public.fable_conversation_members cm where cm.conversation_id=c.id and cm.user_id=me)),'[]'::jsonb)
 ) into result from public.fable_profiles p left join public.fable_state s on s.user_id=p.user_id where p.user_id=me;
 if result is null then raise exception 'Account profile not found'; end if;
 return result;
end $;

create or replace function public.fable_moderation_queue()
returns setof jsonb language plpgsql stable security definer set search_path = '' as $$
begin
 if coalesce(auth.jwt()->'app_metadata'->>'role','')<>'moderator' then raise exception 'Moderator access required'; end if;
 return query select jsonb_build_object('id',r.id,'reason',r.reason,'status',r.status,'created_at',r.created_at,'context',r.context,'reported_profile',public.fable_public_profile(r.reported_id,false)) from public.fable_reports r where r.status in ('open','reviewing') order by r.created_at;
end $$;

create or replace function public.fable_moderate_report(p_report_id uuid,p_action text,p_note text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare me uuid:=auth.uid();
begin
 if coalesce(auth.jwt()->'app_metadata'->>'role','')<>'moderator' then raise exception 'Moderator access required'; end if;
 if p_action not in ('dismissed','warned','suspended','escalated') then raise exception 'Invalid moderation action'; end if;
 update public.fable_reports set status=p_action where id=p_report_id and status in ('open','reviewing');
 if not found then raise exception 'Report is no longer open'; end if;
 insert into public.fable_moderator_actions(report_id,moderator_id,action,note) values(p_report_id,me,p_action,left(coalesce(p_note,''),500));
 if p_action='suspended' then
   insert into public.fable_suspensions(user_id,suspended_until,reason)
   select reported_id,now()+interval '24 hours',reason from public.fable_reports where id=p_report_id
   on conflict(user_id) do update set suspended_until=excluded.suspended_until,reason=excluded.reason,updated_at=now();
 end if;
end $$;

create or replace function public.fable_correction_queue()
returns setof jsonb language plpgsql stable security definer set search_path = '' as $$
begin
 if coalesce(auth.jwt()->'app_metadata'->>'role','')<>'moderator' then raise exception 'Moderator access required'; end if;
 return query select jsonb_build_object('id',r.id,'user_id',r.user_id,'note',r.note,'status',r.status,'created_at',r.created_at) from public.fable_correction_requests r where r.status in ('open','reviewing') order by r.created_at;
end $$;

create or replace function public.fable_review_correction(p_request_id uuid,p_status text)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if coalesce(auth.jwt()->'app_metadata'->>'role','')<>'moderator' then raise exception 'Moderator access required'; end if;
 if p_status not in ('reviewing','resolved','declined') then raise exception 'Invalid correction status'; end if;
 update public.fable_correction_requests set status=p_status where id=p_request_id and status in ('open','reviewing');
 if not found then raise exception 'Request is no longer open'; end if;
end $$;

grant execute on function public.fable_discover_profiles() to authenticated;
grant execute on function public.fable_request_blind_intro() to authenticated;
grant execute on function public.fable_respond_blind_intro(uuid,boolean) to authenticated;
grant execute on function public.fable_send_interest(uuid,text) to authenticated;
grant execute on function public.fable_interest_inbox() to authenticated;
grant execute on function public.fable_respond_interest(uuid,boolean) to authenticated;
grant execute on function public.fable_list_conversations() to authenticated;
grant execute on function public.fable_list_messages(uuid) to authenticated;
grant execute on function public.fable_send_message(uuid,text,boolean) to authenticated;
grant execute on function public.fable_submit_report(uuid,text,jsonb) to authenticated;
grant execute on function public.fable_block_user(uuid) to authenticated;
grant execute on function public.fable_request_correction(text) to authenticated;
grant execute on function public.fable_accept_legal(text,text) to authenticated;
grant execute on function public.fable_end_date(uuid,boolean) to authenticated;
grant execute on function public.fable_export_data() to authenticated;
grant execute on function public.fable_moderation_queue() to authenticated;
grant execute on function public.fable_moderate_report(uuid,text,text) to authenticated;
grant execute on function public.fable_correction_queue() to authenticated;
grant execute on function public.fable_review_correction(uuid,text) to authenticated;

revoke all on table public.fable_legal_versions from public, anon, authenticated;
revoke all on function public.fable_export_data() from public, anon;
revoke all on function public.fable_profile(uuid) from public, anon, authenticated;
revoke all on function public.fable_verified_student(uuid) from public, anon, authenticated;
revoke all on function public.fable_can_date(uuid,uuid) from public, anon, authenticated;
revoke all on function public.fable_public_profile(uuid,boolean) from public, anon, authenticated;

-- Private image storage is configured separately from this migration. Never use a public bucket for dating profile photos.
