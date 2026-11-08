-- تراجع 20261105130000_accept_from_13_no_guardian: يعيد شرط موافقة ولي الأمر من ١٣ إلى ١٧.
do $mig$
declare
  d text;
  s int;
begin
  d := pg_get_functiondef('public.trg_profiles_age_rules()'::regprocedure);
  s := position('hint = ''under_13'';' in d);
  if s = 0 then raise exception 'anchor: trg_profiles_age_rules'; end if;
  d := left(d, s + length('hint = ''under_13'';') - 1)
    || E'\n      elsif not public.has_guardian_consent(new.id) then'
    || E'\n        raise exception ''العضو قاصر: يلزم موافقة ولي أمره من حسابه في التطبيق قبل تفعيل حسابه.'' using hint = ''guardian_consent_required'';'
    || substring(d from s + length('hint = ''under_13'';'));
  d := replace(d, 'and a is not null and a < 13 and public.profile_has_login(new.id)',
                  'and a is not null and a < 18 and public.profile_has_login(new.id)');
  execute d;

  d := pg_get_functiondef('public.merge_member_into_tree(uuid,uuid)'::regprocedure);
  s := position('  -- ─── حماية: ملف المالك لا يُدمج' in d);
  if s = 0 then raise exception 'anchor: merge_member_into_tree'; end if;
  d := left(d, s - 1)
    || E'  if public.age_years(coalesce(v_new.birth_date, v_tree.birth_date)) between 13 and 17\n'
    || E'     and not public.has_guardian_consent(p_new_member_id, p_tree_member_id) then\n'
    || E'    return jsonb_build_object(''success'', false, ''hint'', ''guardian_consent_required'',\n'
    || E'      ''message'', ''العضو قاصر: يلزم موافقة ولي أمره من حسابه في التطبيق قبل تفعيل حسابه.'');\n'
    || E'  end if;\n\n'
    || substring(d from s);
  d := replace(d, 'لا حساب دون ١٣ ───', 'لا حساب دون ١٣، ومن ١٣ إلى ١٧ بعد موافقة ولي الأمر ───');
  execute d;
end
$mig$;
