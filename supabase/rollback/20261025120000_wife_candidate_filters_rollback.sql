-- تراجع 20261025120000_wife_candidate_filters: يحذف المفتاحين (التطبيق يرجع لافتراضه ١٨ سنة و١٢ شهراً).
delete from public.app_config where key in ('wife_candidate_min_age', 'wife_candidate_recent_months');
