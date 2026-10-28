-- تراجع 20261025110000_death_dates_campaign_config: يحذف مفتاحي الحملة (التطبيق يرجع لافتراضه: يُظهرها ما دام في التواريخ
-- ناقص). سجل تغييرهما في app_config_history يبقى للأثر.

delete from public.app_config where key in ('death_dates_campaign', 'death_dates_campaign_until');
