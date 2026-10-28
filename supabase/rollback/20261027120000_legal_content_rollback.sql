-- تراجع 20261027120000_legal_content — التطبيقان يعودان لنصهما المدمج
delete from public.app_config where key = 'legal_content';
