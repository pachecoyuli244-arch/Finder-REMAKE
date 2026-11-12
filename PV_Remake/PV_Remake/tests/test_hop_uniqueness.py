"""PVFinder: the coordinated hopper must not revisit entered servers."""
import sqlite3
import sys
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import hop_coordinator


class FakeHandler:
    def __init__(self, collector_id):
        self.collector_id = collector_id

    def collector(self):
        return {'id': self.collector_id}

    def respond(self, status, body):
        return status, body


class HopUniquenessTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:', isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.db.execute('CREATE TABLE detections(place_id INTEGER, server_id TEXT)')
        hop_coordinator.install(self.db)
        self.lock = threading.RLock()
        self.clock = 1000

    def tearDown(self):
        self.db.close()

    def request(self, bot, endpoint, **fields):
        payload = {'place_id': 42, **fields}
        return hop_coordinator.route(
            FakeHandler(bot), endpoint, payload, self.db, self.lock,
            lambda x: x if type(x) is int and x > 0 else None,
            lambda x: x if type(x) is str and x.startswith('s') else None,
            lambda: self.clock, lambda *args: True)

    def test_entered_job_never_reassigned_even_after_expiry(self):
        code, result = self.request('A', '/api/hop/start', server_id='s1')
        self.assertEqual(code, 200)
        self.assertTrue(result['scan'])
        self.clock += 10_000  # far beyond the 25 minute active-scan lease
        code, other = self.request('B', '/api/hop/start', server_id='s1')
        self.assertEqual(code, 200)
        self.assertFalse(other['scan'])
        code, result = self.request('B', '/api/hop/next',
                                    current_server='s0',
                                    candidates=['s1', 's2'])
        self.assertEqual(code, 200)
        self.assertEqual(result['server_id'], 's2')

    def test_reserved_job_is_exclusive_and_enters_once(self):
        _, first = self.request('A', '/api/hop/next',
                                current_server='s0', candidates=['s3'])
        self.assertEqual(first['server_id'], 's3')
        _, second = self.request('B', '/api/hop/next',
                                 current_server='s0', candidates=['s3'])
        self.assertIsNone(second['server_id'])
        _, started = self.request('A', '/api/hop/start', server_id='s3')
        self.assertTrue(started['scan'])
        self.clock += 5000
        _, third = self.request('B', '/api/hop/next',
                                current_server='s0', candidates=['s3'])
        self.assertIsNone(third['server_id'])

    def test_completed_job_remains_skipped(self):
        self.request('A', '/api/hop/start', server_id='s4')
        hop_coordinator.mark_done(self.db, 42, 's4', 'A', self.clock)
        self.clock += 10_000
        _, result = self.request('B', '/api/hop/next',
                                 current_server='s0', candidates=['s4'])
        self.assertIsNone(result['server_id'])

    def test_failed_teleport_excluded_from_all_future_assignments(self):
        _, first = self.request('A', '/api/hop/next',
                                current_server='s0', candidates=['s7'])
        self.assertEqual(first['server_id'], 's7')
        code, released = self.request('A', '/api/hop/release',
                                      server_id='s7', failed=True)
        self.assertEqual(code, 200)
        self.assertTrue(released['excluded'])
        self.clock += 100_000
        _, result = self.request('B', '/api/hop/next',
                                 current_server='s0', candidates=['s7','s8'])
        self.assertEqual(result['server_id'], 's8')

    def test_prefers_one_player_server(self):
        code, result = self.request('A', '/api/hop/next',
                                    current_server='s0',
                                    candidates=[{'id':'s10','playing':2},
                                                {'id':'s11','playing':1}])
        self.assertEqual(code, 200)
        self.assertEqual(result['server_id'], 's11')
        self.assertEqual(result['player_count'], 1)

    def test_all_open_servers_eligible_and_full_servers_excluded(self):
        code, result = self.request('A', '/api/hop/next', current_server='s0',
                                    candidates=[
                                        {'id':'s10','playing':3,'maxPlayers':10},
                                        {'id':'s11','playing':9,'maxPlayers':9},
                                        {'id':'s12','playing':0,'maxPlayers':10}])
        self.assertEqual(code, 200)
        self.assertEqual(result['server_id'], 's12')
        self.assertEqual(result['player_count'], 0)
        code, result = self.request('B', '/api/hop/next', current_server='s0',
                                    candidates=[
                                        {'id':'s11','playing':9,'maxPlayers':9},
                                        {'id':'s10','playing':3,'maxPlayers':10}])
        self.assertEqual(code, 200)
        self.assertEqual(result['server_id'], 's10')
        self.assertEqual(result['player_count'], 3)

    def test_bot_script_scans_all_public_servers_with_space(self):
        script = (ROOT / 'delta' / 'PVFinder_Bots_ServerHop_Coordinado.lua').read_text()
        self.assertIn('playing>=0', script)
        self.assertIn('playing<maxPlayers', script)
        self.assertIn('maxPlayers=maxPlayers', script)
        self.assertNotIn('(playing==1 or playing==2)', script)
        self.assertIn('local HOP_RETRY_SECONDS=60', script)
        self.assertIn('nextHopAttempt=os.time()', script)
        self.assertIn('if reportFinished and nextHopAttempt and os.time()>=nextHopAttempt then', script)
        self.assertIn('/api/collector/renew', script)
        self.assertIn('failed=true', script)


if __name__ == '__main__':
    unittest.main()
