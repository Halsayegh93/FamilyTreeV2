-- تراجع 20261025100100_insights_owner_admin_only: تقرير الموافقات للمالك والمدير والمراقب كما كان (نفس النص حرفياً).

do $unpatch$
declare
  d text;
  n int;
  v_new text := $n$not in ('owner', 'admin')$n$;
  v_old text := $o$not in ('owner', 'admin', 'monitor')$o$;
begin
  d := pg_get_functiondef('public.approvals_report(timestamptz,timestamptz)'::regprocedure);
  n := (length(d) - length(replace(d, v_new, ''))) / length(v_new);
  if n <> 1 then
    raise exception 'insights_owner_admin_only rollback: expected the new text once, found %', n;
  end if;
  execute replace(d, v_new, v_old);
end
$unpatch$;
