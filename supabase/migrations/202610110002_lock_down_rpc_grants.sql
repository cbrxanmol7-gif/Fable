-- Restrict Fable SECURITY DEFINER RPCs to signed-in users. The API verifies
-- an authenticated CU UP mailbox before forwarding any database operation.
revoke execute on function public.fable_touch_updated_at() from public, anon, authenticated;

revoke execute on function public.fable_accept_legal(text, text) from public, anon;
grant execute on function public.fable_accept_legal(text, text) to authenticated;
revoke execute on function public.fable_block_user(uuid) from public, anon;
grant execute on function public.fable_block_user(uuid) to authenticated;
revoke execute on function public.fable_correction_queue() from public, anon;
grant execute on function public.fable_correction_queue() to authenticated;
revoke execute on function public.fable_discover_profiles() from public, anon;
grant execute on function public.fable_discover_profiles() to authenticated;
revoke execute on function public.fable_end_date(uuid, boolean) from public, anon;
grant execute on function public.fable_end_date(uuid, boolean) to authenticated;
revoke execute on function public.fable_interest_inbox() from public, anon;
grant execute on function public.fable_interest_inbox() to authenticated;
revoke execute on function public.fable_list_conversations() from public, anon;
grant execute on function public.fable_list_conversations() to authenticated;
revoke execute on function public.fable_list_messages(uuid) from public, anon;
grant execute on function public.fable_list_messages(uuid) to authenticated;
revoke execute on function public.fable_moderate_report(uuid, text, text) from public, anon;
grant execute on function public.fable_moderate_report(uuid, text, text) to authenticated;
revoke execute on function public.fable_moderation_queue() from public, anon;
grant execute on function public.fable_moderation_queue() to authenticated;
revoke execute on function public.fable_request_blind_intro() from public, anon;
grant execute on function public.fable_request_blind_intro() to authenticated;
revoke execute on function public.fable_request_correction(text) from public, anon;
grant execute on function public.fable_request_correction(text) to authenticated;
revoke execute on function public.fable_respond_blind_intro(uuid, boolean) from public, anon;
grant execute on function public.fable_respond_blind_intro(uuid, boolean) to authenticated;
revoke execute on function public.fable_respond_interest(uuid, boolean) from public, anon;
grant execute on function public.fable_respond_interest(uuid, boolean) to authenticated;
revoke execute on function public.fable_review_correction(uuid, text) from public, anon;
grant execute on function public.fable_review_correction(uuid, text) to authenticated;
revoke execute on function public.fable_send_interest(uuid, text) from public, anon;
grant execute on function public.fable_send_interest(uuid, text) to authenticated;
revoke execute on function public.fable_send_message(uuid, text, boolean) from public, anon;
grant execute on function public.fable_send_message(uuid, text, boolean) to authenticated;
revoke execute on function public.fable_submit_report(uuid, text, jsonb) from public, anon;
grant execute on function public.fable_submit_report(uuid, text, jsonb) to authenticated;

-- No direct table access is needed from the PostgREST roles; server routes use
-- authenticated RPCs for these tables.
revoke all on table public.fable_legal_versions from anon, authenticated;
grant select on table public.fable_legal_versions to authenticated;
revoke all on table public.fable_suspensions from anon, authenticated;
