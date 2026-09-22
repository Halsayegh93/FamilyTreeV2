import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location('monitor', Path(__file__).resolve().parents[2] / 'scripts/monitor-health.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class MonitorTests(unittest.TestCase):
    def test_healthy(self):
        self.assertEqual(m.classify({'cron':[{'name':'daily','status':'succeeded'}],
            'dispatch_healthy':True,'http_failures':4,'pending_deletions':0}), {})
    def test_incident_thresholds(self):
        issues = m.classify({'cron':[{'name':'daily','status':'failed'}],
            'dispatch_healthy':False,'http_failures':5,'pending_deletions':1})
        self.assertEqual(set(issues), {'cron:daily','dispatch_stale','http_failures','pending_deletions'})
    def test_dedup_and_recovery(self):
        current, opened, resolved = m.transition({}, {'dispatch_stale':'problem'}, True)
        self.assertEqual(opened, ['dispatch_stale'])
        self.assertEqual(m.transition(current, current, True)[1:], ([], []))
        self.assertEqual(m.transition(current, {}, True)[2], ['dispatch_stale'])
    def test_unavailable_never_resolves_incident(self):
        current, opened, resolved = m.transition({'dispatch_stale':'problem'}, {}, False)
        self.assertEqual(resolved, [])
        self.assertIn('dispatch_stale', current)
        self.assertEqual(opened, ['monitor_unavailable'])
        self.assertEqual(m.transition(current, {}, False)[1:], ([], []))
        self.assertEqual(m.transition(current, {}, True)[2], ['dispatch_stale','monitor_unavailable'])

if __name__ == '__main__':
    unittest.main()
