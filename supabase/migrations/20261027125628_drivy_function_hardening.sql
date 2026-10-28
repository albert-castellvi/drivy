-- Advisor fixes: pin search_path and block RPC access to trigger function
alter function public.set_updated_at() set search_path = public;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
