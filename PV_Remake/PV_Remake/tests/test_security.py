"""Pruebas de regresión de acceso y cabeceras de PVFinder (solo stdlib).

Ejecutar: python3 -m unittest discover -s tests -p test_security.py
No requiere claves reales de producción ni solicita la página pública.
"""
import http.cookiejar
import hashlib
import sqlite3
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


class SecurityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory()
        with socket.socket() as sock:
            sock.bind(('127.0.0.1',0))
            cls.port=sock.getsockname()[1]
        cls.base=f'http://127.0.0.1:{cls.port}'
        env=os.environ.copy()
        env.update({
            'PVFINDER_DB':str(Path(cls.tmp.name)/'security-test.sqlite3'),
            'PVFINDER_HOST':'127.0.0.1',
            'PVFINDER_PORT':str(cls.port),
            'PVFINDER_ADMIN_PASSWORD':'UnitTest-'+('a'*24),
            'PVFINDER_PUBLIC_URL':'',
            'RENDER_EXTERNAL_URL':'',
        })
        cls.proc=subprocess.Popen([sys.executable,'-u',str(ROOT/'server.py')],
            cwd=str(ROOT),env=env,stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL)
        for _ in range(100):
            try:
                urllib.request.urlopen(cls.base+'/api/health',timeout=.4).close()
                break
            except (OSError,urllib.error.URLError):
                time.sleep(.08)
        else:
            cls.tearDownClass()
            raise RuntimeError('Test server did not start')

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls,'proc'):
            cls.proc.terminate()
            try:cls.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:cls.proc.kill()
        if hasattr(cls,'tmp'):cls.tmp.cleanup()

    def call(self,route,body=None,headers=None,expected=200):
        hdrs={'Content-Type':'application/json',**(headers or {})}
        payload=json.dumps(body).encode() if body is not None else None
        req=urllib.request.Request(self.base+route,data=payload,headers=hdrs,
            method='POST' if body is not None else 'GET')
        try:response=urllib.request.urlopen(req,timeout=4)
        except urllib.error.HTTPError as exc:response=exc
        with response:
            self.assertEqual(response.status,expected)
            content=response.read().decode()
            if response.headers.get_content_type()=='application/json':
                content=json.loads(content)
            return dict(response.headers),content

    def test_admin_post_requires_json_to_prevent_form_csrf(self):
        self.call('/api/admin/login', {'password':'irrelevant'},
                  headers={'Content-Type':'text/plain'}, expected=415)
        self.call('/api/editor/keys', {'action':'create'},
                  headers={'Content-Type':'text/plain'}, expected=415)
        self.call('/api/logout', {},
                  headers={'Content-Type':'text/plain'}, expected=415)

    def test_public_responses_are_hardened(self):
        headers,body=self.call('/')
        self.assertIn('Content-Security-Policy',headers)
        self.assertIn("script-src 'self'",headers['Content-Security-Policy'])
        self.assertEqual(headers['X-Frame-Options'],'DENY')
        self.assertIn('Permissions-Policy',headers)
        self.assertEqual(headers['Cache-Control'],'no-store')
        self.assertIn('Content-Security-Policy',self.call('/index.html')[0])
        self.assertNotIn('Content-Security-Policy',self.call('/api/health')[0])

    def test_scanner_v3_endpoint_matches_original(self):
        path=ROOT/'delta'/'PVFinder_V3_Scanner.lua'
        with urllib.request.urlopen(self.base+'/scanner-v3.lua',timeout=4) as response:
            self.assertEqual(response.status,200)
            self.assertEqual(response.headers.get('Cache-Control'),'no-store')
            downloaded=response.read()
        self.assertEqual(downloaded,path.read_bytes())
        self.assertIn(b'PVFINDER V3',downloaded)

    def test_bot_collector_script_uses_optional_token(self):
        path=ROOT/'delta'/'PVFinder_V3_BotCollector.lua'
        with urllib.request.urlopen(self.base+'/bot-collector.lua',timeout=4) as response:
            self.assertEqual(response.status,200)
            self.assertEqual(response.headers.get('Cache-Control'),'no-store')
            script=response.read()
        self.assertEqual(script,path.read_bytes())
        self.assertIn(b'PVFINDER V3',script)
        self.assertIn(b'ENV',script)
        self.assertIn(b'/api/collect/batch',script)
        self.assertIn(b'Bearer ',script)
        self.assertIn(b'rows[1]',script)
        self.assertNotIn(b'pvf_session=',script)

    def test_headless_script_without_key_or_gui(self):
        path=ROOT/'delta'/'PVFinder_V3_HeadlessCollector.lua'
        with urllib.request.urlopen(self.base+'/bot-headless.lua',timeout=4) as res:
            self.assertEqual(res.status,200)
            downloaded=res.read()
        self.assertEqual(downloaded,path.read_bytes())
        self.assertIn(b'/api/collect/snapshot',downloaded)
        self.assertIn(b'task.wait(10)',downloaded)
        self.assertNotIn(b'Instance.new("ScreenGui")',downloaded)
        self.assertIn(b'PVFINDER_COLLECTOR_TOKEN',downloaded)

    def test_join_points_to_reported_job_and_rejects_invalid_id(self):
        headers,_=self.call('/api/admin/login',
                            {'password':'UnitTest-'+('a'*24)})
        admin={'Cookie':headers['Set-Cookie'].split(';')[0]}
        _,issued=self.call('/api/admin/collectors',
                           {'label':'JobId validation'},headers=admin,expected=201)
        auth={'Authorization':'Bearer '+issued['credential']}
        job=str(uuid.uuid4())
        place=107778070777162
        reading={'place_id':place,'server_id':job,'egg_id':'GLOBAL/join-test',
                 'egg_name':'Server test','rarity':'Cosmic','biome':'Cherry Blossom',
                 'income_per_second':12345}
        self.call('/api/collect',reading,headers=auth)
        feed=self.call('/api/feed?server='+job,headers=admin)[1]
        self.assertEqual(feed['items'][0]['join_url'],
                         f'roblox://placeId={place}&gameInstanceId={job}')
        self.assertFalse(feed['items'][0]['availability_confirmed'])
        reading['server_id']='servidor-invalido'
        self.call('/api/collect',reading,headers=auth,expected=400)

    def test_join_recovers_report_place_from_owned_server(self):
        headers,_=self.call('/api/admin/login',
                            {'password':'UnitTest-'+('a'*24)})
        admin={'Cookie':headers['Set-Cookie'].split(';')[0]}
        _,issued=self.call('/api/admin/collectors',
                           {'label':'Join place lookup'},headers=admin,expected=201)
        auth={'Authorization':'Bearer '+issued['credential']}
        job=str(uuid.uuid4())
        place=107778070777162
        self.call('/api/hop/start',
                  {'server_id':job,'place_id':place},headers=auth)
        # Un reporte puntual historico puede no incluir PlaceId.
        self.call('/api/collect',
                  {'server_id':job,'egg_id':'G/legacy','egg_name':'Legacy egg',
                   'rarity':'Secret'},headers=auth)
        result=self.call('/api/feed?server='+job,headers=admin)[1]
        item=result['items'][0]
        self.assertEqual(item['place_id'],place)
        self.assertEqual(item['join_url'],
                         f'roblox://placeId={place}&gameInstanceId={job}')

    def test_live_join_uses_place_and_job_not_optional_url(self):
        source=(ROOT/'web'/'app.js').read_text()
        self.assertIn("const place=x.place_id==null?",source)
        self.assertIn("const job=x.server_id==null?",source)
        self.assertIn('roblox://placeId=',source)
        self.assertIn('validPlace&&validJob',source)

    def test_collector_snapshot_preserves_missing_eggs(self):
        headers,_=self.call('/api/admin/login',{'password':'UnitTest-'+('a'*24)})
        admin={'Cookie':headers['Set-Cookie'].split(';')[0]}
        _,first=self.call('/api/admin/collectors',
            {'label':'Snapshot tester'},headers=admin,expected=201)
        auth={'Authorization':'Bearer '+first['credential']}
        server=str(uuid.uuid4())
        place=107778070777162
        a={'server_id':server,'place_id':place,
           'scopes':['GLOBAL'],'items':[{'egg_id':'GLOBAL/egg1','egg_name':'Hexed Pumpkin',
                     'rarity':'Cosmic','biome':'Halloween Z3',
                     'income_per_second':162290000,'income_type':'ESTIMADO'}]}
        self.call('/api/collect/snapshot',a,headers=auth,expected=200)
        _,feed=self.call('/api/feed?server='+server,headers=admin)
        self.assertEqual(feed['count'],1)
        self.assertEqual(feed['items'][0]['egg_name'],'Hexed Pumpkin')
        self.assertEqual(feed['items'][0]['data_status'],'VISTO_RECIENTEMENTE')
        # Sustitución: el anterior desaparece en cuanto se reporta otro TOP.
        a['items'][0]['egg_id']='GLOBAL/egg2'
        a['items'][0]['egg_name']='Haunted Scorpio'
        _,r=self.call('/api/collect/snapshot',a,headers=auth,expected=200)
        self.assertEqual(r['accepted'],1)
        self.assertEqual(r['removed'],0)
        self.assertEqual(r['marked_absent'],1)
        _,feed=self.call('/api/feed?server='+server,headers=admin)
        self.assertEqual(feed['count'],2)
        self.assertEqual({x['egg_name'] for x in feed['items']},{'Hexed Pumpkin','Haunted Scorpio'})
        statuses={x['egg_name']:x['data_status'] for x in feed['items']}
        self.assertEqual(statuses['Hexed Pumpkin'],'YA_NO_VISTO')
        self.assertEqual(statuses['Haunted Scorpio'],'VISTO_RECIENTEMENTE')
        _,detected=self.call('/api/feed?detected_only=1&server='+server,headers=admin)
        self.assertEqual(detected['count'],1)
        self.assertEqual(detected['items'][0]['egg_name'],'Haunted Scorpio')
        # Instantánea vacía en fuente leída marca los huevos como no vistos.
        _,r=self.call('/api/collect/snapshot',
            {'server_id':server,'place_id':place,'items':[],'scopes':['GLOBAL']},
            headers=auth,expected=200)
        self.assertEqual(r['accepted'],0)
        self.assertEqual(r['removed'],0)
        self.assertEqual(self.call('/api/feed?server='+server,headers=admin)[1]['count'],2)
        self.assertTrue(all(x['data_status']=='YA_NO_VISTO' for x in
            self.call('/api/feed?server='+server,headers=admin)[1]['items']))
        _,detected=self.call('/api/feed?detected_only=1&server='+server,headers=admin)
        self.assertEqual(detected['count'],0)
        self.assertEqual(detected['total_count'],0)
        # Ningún usuario sin credencial puede borrar un reporte.
        self.call('/api/collect/snapshot',
            {'server_id':server,'place_id':place,'items':[]},
            expected=401)
        # Otro recolector en el mismo servidor no es borrado por el primero.
        _,second=self.call('/api/admin/collectors',
            {'label':'Other tester'},headers=admin,expected=201)
        auth2={'Authorization':'Bearer '+second['credential']}
        self.call('/api/collect/snapshot',a,headers=auth2)
        self.call('/api/collect/snapshot',
            {'server_id':server,'place_id':place,'items':[]},headers=auth)
        self.assertEqual(self.call('/api/feed?server='+server,headers=admin)[1]['count'],2)

    def test_full_snapshot_accepts_many_and_preserves_partial_sources(self):
        headers,_=self.call('/api/admin/login',{'password':'UnitTest-'+('a'*24)})
        admin={'Cookie':headers['Set-Cookie'].split(';')[0]}
        _,issued=self.call('/api/admin/collectors',
            {'label':'V4 multiscan'},headers=admin,expected=201)
        auth={'Authorization':'Bearer '+issued['credential']}
        server=str(uuid.uuid4())
        place=107778070777162
        first={'egg_id':'GLOBAL/a','egg_name':'Cosmic Alpha',
               'rarity':'Cosmic','biome':'Cherry Blossom',
               'income_per_second':99999}
        second={'egg_id':'GLOBAL/b','egg_name':'Divine Beta',
                'rarity':'Divine','biome':'Enchanted Forest',
                'income_per_second':12345}
        halloween={'egg_id':'HALLOWEEN/h','egg_name':'Secret Gamma',
                   'rarity':'Secret','biome':'Halloween Z3',
                   'income_per_second':None}
        snapshot={'server_id':server,'place_id':place,
                  'items':[first,second,halloween],
                  'scopes':['GLOBAL','HALLOWEEN']}
        _,reply=self.call('/api/collect/snapshot',snapshot,headers=auth)
        self.assertEqual(reply['accepted'],3)
        feed=self.call('/api/feed?server='+server,headers=admin)[1]
        self.assertEqual(feed['count'],3)
        unknown=next(x for x in feed['items'] if x['egg_id']=='HALLOWEEN/h')
        self.assertIsNone(unknown['income_per_second'])
        self.assertEqual(unknown['income_type'],'NO_DISPONIBLE')
        snapshot['items']=[first]
        snapshot['scopes']=['GLOBAL']
        _,reply=self.call('/api/collect/snapshot',snapshot,headers=auth)
        self.assertEqual(reply['removed'],0)
        self.assertEqual(reply['marked_absent'],1)
        feed=self.call('/api/feed?server='+server,headers=admin)[1]
        self.assertEqual({r['egg_id'] for r in feed['items']},
                         {'GLOBAL/a','GLOBAL/b','HALLOWEEN/h'})
        statuses={r['egg_id']:r['data_status'] for r in feed['items']}
        self.assertEqual(statuses['GLOBAL/b'],'YA_NO_VISTO')
        self.assertEqual(statuses['GLOBAL/a'],'VISTO_RECIENTEMENTE')
        self.assertEqual(statuses['HALLOWEEN/h'],'VISTO_RECIENTEMENTE')
        snapshot['items']=[]
        snapshot['scopes']=['HALLOWEEN']
        _,gone=self.call('/api/collect/snapshot',snapshot,headers=auth)
        self.assertEqual(gone['marked_absent'],1)
        self.assertEqual(self.call('/api/feed?server='+server,headers=admin)[1]['count'],3)
        snapshot['items']=[first,first]
        snapshot['scopes']=['GLOBAL']
        self.call('/api/collect/snapshot',snapshot,headers=auth,expected=400)
        snapshot['items']=[]
        snapshot['scopes']=['ALL']
        self.call('/api/collect/snapshot',snapshot,headers=auth,expected=400)
        self.assertEqual(self.call('/api/feed?server='+server,headers=admin)[1]['count'],3)

    def test_live_v2_scopes_all_rarities_and_permanent_history(self):
        headers,_=self.call('/api/admin/login',
            {'password':'UnitTest-'+('a'*24)})
        admin={'Cookie':headers['Set-Cookie'].split(';')[0]}
        _,issued=self.call('/api/admin/collectors',
            {'label':'Live V2 test'},headers=admin,expected=201)
        auth={'Authorization':'Bearer '+issued['credential']}
        server=str(uuid.uuid4())
        place=107778070777162
        global_egg={'egg_id':'G/uuid-global','egg_name':'Crowshade',
                    'rarity':'Mythic','biome':'Enchanted Forest',
                    'income_per_second':12345}
        halloween_egg={'egg_id':'H/uuid-halloween','egg_name':'Whiskers',
                       'rarity':'Epic','biome':'Halloween Z1',
                       'income_per_second':1234}
        snapshot={'server_id':server,'place_id':place,
                  'items':[global_egg,halloween_egg],
                  'scopes':['G','H']}
        _,result=self.call('/api/collect/snapshot',snapshot,headers=auth)
        self.assertEqual(result['accepted'],2)
        feed=self.call('/api/feed?server='+server,headers=admin)[1]
        self.assertEqual(feed['count'],2)
        self.assertEqual({r['rarity'] for r in feed['items']},{'Mythic','Epic'})
        snapshot['items']=[]
        snapshot['scopes']=['H']
        _,result=self.call('/api/collect/snapshot',snapshot,headers=auth)
        self.assertEqual(result['removed'],0)
        self.assertEqual(result['marked_absent'],1)
        feed=self.call('/api/feed?server='+server,headers=admin)[1]
        self.assertEqual({r['egg_id'] for r in feed['items']},{'G/uuid-global','H/uuid-halloween'})
        statuses={r['egg_id']:r['data_status'] for r in feed['items']}
        self.assertEqual(statuses['H/uuid-halloween'],'YA_NO_VISTO')
        self.assertEqual(statuses['G/uuid-global'],'VISTO_RECIENTEMENTE')
        snapshot['items']=[]
        snapshot['scopes']=['G']
        _,result=self.call('/api/collect/snapshot',snapshot,headers=auth)
        self.assertEqual(result['removed'],0)
        self.assertEqual(self.call('/api/feed?server='+server,headers=admin)[1]['count'],2)

    def test_feed_history_pagination(self):
        headers,_=self.call('/api/admin/login',{'password':'UnitTest-'+('a'*24)})
        admin={'Cookie':headers['Set-Cookie'].split(';')[0]}
        _,collector=self.call('/api/admin/collectors',{'label':'History tester'},
            headers=admin,expected=201)
        auth={'Authorization':'Bearer '+collector['credential']}
        server=str(uuid.uuid4())
        data={'server_id':server,'place_id':107778070777162,
              'items':[{'egg_id':'G/'+str(i),'egg_name':'Egg '+str(i),
                        'rarity':'Rare','biome':'Cherry Blossom'}
                       for i in range(3)]}
        self.call('/api/collect/snapshot',data,headers=auth)
        first=self.call('/api/feed?limit=2&offset=0&server='+server,headers=admin)[1]
        second=self.call('/api/feed?limit=2&offset=2&server='+server,headers=admin)[1]
        self.assertEqual(first['total_count'],3)
        self.assertEqual(first['count'],2)
        self.assertTrue(first['has_more'])
        self.assertEqual(second['count'],1)
        self.assertFalse(second['has_more'])
        self.assertEqual({x['egg_id'] for x in first['items']+second['items']},
                         {'G/0','G/1','G/2'})
        self.call('/api/feed?limit=501&server='+server,headers=admin,expected=400)
        self.call('/api/feed?detected_only=bad&server='+server,headers=admin,expected=400)
        _,detected=self.call('/api/feed?detected_only=1&server='+server,headers=admin)
        self.assertEqual(detected['count'],3)
        self.assertEqual(detected['total_count'],3)

    def test_v4_full_collector_route_is_separate(self):
        path=ROOT/'delta'/'PVFinder_V4_FullCollector.lua'
        with urllib.request.urlopen(self.base+'/bot-full.lua',timeout=4) as response:
            self.assertEqual(response.status,200)
            script=response.read()
        self.assertEqual(script,path.read_bytes())
        self.assertIn(b'ReadFieldEggs',script)
        self.assertIn(b'items=items,scopes=scopes',script)
        self.assertIn(b'PVFINDER_COLLECTOR_TOKEN',script)
        self.assertNotIn(b'chillihub.pro',script)

    def test_public_sales_page_has_current_plans_and_private_checkout(self):
        headers,html=self.call('/ventas')
        self.assertEqual(headers['Cache-Control'],'no-store')
        self.assertIn('Content-Security-Policy',headers)
        self.assertIn("script-src 'self'",headers['Content-Security-Policy'])
        self.assertRegex(html,r'<script src="/ventas\.js(?:\?[^"]*)?" defer></script>')
        self.assertNotIn('<script>',html)
        self.assertEqual(html.count('data-plan="'),3)
        for label in ('24 horas','7 días','30 días',
                      '$5.99','$29.99','$64.99'):
            self.assertIn(label,html)
        self.assertIn('data-plan="daily"',html)
        self.assertNotIn('Permanente',html)
        self.assertNotIn('Sin vencimiento',html)
        self.assertNotIn('data-plan="lifetime"',html)
        self.assertNotIn('$80',html)
        self.assertIn('discord.com/channels/1565963083212398804',html)
        self.assertIn('id="paypal-pay-link"',html)
        self.assertIn('id="after-payment"',html)
        self.assertIn('Envíame una captura del comprobante de pago en un ticket privado',html)
        self.assertIn('Enviar comprobante en un ticket',html)
        self.assertIn('Este aviso aparece al abrir PayPal',html)
        self.assertIn('https://paypal.me/PVFINSER0ficial',html)
        self.assertIn('confirma el dinero recibido',html.lower())
        self.assertIn('Esta web no cobra directamente',html)
        self.assertNotIn('pvf_session=',html)
        self.assertNotIn('PVFINDER_ADMIN_PASSWORD',html)
        self.assertEqual(self.call('/precios')[1],html)
        script_headers,script=self.call('/ventas.js')
        self.assertIn('javascript',script_headers['Content-Type'].lower())
        self.assertIn('navigator.clipboard',script)
        self.assertIn('https://paypal.me/PVFINSER0ficial',script)
        self.assertIn('paypalMeBase + "/" + String(amount) + "USD"',script)
        self.assertIn('const amount = Number(',script)
        self.assertIn('afterPayment.hidden = false',script)
        self.assertIn('afterPayment.hidden = true',script)
        self.assertNotIn('sk_test_',script)
        self.assertNotIn('client_secret',script)
        self.assertIn('button[data-plan]',script)
        self.assertNotIn('lifetime:',script)
        self.assertNotIn('Permanente',script)
        self.assertNotIn('pvf_session=',script)
        self.call('/api/feed',expected=401)
        self.call('/api/admin/overview',expected=401)

    def test_private_endpoints_and_files(self):
        for file in ('/server.py','/pvfinder.sqlite3','/.env','/SECURITY.md'):
            self.call(file,expected=404)
        self.call('/api/feed',expected=401)
        self.call('/api/admin/overview',expected=401)

    def test_universal_key_valid_for_web_and_delta_without_roblox_username(self):
        headers, _ = self.call('/api/admin/login',
            {'password':'UnitTest-'+('a'*24)})
        admin = {'Cookie':headers['Set-Cookie'].split(';')[0]}
        _, created = self.call('/api/editor/keys',
            {'action':'create', 'kind':'universal', 'days':7, 'label':'Cliente sin Roblox'},
            headers=admin,expected=201)
        self.assertTrue(created['key'].startswith('pvk_'))
        self.assertIsNone(created['roblox_user_id'])
        self.assertIsNone(created['roblox_username'])
        _, listing = self.call('/api/editor/keys',headers=admin)
        self.assertIn(created['id'], [key['id'] for key in listing['web_keys']])
        token = created['key']
        web_headers, web = self.call('/api/access/redeem', {'token':token})
        self.assertEqual(web['role'],'viewer')
        delta_headers, delta = self.call('/api/delta/redeem', {'token':token})
        self.assertEqual(delta['role'],'viewer')
        self.assertTrue(delta['session_token'].startswith('pvfs_'))
        # Even a different Roblox account can redeem a universal key.
        _, other = self.call('/api/delta/redeem',
            {'token':token,'user_id':99999999})
        self.assertEqual(other['role'],'viewer')
        self.assertEqual(self.call('/api/feed',
            headers={'Cookie':web_headers['Set-Cookie'].split(';')[0]})[0].get('Content-Type','').split(';')[0],
            'application/json')
        self.call('/api/feed',headers={
            'Authorization':'Bearer '+delta['session_token']})
        self.call('/api/editor/keys',{'action':'revoke','id':created['id']},
            headers=admin)
        self.call('/api/delta/redeem',{'token':token},expected=401)
        self.call('/api/feed',headers={
            'Authorization':'Bearer '+delta['session_token']},expected=401)

    def test_bots_dashboard_is_owner_only_and_reports_real_data(self):
        self.call('/api/admin/bots', expected=401)
        headers,html=self.call('/bots')
        self.assertIn('Content-Security-Policy',headers)
        self.assertIn("script-src 'self'",headers['Content-Security-Policy'])
        self.assertIn('/bots.js',html)
        self.assertIn('/bots.css',html)
        self.assertNotIn('pvf_session=',html)
        self.assertIn('Centro de bots',html)
        _,js=self.call('/bots.js')
        self.assertIn('/api/admin/bots',js)
        self.assertNotIn('PVFINDER_ADMIN_PASSWORD',js)

        # Create an admin-only fixture without consuming the production-style
        # login rate limit shared by this test suite's other login tests.
        token='owner-fixture-'+uuid.uuid4().hex
        with sqlite3.connect(str(Path(self.tmp.name)/'security-test.sqlite3')) as db:
            db.execute("""INSERT INTO sessions(token_hash,role,link_id,created_at,expires_at)
                          VALUES(?,?,?,?,?)""",
                       (hashlib.sha256(token.encode()).hexdigest(),'admin',None,
                        int(time.time()),int(time.time())+1800))
        owner={'Cookie':'pvf_session='+token}
        _,start=self.call('/api/admin/bots',headers=owner)
        self.assertIn('counts',start)
        self.assertIn('bots',start)
        self.assertIn('activity',start)
        self.assertEqual(len(start['activity']),12)
        self.assertEqual(start['active_window_seconds'],300)

        _,issued=self.call('/api/admin/collectors',
            {'label':'Bot privado prueba'},headers=owner,expected=201)
        cred={'Authorization':'Bearer '+issued['credential']}
        self.call('/api/collector/activity',
                  {'phase':'scanning','reason':'reading_sources'},headers=cred)
        job=str(uuid.uuid4())
        self.call('/api/collect/batch',{
            'items':[{'server_id':job,'egg_id':'egg-status-test',
              'place_id':107778070777162,'egg_name':'Huevo para el panel',
              'rarity':'Cosmic','biome':'Enchanted Forest',
              'income_per_second':10000,'income_type':'ESTIMADO'}]},
            headers=cred)
        _,stats=self.call('/api/admin/bots',headers=owner)
        self.assertGreaterEqual(stats['counts']['active_estimate'],1)
        self.assertGreaterEqual(stats['counts']['eggs_hour'],1)
        self.assertTrue(any(b['label']=='Bot privado prueba' and
             b['eggs_hour']>=1 and b['state']=='scanning'
             for b in stats['bots']))
        self.assertNotIn('credential',str(stats).lower())
        self.assertNotIn(issued['credential'],str(stats))

        _,viewer_link=self.call('/api/admin/links',
            {'label':'Solo visitante','expires_hours':1},
            headers=owner,expected=201)
        token=viewer_link['url'].rsplit('/',1)[-1]
        viewer_cookie,_=self.call('/api/access/redeem',{'token':token})
        self.call('/api/admin/bots',headers={
            'Cookie':viewer_cookie['Set-Cookie'].split(';')[0]},expected=401)
        self.call('/api/admin/bots',headers=cred,expected=401)

    def test_viewer_cannot_become_admin_and_feed_redacts_internal_ids(self):
        headers,_=self.call('/api/admin/login',
            {'password':'UnitTest-'+('a'*24)},
            headers={'X-Forwarded-Proto':'https'})
        cookie=headers['Set-Cookie']
        self.assertIn('HttpOnly',cookie)
        self.assertIn('Secure',cookie)
        login_cookie={'Cookie':cookie.split(';')[0]}
        _,collector=self.call('/api/admin/collectors',{'label':'Automated test'},
            headers=login_cookie,expected=201)
        _,access=self.call('/api/admin/links',
            {'label':'Viewer test','expires_hours':1,'max_uses':2},
            headers=login_cookie,expected=201)
        server=str(uuid.uuid4())
        _,collected=self.call('/api/collect/batch',
            {'items':[{'server_id':server,'egg_id':'test-egg',
                'place_id':107778070777162,'egg_name':'Spirit Panda',
                'rarity':'Cosmic','biome':'Enchanted Forest',
                'income_per_second':150000000,'income_type':'ESTIMADO'}]},
            headers={'Authorization':'Bearer '+collector['credential']})
        self.assertEqual(collected['accepted'],1)
        token=access['url'].rsplit('/',1)[-1]
        _,viewer=self.call('/api/delta/redeem',{'token':token})
        bearer={'Authorization':'Bearer '+viewer['session_token']}
        _,feed=self.call('/api/feed?server='+server,headers=bearer)
        self.assertEqual(feed['count'],1)
        self.assertEqual(feed['items'][0]['egg_name'],'Spirit Panda')
        _,recent=self.call('/api/feed?recent_seconds=90&server='+server,headers=bearer)
        self.assertEqual(recent['count'],1)
        self.call('/api/feed?recent_seconds=91&server='+server,headers=bearer,expected=400)
        self.assertNotIn('collector_id',feed['items'][0])
        self.assertNotIn('first_seen',feed['items'][0])
        self.call('/api/admin/overview',headers=bearer,expected=401)


if __name__=='__main__':
    unittest.main()
