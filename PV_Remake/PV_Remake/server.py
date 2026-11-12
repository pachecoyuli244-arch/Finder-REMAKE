#!/usr/bin/env python3
"""PVFINDER minimal self-hosted backend; stdlib only (Python 3.10+)."""
import os, sys, json, time, uuid, hmac, hashlib, secrets, sqlite3, threading, mimetypes, re
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from datetime import datetime
from contextlib import closing
import base64, gzip, shutil, tempfile
from urllib.request import urlopen
from urllib.parse import urlparse, parse_qs, urlencode
from http.cookies import SimpleCookie
import hop_coordinator
import coowner_access
import bot_dashboard
import payments

ROOT=Path(__file__).resolve().parent


def prepare_radar_styles(path):
    """Keep the CSS small. The browser downloads only images it uses."""
    try:
        content=path.read_bytes()
    except FileNotFoundError:
        return None, {}
    images={}
    def extract(match):
        body=base64.b64decode(match[1],validate=True)
        name=hashlib.sha256(body).hexdigest()+'.webp'
        images[name]=body
        return b'/media/radar/'+name.encode('ascii')
    content=re.sub(rb'data:image/webp;base64,([A-Za-z0-9+/]+={0,2})',extract,content)
    return content, images


radar_styles,radar_images=prepare_radar_styles(ROOT/'web'/'styles.css')
radar_styles_gzip=gzip.compress(radar_styles,compresslevel=5,mtime=0) if radar_styles else None

DATA=Path(os.environ.get('PVFINDER_DB', str(ROOT/'pvfinder.sqlite3')))
HOST=os.environ.get('PVFINDER_HOST','127.0.0.1')
PORT=int(os.environ.get('PVFINDER_PORT','8765'))
ADMIN_PASSWORD=os.environ.get('PVFINDER_ADMIN_PASSWORD','')
OWNER_KEY_HASH=os.environ.get('PVFINDER_OWNER_KEY_HASH','')
STAFF_COOKIE_MAX_AGE=400*86400
OWNER_SESSION_PREFIX='pvfo_session_'
SECURE_COOKIES=os.environ.get('PVFINDER_SECURE_COOKIES','0')=='1'
PUBLIC_URL=os.environ.get('PVFINDER_PUBLIC_URL','').rstrip('/')
TTL=int(os.environ.get('PVFINDER_TTL_SECONDS','600'))
RADAR_CYCLE_SECONDS=300
FRESH_SECONDS=max(15,min(3600,int(os.environ.get('PVFINDER_FRESH_SECONDS','90'))))
# Read-only access for the keyless Delta viewer; admin and collector routes stay protected.
PUBLIC_FEED_ENABLED=os.environ.get('PVFINDER_PUBLIC_FEED','0')=='1'
RARITIES={'Common','Uncommon','Rare','Epic','Legendary','Mythic','Cosmic','Secret','Eternal','Divine'}
# Registro sin keys MANUALES, desactivado hasta configurarlo en el VPS.
AUTO_COLLECTORS_ENABLED=os.environ.get('PVFINDER_AUTO_COLLECTORS','0')=='1'
AUTO_SESSION_SECONDS=6*3600
AUTO_MAX_ACTIVE=max(1,min(2000,int(os.environ.get('PVFINDER_AUTO_MAX_ACTIVE','250'))))
AUTO_REGISTRATIONS_PER_IP=max(1,min(500,int(os.environ.get('PVFINDER_AUTO_REGISTRATIONS_PER_IP','60'))))
lock=threading.RLock()
radar_changed=threading.Condition(lock)
radar_waiters=threading.BoundedSemaphore(16)
rate_buckets={}

if not ADMIN_PASSWORD or len(ADMIN_PASSWORD)<12:
    sys.exit('Configura PVFINDER_ADMIN_PASSWORD con 12+ caracteres antes de iniciar.')

DATA.parent.mkdir(parents=True,exist_ok=True)
DB=sqlite3.connect(DATA, check_same_thread=False, isolation_level=None)
DB.row_factory=sqlite3.Row
DB.execute('PRAGMA journal_mode=WAL')
DB.execute('PRAGMA foreign_keys=ON')
DB.executescript('''
CREATE TABLE IF NOT EXISTS access_links(
 id TEXT PRIMARY KEY, label TEXT NOT NULL, token_hash TEXT UNIQUE NOT NULL,
 created_at INTEGER NOT NULL, expires_at INTEGER, max_uses INTEGER,
 uses INTEGER NOT NULL DEFAULT 0, revoked_at INTEGER
);
CREATE TABLE IF NOT EXISTS sessions(
 token_hash TEXT PRIMARY KEY, role TEXT NOT NULL, link_id TEXT,
 created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL,
 FOREIGN KEY(link_id) REFERENCES access_links(id)
);
CREATE TABLE IF NOT EXISTS collectors(
 id TEXT PRIMARY KEY, label TEXT NOT NULL, token_hash TEXT UNIQUE NOT NULL,
 created_at INTEGER NOT NULL, last_seen INTEGER, revoked_at INTEGER
);
CREATE TABLE IF NOT EXISTS detections(
 id TEXT PRIMARY KEY, server_id TEXT NOT NULL, egg_id TEXT NOT NULL,
 place_id INTEGER,
 collector_id TEXT NOT NULL, egg_name TEXT NOT NULL,
 rarity TEXT, biome TEXT, income_per_second REAL, income_type TEXT NOT NULL,
 weight_kg REAL, mutation TEXT, multiplier REAL, seen_at INTEGER NOT NULL,
 first_seen INTEGER NOT NULL, updated_at INTEGER NOT NULL,
 presence_state TEXT NOT NULL DEFAULT 'SIN_CONFIRMAR', checked_at INTEGER,
 UNIQUE(server_id,egg_id), FOREIGN KEY(collector_id) REFERENCES collectors(id)
);
CREATE INDEX IF NOT EXISTS detections_updated ON detections(updated_at DESC);
CREATE INDEX IF NOT EXISTS detections_rarity ON detections(rarity);
CREATE TABLE IF NOT EXISTS radar_sync(
 id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER NOT NULL
);
INSERT OR IGNORE INTO radar_sync VALUES(1,0);
CREATE TABLE IF NOT EXISTS collector_activity(
 collector_id TEXT PRIMARY KEY REFERENCES collectors(id),
 phase TEXT NOT NULL, reason TEXT NOT NULL, signal_at INTEGER NOT NULL,
 last_pause_reason TEXT, last_pause_at INTEGER
);
CREATE TABLE IF NOT EXISTS radar_server_scans(
 cycle_start INTEGER NOT NULL, place_id INTEGER NOT NULL, server_id TEXT NOT NULL,
 PRIMARY KEY(cycle_start,place_id,server_id)
);
CREATE TABLE IF NOT EXISTS auto_collector_sessions (
 token_hash TEXT PRIMARY KEY,
 collector_id TEXT NOT NULL REFERENCES collectors(id),
 created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS auto_collector_sessions_expiry ON auto_collector_sessions(expires_at);
''')
hop_coordinator.install(DB)
coowner_access.install(DB)
# Limpieza puntual de llaves de clientes solicitada por el propietario.
# Nunca toca collectors, auto_collector_sessions, sesiones admin ni su clave Owner.
# La marca persistente permite emitir llaves nuevas sin que se vuelvan a revocar al reiniciar.
def revoke_customer_keys_once():
    marker = 'owner_customer_key_reset_2026_11_09'
    DB.execute("""CREATE TABLE IF NOT EXISTS pvfinder_maintenance (
        id TEXT PRIMARY KEY, completed_at INTEGER NOT NULL,
        affected_keys INTEGER NOT NULL, affected_sessions INTEGER NOT NULL
    )""")
    DB.execute('BEGIN IMMEDIATE')
    try:
        previous = DB.execute(
            'SELECT affected_keys,affected_sessions FROM pvfinder_maintenance WHERE id=?',
            (marker,)).fetchone()
        if previous:
            DB.execute('COMMIT')
            print('[KEY RESET] Ya aplicado; las keys nuevas permanecen intactas.',flush=True)
            return
        stamp = int(time.time())
        keys = DB.execute(
            'SELECT COUNT(*) FROM access_links WHERE revoked_at IS NULL').fetchone()[0]
        sessions = DB.execute(
            "SELECT COUNT(*) FROM sessions WHERE role='viewer'").fetchone()[0]
        DB.execute('UPDATE access_links SET revoked_at=? WHERE revoked_at IS NULL',(stamp,))
        DB.execute("DELETE FROM sessions WHERE role='viewer'")
        DB.execute(
            'INSERT INTO pvfinder_maintenance VALUES(?,?,?,?)',
            (marker,stamp,keys,sessions))
        DB.execute('COMMIT')
    except Exception:
        DB.execute('ROLLBACK')
        raise
    print(f'[KEY RESET] Llaves de clientes revocadas: {keys}; sesiones viewer cerradas: {sessions}; bots intactos.',flush=True)

revoke_customer_keys_once()
# Compatible con bases v1 existentes: agregar el campo sin borrar detecciones.
columns={row[1] for row in DB.execute('PRAGMA table_info(detections)')}
if 'place_id' not in columns:
    DB.execute('ALTER TABLE detections ADD COLUMN place_id INTEGER')
if 'presence_state' not in columns:
    DB.execute("ALTER TABLE detections ADD COLUMN presence_state TEXT NOT NULL DEFAULT 'SIN_CONFIRMAR'")
if 'checked_at' not in columns:
    DB.execute('ALTER TABLE detections ADD COLUMN checked_at INTEGER')

if 'radar_revision' not in columns:
    DB.execute("ALTER TABLE detections ADD COLUMN radar_revision INTEGER NOT NULL DEFAULT 0")
DB.execute("CREATE INDEX IF NOT EXISTS detections_radar_revision ON detections(radar_revision,id)")

def radar_revision():
    return DB.execute('SELECT revision FROM radar_sync WHERE id=1').fetchone()[0]

def advance_radar_revision():
    DB.execute('UPDATE radar_sync SET revision=revision+1 WHERE id=1')
    return radar_revision()

def valid_place_id(value):
    if isinstance(value, bool) or value is None: return None
    if isinstance(value, int): n=value
    elif isinstance(value, str) and value.isascii() and value.isdecimal(): n=int(value)
    else: raise ValueError('place_id debe ser un entero positivo')
    if n<1 or n>9007199254740991: raise ValueError('place_id fuera de rango')
    return n

def valid_job_id(value):
    try:
        return str(uuid.UUID(value)) if isinstance(value,str) and len(value)==36 else None
    except (ValueError,AttributeError): return None

def build_join_url(place_id, job_id):
    # El enlace web puede ignorar gameInstanceId; el protocolo abre la instancia indicada.
    if not place_id: return None
    valid=valid_job_id(job_id)
    if not valid: return None
    return 'roblox://placeId='+str(place_id)+'&gameInstanceId='+valid

def digest(token): return hashlib.sha256(token.encode('utf8')).hexdigest()
def now(): return int(time.time())

def owner_session_hash(token):
    # Rotating the owner key invalidates all of its existing persistent sessions.
    if token.startswith(OWNER_SESSION_PREFIX):
        return digest(OWNER_KEY_HASH+':'+token)
    return digest(token)

def radar_cycle_start(timestamp):
    return timestamp//RADAR_CYCLE_SECONDS*RADAR_CYCLE_SECONDS

def record_radar_scans(db,timestamp,servers):
    cycle_start=radar_cycle_start(timestamp)
    db.executemany('INSERT OR IGNORE INTO radar_server_scans VALUES(?,?,?)',
                   ((cycle_start,place,server) for place,server in servers))
    db.execute('DELETE FROM radar_server_scans WHERE cycle_start<?',
               (cycle_start-RADAR_CYCLE_SECONDS,))
def rowdict(row): return dict(row) if row else None

def strval(x,maxlen=120):
    if not isinstance(x,str): return ''
    return x.strip()[:maxlen]

def numval(x):
    if x is None or x=='': return None
    if isinstance(x,bool): raise ValueError('Numero invalido')
    v=float(x)
    if not (0 <= v < 1e18): raise ValueError('Numero fuera de rango')
    return v

def check_rate(key,limit=120,window=60):
    # Limites en memoria para evitar agotamiento por identificadores aleatorios.
    t=time.monotonic()
    with lock:
        if len(rate_buckets)>4096:
            expired=[k for k,ts in rate_buckets.items()
                     if not ts or t-ts[-1]>max(window,120)]
            for k in expired: rate_buckets.pop(k,None)
            if len(rate_buckets)>4096:
                oldest=sorted(rate_buckets,
                              key=lambda k:rate_buckets[k][-1])[:1024]
                for k in oldest: rate_buckets.pop(k,None)
        times=[x for x in rate_buckets.get(key,[]) if t-x<window]
        if len(times)>=limit: return False
        times.append(t); rate_buckets[key]=times
    return True

ROBLOX_EVENTS_URL='https://apis.roblox.com/virtual-events/v1/universes/10563114921/virtual-events?limit=100'
event_cache_lock=threading.Lock()
event_cache=(0,())

def official_radar_events(ts):
    global event_cache
    with event_cache_lock:
        expires,events=event_cache
        if ts>=expires:
            try:
                with urlopen(ROBLOX_EVENTS_URL,timeout=3) as response:
                    payload=json.loads(response.read(500_000))
                events=[]
                for event in payload['data']:
                    if (event.get('universeId')!=10563114921 or event.get('eventVisibility')!='public'
                            or event.get('eventStatus')!='active'):
                        continue
                    dates=event['eventTime']
                    start=int(datetime.fromisoformat(dates['startUtc']).timestamp())
                    end=int(datetime.fromisoformat(dates['endUtc']).timestamp())
                    if start>=end or end<=ts:
                        continue
                    title=str(event.get('displayTitle') or event.get('title') or '').strip()[:120]
                    if title:
                        events.append({'title':title,'start':start,'end':end})
                event_cache=(ts+300,events)
            except (OSError,ValueError,KeyError,TypeError,AttributeError):
                event_cache=(ts+60,events)
        return sorted((e for e in events if e['end']>ts and e['start']<=ts+7*86400),
                      key=lambda e:e['start'])[:5]

COLLECTOR_PHASES={
    'scanning': {'reading_sources', 'sending_snapshot'},
    'moving': {'looking_for_server', 'teleport_requested'},
    'paused': {'roblox_flooded', 'roblox_http_limit', 'roblox_api_error',
               'teleport_failed', 'no_candidates', 'session_error',
               'coordinator_error', 'sources_unavailable', 'snapshot_rejected',
               'snapshot_error', 'too_many_detections', 'no_auto_resume'},
}

def radar_collectors(ts):
    with lock:
        rows=DB.execute("""
            SELECT c.id,c.last_seen,a.phase,a.reason,a.signal_at,
                   a.last_pause_reason,a.last_pause_at
            FROM collectors c LEFT JOIN collector_activity a ON c.id=a.collector_id
            WHERE c.revoked_at IS NULL AND (
                c.last_seen>=? OR a.signal_at>=? OR EXISTS (
                    SELECT 1 FROM auto_collector_sessions s
                    WHERE s.collector_id=c.id AND s.expires_at>?
                )
            )
            ORDER BY max(coalesce(a.signal_at,0),coalesce(c.last_seen,0)) DESC,c.id
        """,(ts-86400,ts-86400,ts)).fetchall()
    bots=[]
    for row in rows:
        if (row['signal_at'] or 0)>=ts-90:
            state=row['phase']
        elif (row['last_seen'] or 0)>=ts-300:
            state='recent_report'
        else:
            state='silent'
        bots.append({
            'label':'Bot '+digest(row['id'])[:8].upper(),
            'state':state,'reason':row['reason'] if state==row['phase'] else None,
            'signal_at':row['signal_at'],'last_scan_at':row['last_seen'],
            'last_pause_reason':row['last_pause_reason'],'last_pause_at':row['last_pause_at'],
        })
    return bots

def export_portable_database(destination):
    """Copy application content and scan history into a fresh DB with no live credentials."""
    path=DATA.resolve().as_uri()+'?mode=ro'
    tables=('collectors','detections','radar_sync','radar_server_scans',
            'collector_activity','site_content','site_branding','site_edit_log')
    with closing(sqlite3.connect(path,uri=True)) as source, closing(sqlite3.connect(destination)) as target:
        source.execute('BEGIN')
        target.execute('PRAGMA foreign_keys=ON')
        for table in tables:
            schema=source.execute(
                'SELECT sql FROM sqlite_master WHERE type=? AND name=?',('table',table)).fetchone()[0]
            target.execute(schema)
            if table=='collectors':
                rows=((id,'Histórico '+id[:8],secrets.token_hex(32),created,seen,revoked or now())
                      for id,created,seen,revoked in source.execute(
                          'SELECT id,created_at,last_seen,revoked_at FROM collectors'))
            else:
                rows=source.execute('SELECT * FROM '+table)
            columns=target.execute('PRAGMA table_info('+table+')').fetchall()
            target.executemany('INSERT INTO '+table+' VALUES('+','.join('?' for _ in columns)+')',rows)
        target.commit()

class Handler(BaseHTTPRequestHandler):
    server_version='PVFINDER/1.1'
    def log_message(self,fmt,*args):
        # Do not log request URLs: private access tokens may appear in URLs.
        print('[HTTP]',self.command,self.path.split('?')[0].split('/')[1:2],str(args[-1]) if args else '')
    def is_https(self):
        # Render termina TLS en el proxy; el backend recibe HTTP interno.
        forwarded=self.headers.get('X-Forwarded-Proto','').split(',')[0].strip().lower()
        return (SECURE_COOKIES or forwarded=='https' or
            PUBLIC_URL.startswith('https://') or
            os.environ.get('RENDER_EXTERNAL_URL','').startswith('https://'))
    def secure_headers(self,is_html=False,cache_control='no-store'):
        self.send_header('Cache-Control',cache_control)
        self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Referrer-Policy','no-referrer')
        self.send_header('X-Frame-Options','DENY')
        self.send_header('Permissions-Policy',
            'camera=(), microphone=(), geolocation=(), payment=()')
        if self.is_https():
            self.send_header('Strict-Transport-Security','max-age=31536000')
        if is_html:
            self.send_header('Content-Security-Policy',
                "default-src 'none'; script-src 'self'; "
                "style-src 'self' 'unsafe-inline'; img-src 'self' data:; "
                "connect-src 'self'; font-src 'self'; "
                "frame-ancestors 'none'; base-uri 'none'; "
                "form-action 'self'; object-src 'none'")
    def respond(self,status,obj=None,cookie=None):
        out=json.dumps(obj if obj is not None else {},ensure_ascii=False,separators=(',',':')).encode()
        self.send_response(status)
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.secure_headers()
        if cookie:self.send_header('Set-Cookie',cookie)
        self.send_header('Content-Length',str(len(out)))
        self.end_headers();self.wfile.write(out)
    def cookie_token(self):
        cookies=SimpleCookie()
        try:
            cookies.load(self.headers.get('Cookie',''))
        except Exception:
            return None
        token=cookies.get('pvf_session')
        return token.value if token else None

    def cookie(self,value='',max_age=0):
        opts='; HttpOnly; SameSite=Strict; Path=/; Max-Age='+str(max_age)
        if self.is_https():opts+='; Secure'
        return 'pvf_session='+value+opts
    def body(self):
        size=int(self.headers.get('Content-Length','0'))
        if size<1 or size>256000: raise ValueError('Tamaño de solicitud no permitido')
        data=json.loads(self.rfile.read(size))
        return data
    def session(self):
        token=self.cookie_token()
        if not token:return None
        with lock:
            record=DB.execute('''SELECT s.role,s.link_id,s.expires_at,l.expires_at AS lexpires,l.revoked_at
                FROM sessions s LEFT JOIN access_links l ON s.link_id=l.id
                WHERE s.token_hash=?''',(owner_session_hash(token),)).fetchone()
        if not record:return None
        persistent=record['expires_at']==0 and record['role'] in ('admin','coowner')
        if not persistent and record['expires_at']<=now():return None
        if record['role']=='viewer' and (record['revoked_at'] or (record['lexpires'] and record['lexpires']<=now())):return None
        if record['role']=='coowner':
            with lock:
                active=DB.execute("SELECT revoked_at FROM coowners WHERE id='primary'").fetchone()
            if not active or active['revoked_at'] is not None:return None
        return {**dict(record),'persistent':persistent}
    def require(self,role=None):
        s=self.session()
        if not s or (role and s['role']!=role):
            self.respond(401,{'error':'Acceso no autorizado'});return None
        return s
    def delta_viewer_session(self):
        # Solo sesiones viewer emitidas mediante /api/delta/redeem.
        # No permite autenticar rutas administrativas ni recolectores.
        header=self.headers.get('Authorization','')
        if not header.startswith('Bearer pvfs_'):return None
        token=header[7:].strip()
        if len(token)>200:return None
        with lock:
            record=DB.execute('''SELECT s.role,s.link_id,s.expires_at,
                l.expires_at AS lexpires,l.revoked_at,l.roblox_user_id
                FROM sessions s JOIN access_links l ON s.link_id=l.id
                WHERE s.token_hash=? AND s.role='viewer' ''',(digest(token),)).fetchone()
        if not record or record['expires_at']<=now():return None
        if record['revoked_at'] or (record['lexpires'] and record['lexpires']<=now()):return None
        if record['roblox_user_id'] is not None:
            try:
                if coowner_access.uid(self.headers.get('X-Roblox-UserId'))!=record['roblox_user_id']:return None
            except (ValueError,TypeError):return None
        return dict(record)
    def collector(self):
        header=self.headers.get('Authorization','')
        if not header.startswith('Bearer '):return None
        token=header[7:].strip()
        if not token or len(token)>180:return None
        with lock:
            r=DB.execute('SELECT id,label FROM collectors WHERE token_hash=? AND revoked_at IS NULL',(digest(token),)).fetchone()
            if not r and token.startswith('pvfa_'):
                r=DB.execute('''SELECT c.id,c.label FROM auto_collector_sessions a
                    JOIN collectors c ON c.id=a.collector_id
                    WHERE a.token_hash=? AND a.expires_at>? AND c.revoked_at IS NULL''',
                    (digest(token),now())).fetchone()
        return rowdict(r)
    def do_GET(self):
        p=urlparse(self.path)
        if p.path=='/api/health':return self.respond(200,{'ok':True,'service':'PVFINDER','status':'running'})
        if p.path=='/api/payments/status':return self.respond(200,payments.status(PUBLIC_URL))
        if p.path in ('/api/site/content','/api/editor/site','/api/editor/site/history','/api/branding/meta','/api/branding/logo','/api/branding/hero','/api/editor/keys'):
            return coowner_access.handle_get(self,p.path,DB,lock,now)
        if p.path=='/api/me':
            session=self.session()
            persistent=bool(session and session['persistent'])
            expires=min(session['expires_at'],session['lexpires'] or session['expires_at']) if session and not persistent else None
            cookie=self.cookie(self.cookie_token(),STAFF_COOKIE_MAX_AGE) if persistent else None
            return self.respond(200,{'authenticated':bool(session),'role':session['role'] if session else None,
                                     'persistent':persistent,'expires_at':expires,'server_time':now()},cookie)
        
        if p.path=='/api/radar/events':
            if not PUBLIC_FEED_ENABLED and not (self.session() or self.delta_viewer_session()):
                return self.respond(401,{'error':'Acceso no autorizado'})
            return self.respond(200,{'events':official_radar_events(now())})
        if p.path=='/api/radar/collectors':
            if not PUBLIC_FEED_ENABLED and not (self.session() or self.delta_viewer_session()):
                return self.respond(401,{'error':'Acceso no autorizado'})
            identity=self.headers.get('Cookie','')[:512] or str(self.client_address[0])
            if not check_rate('radar-bots:'+digest(identity),30,60):
                return self.respond(429,{'error':'Límite de consultas del radar'})
            ts=now()
            return self.respond(200,{'bots':radar_collectors(ts),'server_time':ts})

        if p.path=='/api/feed':
            if not PUBLIC_FEED_ENABLED and not (self.session() or self.delta_viewer_session()):
                return self.respond(401,{'error':'Acceso no autorizado'})
            # 60 queries/minute per viewer; public visitors cannot all share
            # the same anonymous rate-limit bucket.
            identity=(self.headers.get('Authorization','') or
                      self.headers.get('Cookie',''))[:512]
            if not identity:
                identity='anonymous:'+str(self.client_address[0])
            if not check_rate('feed:'+digest(identity),60,60):
                return self.respond(429,{'error':'Límite de consultas al Live Feed'})

            params=parse_qs(p.query)
            cycle_mode=params.get('radar_cycle',[''])[0]=='1'
            cycle_start=radar_cycle_start(now()) if cycle_mode else None
            cursor=params.get('after',[''])[0] if cycle_mode else ''
            if cursor and not re.fullmatch('[0-9a-f]{32}',cursor):
                return self.respond(400,{'error':'Cursor de radar inválido'})
            delta_mode=cycle_mode and params.get('sync',[''])[0]=='1'
            since=pinned=0
            if delta_mode:
                revision_params=[params.get(k,[d])[0] for k,d in (
                    ('since','0'),('through','0'),('sync_cycle','0'))]
                if any(not re.fullmatch(r'[0-9]{1,16}',value) for value in revision_params):
                    return self.respond(400,{'error':'Revisión del radar inválida'})
                since,pinned,client_cycle=map(int,revision_params)
                if cursor and client_cycle!=cycle_start:
                    return self.respond(409,{'error':'El ciclo del radar cambió'})
                if since and client_cycle==cycle_start and not cursor and params.get('wait',[''])[0]=='1':
                    if radar_waiters.acquire(blocking=False):
                        try:
                            with radar_changed:
                                radar_changed.wait_for(
                                    lambda: radar_revision()!=since or radar_cycle_start(now())!=client_cycle,
                                    timeout=min(12,max(0,client_cycle+RADAR_CYCLE_SECONDS-now())))
                        finally:
                            radar_waiters.release()
                        if not PUBLIC_FEED_ENABLED and not (self.session() or self.delta_viewer_session()):
                            return self.respond(401,{'error':'Acceso no autorizado'})
                cycle_start=radar_cycle_start(now())
                if cursor and client_cycle!=cycle_start:
                    return self.respond(409,{'error':'El ciclo del radar cambió'})
                if client_cycle!=cycle_start:
                    since=pinned=0
            rarity=strval(params.get('rarity',[''])[0],20)
            zone=strval(params.get('biome',[''])[0],70)
            server=strval(params.get('server',[''])[0],120)
            # Historico completo. Los filtros recientes siguen disponibles solo
            # para clientes antiguos que los solicitan expresamente.
            recent=strval(params.get('recent_seconds',[''])[0],8)
            if recent and recent not in ('30','90'):
                return self.respond(400,{'error':'Ventana reciente invalida'})
            detected_only=params.get('detected_only',['0'])[0]
            if detected_only not in ('0','1'):
                return self.respond(400,{'error':'Filtro detectados invalido'})
            presence_filter=params.get('presence',[''])[0]
            if presence_filter not in ('','absent'):
                return self.respond(400,{'error':'Filtro de presencia inválido'})
            if presence_filter=='absent' and detected_only=='1':
                return self.respond(400,{'error':'Filtros de presencia incompatibles'})
            sort=params.get('sort',[''])[0]
            if sort not in ('','recent'):
                return self.respond(400,{'error':'Orden de reportes inválido'})
            raw_limit=strval(params.get('limit',['250'])[0],8)
            raw_offset=strval(params.get('offset',['0'])[0],12)
            if not (raw_limit.isascii() and raw_limit.isdecimal()
                    and raw_offset.isascii() and raw_offset.isdecimal()):
                return self.respond(400,{'error':'Paginacion invalida'})
            limit=int(raw_limit)
            offset=int(raw_offset)
            if not 1<=limit<=500 or offset>10000000:
                return self.respond(400,{'error':'Paginacion fuera de rango'})
            
            wh=["(LOWER(COALESCE(biome,'')) <> 'prehistoric' OR LOWER(TRIM(egg_name))='mosasaurus')"]
            args=[]
            if params.get('alien_min_secret',[''])[0]=='1':
                wh.append("""(LOWER(TRIM(COALESCE(biome,''))) NOT IN ('alien','alien zone','zona alien')
                    OR LOWER(TRIM(rarity)) IN ('secret','eternal','divine'))""")
            if cycle_mode:
                wh.append("(updated_at>=? OR (presence_state='AUSENTE_REPORTADO' AND checked_at>=?))")
                args.extend((cycle_start,cycle_start))
                requested=params.get('species',[''])[0]
                include_alien=params.get('include_alien',[''])[0]=='1'
                if requested:
                    species=list(dict.fromkeys(name.strip().lower() for name in requested.split(',') if name.strip()))
                    if not species or len(species)>40 or any(len(name)>100 for name in species):
                        return self.respond(400,{'error':'Lista de huevos inválida'})
                    species_filter='LOWER(TRIM(egg_name)) IN ('+','.join('?' for _ in species)+')'
                    if include_alien:
                        species_filter="("+species_filter+" OR LOWER(TRIM(biome)) IN ('alien','alien zone','zona alien'))"
                    wh.append(species_filter)
                    args.extend(species)
                wh.append("presence_state IN ('PRESENTE_REPORTADO','REPORTE_PUNTUAL','AUSENTE_REPORTADO')")
            elif detected_only=='1':
                # Solo reportes recientes que no fueron marcados ausentes.
                # No confundir observacion reportada con disponibilidad garantizada.
                wh.append('updated_at>=?')
                args.append(now()-FRESH_SECONDS)
                wh.append("presence_state IN ('PRESENTE_REPORTADO','REPORTE_PUNTUAL')")
            if presence_filter=='absent':
                wh.append("presence_state='AUSENTE_REPORTADO'")
            if recent:
                wh.append('first_seen>=?')
                args.append(now()-int(recent))
            if rarity:
                wh.append('rarity=?')
                args.append(rarity)
            if zone:
                wh.append('biome=?')
                args.append(zone)
            if server:
                wh.append('server_id=?')
                args.append(server)
            
            # El TTL solo determina estado reciente, nunca borra ni oculta historial.
            order_by=("id ASC" if cycle_mode else "COALESCE(checked_at, updated_at) DESC, id DESC" if presence_filter=='absent'
                      else "updated_at DESC, id DESC" if sort=='recent'
                      else "(income_per_second IS NULL), income_per_second DESC, updated_at DESC, id DESC")
            with lock:
                if delta_mode:
                    revision=radar_revision()
                    if pinned>revision or (pinned and pinned<since):
                        return self.respond(409,{'error':'La revisión del radar cambió'})
                    if since>revision:
                        since=0
                    revision=pinned or revision
                    wh.append('radar_revision<=?')
                    args.append(revision)
                    if since:
                        wh.append('radar_revision>?')
                        args.append(since)
                condition=' AND '.join(wh)
                query="""
                SELECT id,server_id, egg_id, place_id,
                    egg_name, rarity, biome,
                    income_per_second, income_type,
                    weight_kg, mutation, multiplier, updated_at,
                    presence_state, checked_at
                FROM detections
                WHERE """+condition+(" AND id>?" if cursor else "")+"""
                ORDER BY """+order_by+"""
                LIMIT ? OFFSET ?
            """
                total=None if delta_mode else DB.execute(
                    'SELECT COUNT(*) FROM detections WHERE '+condition,args).fetchone()[0]
                if cycle_mode:
                    scanned=DB.execute('SELECT COUNT(*) FROM radar_server_scans WHERE cycle_start=?',
                                       (cycle_start,)).fetchone()[0]
                    page_args=args+([cursor] if cursor else [])+[limit+1,0]
                    rec=DB.execute(query,page_args).fetchall()
                    next_cursor=rec[limit-1]['id'] if len(rec)>limit else None
                    rec=rec[:limit]
                else:
                    rec=DB.execute(query,args+[limit,offset]).fetchall()
            
            feed=[]
            response_time=now()
            cutoff=response_time-FRESH_SECONDS
            for row in rec:
                obj=dict(row)
                # Los reportes antiguos pueden carecer de PlaceId aunque el
                # coordinador ya conozca la instancia. Recuperarlo SOLO si
                # existe evidencia del mismo JobId en nuestra base de datos.
                if not obj.get('place_id') and valid_job_id(obj.get('server_id')):
                    with lock:
                        known_place=DB.execute(
                            'SELECT place_id FROM pvf_hop_jobs WHERE server_id=? '
                            'ORDER BY updated_at DESC LIMIT 1',
                            (obj['server_id'],)).fetchone()
                        if not known_place:
                            known_place=DB.execute(
                                'SELECT place_id FROM radar_server_scans WHERE server_id=? '
                                'ORDER BY cycle_start DESC LIMIT 1',
                                (obj['server_id'],)).fetchone()
                    if known_place:
                        obj['place_id']=known_place['place_id']
                obj.pop('id',None)
                # Timestamps reflect when the backend received the report,
                # not a guaranteed in-game observation at this instant.
                obj['report_received_at']=obj['updated_at']
                obj['report_age_seconds']=max(0,response_time-int(obj['updated_at']))
                obj['availability_confirmed']=False
                obj['income_provenance']=(
                    'CALCULADO' if obj['income_type']=='ESTIMADO' else
                    'DECLARADO_POR_RECOLECTOR' if obj['income_type']=='DIRECTO' else
                    'NO_VERIFICADO' if obj['income_per_second'] is not None else
                    'NO_DISPONIBLE')
                state=obj['presence_state']
                if state=='AUSENTE_REPORTADO':
                    obj['data_status']='YA_NO_VISTO'
                elif obj['updated_at']<cutoff and not cycle_mode:
                    obj['data_status']='HISTORICO'
                elif state=='PRESENTE_REPORTADO':
                    obj['data_status']='VISTO_RECIENTEMENTE'
                elif state=='REPORTE_PUNTUAL':
                    obj['data_status']='REPORTE_RECIENTE'
                else:
                    obj['data_status']='SIN_CONFIRMAR'
                obj['join_url']=build_join_url(obj.get('place_id'),obj.get('server_id'))
                obj['join_status']=(
                    'REPORTADO_RECIENTEMENTE' if obj['data_status']=='VISTO_RECIENTEMENTE'
                    else 'NO_VERIFICADO'
                )
                feed.append(obj)
            next_offset=offset+len(feed)
            return self.respond(200,{
                'items':feed, 'ttl_seconds':TTL, 'fresh_seconds':FRESH_SECONDS,
                'count':len(feed), 'total_count':total,
                'has_more':bool(next_cursor) if cycle_mode else next_offset<total,
                'next_offset':next_offset,
                **({'cycle_start':cycle_start,'next_cursor':next_cursor,'scanned_servers':scanned}
                   if cycle_mode else {}),
                **({'sync_revision':revision,'delta':bool(since)} if delta_mode else {}),
                'updated_at':response_time,
                'join_warning':'El historial no garantiza que los huevos sigan disponibles. '
                    'Roblox tampoco garantiza unirse a la instancia reportada.'
            })
        if p.path=='/api/admin/backup':
            session=self.session()
            if not session or session['role'] != 'admin':
                return self.respond(401,{'error':'Solo el propietario puede descargar respaldos'})
            if not check_rate('portable-backup',3,600):
                return self.respond(429,{'error':'Espera para volver a descargar el respaldo'})
            try:
                with tempfile.TemporaryDirectory(prefix='pvfinder-export-') as work:
                    database=Path(work)/'pvfinder.sqlite3'
                    archive=Path(work)/'pvfinder.sqlite3.gz'
                    export_portable_database(database)
                    with database.open('rb') as original, gzip.open(archive,'wb',compresslevel=3) as compressed:
                        shutil.copyfileobj(original,compressed)
                    self.send_response(200)
                    self.secure_headers()
                    self.send_header('Content-Type','application/gzip')
                    self.send_header('Content-Disposition','attachment; filename="PVFINDER-datos-portables.sqlite3.gz"')
                    self.send_header('Content-Length',str(archive.stat().st_size))
                    self.end_headers()
                    with archive.open('rb') as file:
                        shutil.copyfileobj(file,self.wfile)
            except (BrokenPipeError,ConnectionResetError):
                pass
            return
        if p.path=='/api/admin/bots':
            if not self.require('admin'):return
            if not check_rate('owner-bot-dashboard:'+self.client_address[0],30,60):
                return self.respond(429,{'error':'Demasiadas consultas de estadísticas'})
            return self.respond(200,bot_dashboard.snapshot(DB,lock,now()))
        if p.path=='/api/admin/overview':
            if not self.require('admin'):return
            with lock:
                links=DB.execute('SELECT id,label,created_at,expires_at,max_uses,uses,revoked_at FROM access_links ORDER BY created_at DESC LIMIT 150').fetchall()
                collectors=DB.execute('SELECT id,label,created_at,last_seen,revoked_at FROM collectors ORDER BY created_at DESC LIMIT 150').fetchall()
                counts=DB.execute('SELECT rarity,COUNT(*) n FROM detections GROUP BY rarity').fetchall()
                unknown=DB.execute("SELECT COUNT(*) n FROM detections WHERE rarity IS NULL OR rarity=''").fetchone()['n']
                events=DB.execute('SELECT * FROM detections ORDER BY updated_at DESC LIMIT 30').fetchall()
            return self.respond(200,{'links':[dict(r) for r in links],'collectors':[dict(r) for r in collectors],'counts':{r['rarity'] or 'Desconocida':r['n'] for r in counts},'unknown_count':unknown,'events':[dict(r) for r in events]})
        if p.path in ('/bots','/bots/'):
            return self.static(ROOT/'web'/'bots.html')
        if p.path in ('/bots.js','/bots.css'):
            return self.static(ROOT/'web'/p.path[1:])
        if p.path in ('/editor','/editor.html'):
            return self.static(ROOT/'web'/'editor.html')
        if p.path in ('/editor.js','/branding.js','/site-config.js','/site-editor.js'):
            return self.static(ROOT/'web'/p.path[1:])
        if p.path=='/' or p.path=='/index.html' or p.path=='/demo.html':
            return self.static(ROOT/'web'/('demo.html' if p.path=='/demo.html' else 'index.html'))
        if p.path=='/styles.css' and radar_styles is not None:
            encodings=(part.strip().lower().split(';',1) for part in
                       self.headers.get('Accept-Encoding','').split(','))
            gzip_ok=any(name=='gzip' and (not quality or float(quality[0].strip()[2:])>0)
                        for name,*quality in encodings
                        if not quality or re.fullmatch(r'q=[01](?:\.[0-9]+)?',quality[0].strip()))
            content=radar_styles_gzip if gzip_ok else radar_styles
            return self.public_asset(content,'text/css; charset=utf-8',
                'public, no-cache',encoding='gzip' if gzip_ok else None,vary=True)
        if p.path.startswith('/media/radar/'):
            name=p.path.removeprefix('/media/radar/')
            content=radar_images.get(name)
            if content is None:return self.respond(404,{'error':'Imagen no encontrada'})
            return self.public_asset(content,'image/webp',
                'public, max-age=31536000, immutable',etag='"'+name.removesuffix('.webp')+'"')
        if p.path in ('/app.js','/styles.css'):
            return self.static(ROOT/'web'/p.path[1:])
        if p.path=='/delta.lua':
            # Publica solo el visor cliente, sin exponer codigo ni datos del backend.
            # El feed requiere un token de jugador validado por la API.
            return self.static(ROOT/'delta'/'PVFinder_Viewer.lua')
        if p.path=='/scanner-v3.lua':
            return self.static(ROOT/'delta'/'PVFinder_V3_Scanner.lua')
        if p.path=='/live-v2.lua':
            # Misma version funcional verificada en Delta, sin secretos incrustados.
            # GitHub es privado: Render distribuye este archivo sin login.
            return self.static(ROOT/'delta'/'PVFinder_Live_V2_Panel.lua')
        if p.path=='/bot-hop.lua':
            # Script publico para que Delta lo reejecute despues de cada teleport.
            return self.static(ROOT/'delta'/'PVFinder_Bots_ServerHop_Coordinado.lua')
        if p.path=='/auto-node.lua':
            # Unico script publico sin credenciales; versionado en GitHub privado.
            return self.static(ROOT/'PVFinder_V3_AutoNode_SinKeys_SinPanel.lua')
        if p.path=='/bot-collector.lua':
            # Nueva variante: token individual activado por el usuario, no hardcodeado.
            return self.static(ROOT/'delta'/'PVFinder_V3_BotCollector.lua')
        if p.path in ('/ventas','/ventas/','/precios'):
            # Precios PUBLICOS; la autenticacion del Live Feed sigue separada.
            return self.static(ROOT/'web'/'ventas.html')
        if p.path=='/ventas.js':
            return self.static(ROOT/'web'/'ventas.js')
        if p.path=='/bot-headless.lua':
            # V3 original preservado.
            return self.static(ROOT/'delta'/'PVFinder_V3_HeadlessCollector.lua')
        if p.path=='/bot-full.lua':
            # V4 opcional para multiples detecciones simultaneas.
            return self.static(ROOT/'delta'/'PVFinder_V4_FullCollector.lua')
        return self.respond(404,{'error':'No encontrado'})
    def public_asset(self,content,mime,cache_control,encoding=None,vary=False,etag=None):
        if etag is None:
            etag='"'+hashlib.sha256(content).hexdigest()+'"'
        known=self.headers.get('If-None-Match','').split(',')
        unchanged=any(tag.strip().removeprefix('W/') in (etag,'*') for tag in known)
        self.send_response(304 if unchanged else 200)
        self.secure_headers(cache_control=cache_control)
        self.send_header('ETag',etag)
        if vary:self.send_header('Vary','Accept-Encoding')
        if not unchanged:
            self.send_header('Content-Type',mime)
            self.send_header('Content-Length',str(len(content)))
            if encoding:self.send_header('Content-Encoding',encoding)
        self.end_headers()
        if not unchanged:self.wfile.write(content)

    def static(self,fp):
        try:content=fp.read_bytes()
        except FileNotFoundError:return self.respond(404,{'error':'Archivo no encontrado'})
        typ=mimetypes.guess_type(fp.name)[0] or 'application/octet-stream'
        self.send_response(200)
        self.send_header('Content-Type',typ+'; charset=utf-8')
        self.send_header('Content-Length',str(len(content)))
        self.secure_headers(is_html=fp.suffix=='.html')
        self.end_headers();self.wfile.write(content)
    def do_POST(self):
        p=urlparse(self.path).path
        # Las rutas administrativas solo aceptan JSON. Evita formularios
        # cross-site que intentan ejecutar acciones con la cookie del owner.
        if (p.startswith('/api/admin/') or p.startswith('/api/editor/') or p in ('/api/logout','/api/payments/checkout')):
            media_type=self.headers.get('Content-Type','').split(';',1)[0].strip().lower()
            if media_type!='application/json':
                return self.respond(415,{'error':'Se requiere application/json'})
        origin=self.headers.get('Origin','')
        if origin:
            from urllib.parse import urlparse as pu
            host=self.headers.get('Host','')
            if pu(origin).netloc != host and (not PUBLIC_URL or origin!=PUBLIC_URL):
                return self.respond(403,{'error':'Origen no autorizado'})
        if not p.startswith('/api/hop/') and not check_rate('ip:'+self.client_address[0],200):return self.respond(429,{'error':'Demasiadas solicitudes'})
        try:
            data=self.body()
            if p=='/api/payments/checkout':
                if not check_rate('checkout:'+self.client_address[0],12,60):
                    return self.respond(429,{'error':'Demasiados intentos de pago'})
                if not isinstance(data,dict):
                    return self.respond(400,{'error':'JSON inválido'})
                status,result=payments.create_checkout(data.get('plan'),PUBLIC_URL)
                return self.respond(status,result)
            if p in ('/api/editor/login','/api/editor/keys','/api/editor/site','/api/editor/branding','/api/editor/coowner/revoke','/api/editor/coowner/rotate'):
                return coowner_access.handle_post(self,p,data,DB,lock,now,digest,check_rate,STAFF_COOKIE_MAX_AGE)
            if p=='/api/collector/register':
                # Solo si el dueño habilita explícitamente registro automático.
                # Sin autenticación inicial: nunca afirmar que un bot es confiable.
                if not AUTO_COLLECTORS_ENABLED:
                    return self.respond(403,{'error':'Registro automatico desactivado'})
                if not isinstance(data,dict):
                    return self.respond(400,{'error':'JSON invalido'})
                place=valid_place_id(data.get('place_id'))
                job=valid_job_id(data.get('server_id'))
                if not place or not job:
                    return self.respond(400,{'error':'Falta PlaceId o JobId valido'})
                ip=self.client_address[0]
                if not check_rate('auto-reg:'+ip,AUTO_REGISTRATIONS_PER_IP,3600):
                    return self.respond(429,{'error':'Demasiados registros desde esta conexion'})
                if not check_rate('auto-reg:global',600,3600):
                    return self.respond(429,{'error':'Limite global de registros'})
                ts=now()
                collector_id=uuid.uuid4().hex
                token='pvfa_'+secrets.token_urlsafe(32)
                with lock:
                    active=DB.execute('SELECT COUNT(*) FROM auto_collector_sessions WHERE expires_at>?',(ts,)).fetchone()[0]
                    if active>=AUTO_MAX_ACTIVE:
                        return self.respond(429,{'error':'Limite de recolectores activos'})
                    # Los recolectores antiguos no se borran: mantienen historial.
                    seq=DB.execute("SELECT COUNT(*) FROM collectors WHERE label LIKE 'Auto Node %'").fetchone()[0]+1
                    label='Auto Node %03d'%seq
                    DB.execute('BEGIN IMMEDIATE')
                    try:
                        DB.execute('INSERT INTO collectors(id,label,token_hash,created_at) VALUES(?,?,?,?)',
                            (collector_id,label,digest('pvfa_unused_'+secrets.token_urlsafe(32)),ts))
                        DB.execute('INSERT INTO auto_collector_sessions(token_hash,collector_id,created_at,expires_at) VALUES(?,?,?,?)',
                            (digest(token),collector_id,ts,ts+AUTO_SESSION_SECONDS))
                        DB.execute('COMMIT')
                    except Exception:
                        DB.execute('ROLLBACK')
                        raise
                return self.respond(201,{'ok':True,'collector_id':collector_id,'label':label,
                    'session_token':token,'expires_in':AUTO_SESSION_SECONDS,
                    'unverified_source':True})
            if p=='/api/collector/renew':
                # Renueva su propia sesión; no crea un recolector nuevo.
                auth=self.headers.get('Authorization','')
                token=auth[7:].strip() if auth.startswith('Bearer pvfa_') else ''
                if not token or len(token)>180:
                    return self.respond(401,{'error':'Sesion de recolector invalida'})
                ts=now()
                with lock:
                    valid=DB.execute('''SELECT c.id FROM auto_collector_sessions a
                        JOIN collectors c ON c.id=a.collector_id
                        WHERE a.token_hash=? AND a.expires_at>? AND c.revoked_at IS NULL''',
                        (digest(token),ts)).fetchone()
                    if not valid:return self.respond(401,{'error':'Sesion expirada o revocada'})
                    DB.execute('UPDATE auto_collector_sessions SET expires_at=? WHERE token_hash=?',
                               (ts+AUTO_SESSION_SECONDS,digest(token)))
                return self.respond(200,{'ok':True,'expires_in':AUTO_SESSION_SECONDS})
            if p=='/api/admin/login':
                if not check_rate('login:'+self.client_address[0],8,60):return self.respond(429,{'error':'Intenta de nuevo mas tarde'})
                pwd=str(data.get('password',''))
                owner_key=coowner_access.normalized_staff_key(pwd,'pvfo_')
                persistent=bool(owner_key and hmac.compare_digest(digest(owner_key),OWNER_KEY_HASH))
                if not persistent and not hmac.compare_digest(pwd.encode(),ADMIN_PASSWORD.encode()):
                    return self.respond(401,{'error':'Contraseña o llave de Owner incorrecta'})
                token=secrets.token_urlsafe(32)
                if persistent:token=OWNER_SESSION_PREFIX+token
                created=now()
                expires=0 if persistent else created+8*3600
                with lock:DB.execute('INSERT INTO sessions VALUES(?,?,?,?,?)',(owner_session_hash(token),'admin',None,created,expires))
                return self.respond(200,{'ok':True,'role':'admin','persistent':persistent},
                    self.cookie(token,STAFF_COOKIE_MAX_AGE if persistent else 8*3600))
            if p in ('/api/access/redeem','/api/delta/redeem'):
                is_delta=(p=='/api/delta/redeem')
                if not check_rate(
                    ('delta-login:' if is_delta else 'viewer-login:')+
                    self.client_address[0],8,60):
                    return self.respond(429,{'error':'Demasiados intentos'})
                token=strval(data.get('token'),200)
                if len(token)<32:return self.respond(401,{'error':'Enlace invalido'})
                with lock:
                    DB.execute('BEGIN IMMEDIATE')
                    try:
                        l=DB.execute('SELECT * FROM access_links WHERE token_hash=?',(digest(token),)).fetchone()
                        if not l or l['revoked_at'] or (l['expires_at'] and l['expires_at']<=now()) or (l['max_uses'] is not None and l['uses']>=l['max_uses']):
                            DB.execute('ROLLBACK');return self.respond(401,{'error':'Enlace vencido o invalido'})
                        if l['roblox_user_id'] is not None:
                            try:
                                reported_uid=coowner_access.uid(data.get('user_id'))
                            except (ValueError,TypeError):
                                reported_uid=None
                            if not is_delta or reported_uid!=l['roblox_user_id']:
                                DB.execute('ROLLBACK')
                                return self.respond(401,{'error':'La llave no corresponde al UserId de Roblox'})
                        DB.execute('UPDATE access_links SET uses=uses+1 WHERE id=?',(l['id'],))
                        session=('pvfs_' if is_delta else '')+secrets.token_urlsafe(32)
                        lifespan=8*3600 if is_delta else 7*86400
                        expiration=min(now()+lifespan,l['expires_at']) if l['expires_at'] else now()+lifespan
                        DB.execute('INSERT INTO sessions VALUES(?,?,?,?,?)',(digest(session),'viewer',l['id'],now(),expiration))
                        DB.execute('COMMIT')
                    except Exception:
                        DB.execute('ROLLBACK');raise
                if is_delta:
                    return self.respond(200,{'ok':True,'role':'viewer',
                        'session_token':session,'expires_at':expiration})
                return self.respond(200,{'ok':True,'role':'viewer'},self.cookie(session,expiration-now()))
            if p=='/api/logout':
                token=self.cookie_token()
                if token:
                    with lock:DB.execute('DELETE FROM sessions WHERE token_hash=?',(owner_session_hash(token),))
                return self.respond(200,{'ok':True},self.cookie('',0))
            if p=='/api/admin/links':
                if not self.require('admin'):return
                label=strval(data.get('label'),60) or 'Acceso privado'
                hours=data.get('expires_hours')
                if hours is not None and hours not in (1,24,168,720):return self.respond(400,{'error':'Vencimiento invalido'})
                max_uses=data.get('max_uses')
                if max_uses is not None and (not isinstance(max_uses,int) or max_uses<1 or max_uses>100000):return self.respond(400,{'error':'Limite de usos invalido'})
                token=secrets.token_urlsafe(32); id=uuid.uuid4().hex
                exp=now()+hours*3600 if hours else None
                with lock:DB.execute('INSERT INTO access_links(id,label,token_hash,created_at,expires_at,max_uses) VALUES(?,?,?,?,?,?)',(id,label,digest(token),now(),exp,max_uses))
                base=(PUBLIC_URL or os.environ.get('RENDER_EXTERNAL_URL','').rstrip('/')
                      or ('http://'+self.headers.get('Host','localhost:'+str(PORT))))
                url=base+'/#/acceso/'+token
                return self.respond(201,{'ok':True,'url':url,'id':id,'warning':'Copia el enlace: el token no se guardara en texto claro.'})
            if p=='/api/admin/links/revoke':
                if not self.require('admin'):return
                id=strval(data.get('id'),80)
                with lock:
                    DB.execute('UPDATE access_links SET revoked_at=? WHERE id=?',(now(),id))
                    DB.execute('DELETE FROM sessions WHERE link_id=?',(id,))
                return self.respond(200,{'ok':True})
            if p=='/api/admin/collectors':
                if not self.require('admin'):return
                label=strval(data.get('label'),60) or 'Recolector'
                token='pvf_'+secrets.token_urlsafe(32);id=uuid.uuid4().hex
                with lock:DB.execute('INSERT INTO collectors(id,label,token_hash,created_at) VALUES(?,?,?,?)',(id,label,digest(token),now()))
                return self.respond(201,{'ok':True,'collector_id':id,'credential':token,'warning':'Copia la credencial: se muestra solo esta vez.'})
            if p=='/api/admin/collectors/revoke':
                if not self.require('admin'):return
                id=strval(data.get('id'),80)
                with lock:DB.execute('UPDATE collectors SET revoked_at=? WHERE id=?',(now(),id))
                return self.respond(200,{'ok':True})
            if p=='/api/collector/activity':
                collector=self.collector()
                if not collector:
                    return self.respond(401,{'error':'Credencial del recolector inválida'})
                if not check_rate('collector-activity:'+collector['id'],20,60):
                    return self.respond(429,{'error':'Límite de actividad'})
                phase=data.get('phase') if isinstance(data,dict) else None
                reason=data.get('reason') if isinstance(data,dict) else None
                if (not isinstance(phase,str) or not isinstance(reason,str)
                        or reason not in COLLECTOR_PHASES.get(phase,())):
                    return self.respond(400,{'error':'Estado de recolector inválido'})
                ts=now()
                pause_reason=reason if phase=='paused' else None
                with lock:
                    DB.execute('''
                        INSERT INTO collector_activity VALUES(?,?,?,?,?,?)
                        ON CONFLICT(collector_id) DO UPDATE SET
                            phase=excluded.phase, reason=excluded.reason,
                            signal_at=excluded.signal_at,
                            last_pause_reason=coalesce(excluded.last_pause_reason,last_pause_reason),
                            last_pause_at=coalesce(excluded.last_pause_at,last_pause_at)
                    ''',(collector['id'],phase,reason,ts,pause_reason,ts if pause_reason else None))
                return self.respond(200,{'ok':True})
            if p in ('/api/hop/start','/api/hop/next','/api/hop/release'):
                return hop_coordinator.route(self,p,data,DB,lock,
                                             valid_place_id,valid_job_id,
                                             now,check_rate)
            if p=='/api/hop/recheck':
                collector=self.collector()
                if not collector:
                    return self.respond(401,{'error':'Credencial del recolector invalida'})
                if not check_rate('hop-recheck:'+collector['id'],30,60):
                    return self.respond(429,{'error':'Demasiadas comprobaciones'})
                if not isinstance(data,dict):
                    return self.respond(400,{'error':'Comprobacion invalida'})
                server=valid_job_id(data.get('server_id'))
                place_id=valid_place_id(data.get('place_id'))
                snapshot_at=data.get('snapshot_at')
                missing=data.get('missing_ids')
                timestamp=now()
                if (not server or not place_id or type(snapshot_at) is not int
                    or not timestamp-90<=snapshot_at<=timestamp
                    or not isinstance(missing,list) or not 1<=len(missing)<=500
                    or any(type(egg_id) is not str or not 3<=len(egg_id)<=160
                           or not egg_id.startswith(('G/','H/')) for egg_id in missing)):
                    return self.respond(400,{'error':'Comprobacion de presencia invalida'})
                with lock:
                    DB.execute('BEGIN IMMEDIATE')
                    try:
                        candidates=list(dict.fromkeys(missing))
                        targets=DB.execute(
                            "SELECT egg_id FROM detections WHERE collector_id=? AND place_id=? AND server_id=? "
                            "AND updated_at=? AND presence_state='PRESENTE_REPORTADO' AND egg_id IN ("
                            + ','.join('?' for _ in candidates) + ')',
                            (collector['id'],place_id,server,snapshot_at,*candidates)).fetchall()
                        if targets:
                            revision=advance_radar_revision()
                            DB.executemany(
                                "UPDATE detections SET presence_state='AUSENTE_REPORTADO',checked_at=?,radar_revision=? "
                                "WHERE server_id=? AND egg_id=?",
                                ((timestamp,revision,server,row['egg_id']) for row in targets))
                        DB.execute('COMMIT')
                        if targets:
                            radar_changed.notify_all()
                    except Exception:
                        DB.execute('ROLLBACK')
                        raise
                return self.respond(200,{'ok':True,'marked_absent':len(targets)})
            if p in ('/api/collect/snapshot','/api/hop/snapshot'):
                # Acepta todos los huevos TOP de una instantanea (V3 puede seguir enviando uno).
                collector=self.collector()
                if not collector:
                    return self.respond(401,{'error':'Credencial del recolector invalida'})
                if not check_rate('snapshot:'+collector['id'],60,60):
                    return self.respond(429,{'error':'Demasiadas instantaneas'})
                if not isinstance(data,dict):
                    return self.respond(400,{'error':'Instantanea invalida'})
                server=valid_job_id(data.get('server_id'))
                place_id=valid_place_id(data.get('place_id'))
                if not server or not place_id:
                    return self.respond(400,{'error':'Se requiere JobId y PlaceId validos'})
                items=data.get('items')
                if not isinstance(items,list) or len(items)>500:
                    return self.respond(400,{'error':'Se admiten de 0 a 500 huevos por instantanea'})
                # Admitir los nombres antiguos y los prefijos G/H de Live V2.
                # Una lista vacia con scopes marca ausencias; nunca borra detecciones.
                scope_alias={'G':'G','GLOBAL':'G','H':'H','HALLOWEEN':'H'}
                scopes=data.get('scopes')
                if scopes is not None:
                    if (not isinstance(scopes,list) or len(scopes)>2
                        or any(type(v) is not str or v not in scope_alias for v in scopes)
                        or len({scope_alias[v] for v in scopes})!=len(scopes)):
                        return self.respond(400,{'error':'Fuentes de escaneo invalidas'})
                    scopes={scope_alias[v] for v in scopes}
                if p=='/api/hop/snapshot' and not scopes:
                    return self.respond(400,{'error':'No se leyo ninguna fuente; no se marca el servidor como visitado'})
                timestamp=now()
                records=[]
                seen_ids=set()
                for item in items:
                    if not isinstance(item,dict):
                        return self.respond(400,{'error':'Huevo invalido'})
                    name=strval(item.get('egg_name'),100)
                    egg_id=strval(item.get('egg_id'),160)
                    rarity=strval(item.get('rarity'),24)
                    biome=strval(item.get('biome'),70)
                    income=numval(item.get('income_per_second'))
                    weight=numval(item.get('weight_kg'))
                    multiplier=numval(item.get('multiplier'))
                    mutation=strval(item.get('mutation'),70) or None
                    if not name or not egg_id or not rarity:
                        return self.respond(400,{'error':'Faltan datos del huevo'})
                    if biome.casefold()=='prehistoric' and name.strip().casefold()!='mosasaurus':
                        return self.respond(400,{'error':'Bioma no permitido'})
                    if item.get('server_id') not in (None,server):
                        return self.respond(400,{'error':'JobId del huevo no coincide'})
                    if item.get('place_id') not in (None,place_id):
                        return self.respond(400,{'error':'PlaceId del huevo no coincide'})
                    if scopes and scope_alias.get(egg_id.split('/',1)[0]) not in scopes:
                        return self.respond(400,{'error':'Fuente del huevo fuera del escaneo'})
                    if egg_id in seen_ids:
                        return self.respond(400,{'error':'Identificador duplicado'})
                    seen_ids.add(egg_id)
                    income_type='ESTIMADO' if income is not None else 'NO_DISPONIBLE'
                    records.append((uuid.uuid4().hex,server,egg_id,place_id,
                        collector['id'],name,rarity,biome,income,income_type,
                        weight,mutation,multiplier,timestamp,timestamp,timestamp,
                        'PRESENTE_REPORTADO',timestamp))
                with lock:
                    DB.execute('BEGIN IMMEDIATE')
                    try:
                        if p=='/api/hop/snapshot':
                            if (not hop_coordinator.claimed(DB,place_id,server,collector['id'],timestamp)
                                or hop_coordinator.has_detections(DB,place_id,server)):
                                DB.execute('ROLLBACK')
                                return self.respond(409,{'ok':False,'error':'already_reported_or_not_owned'})
                        revision=advance_radar_revision()
                        for record in records:
                            DB.execute('''
                                INSERT INTO detections(id,server_id,egg_id,place_id,
                                    collector_id,egg_name,rarity,biome,income_per_second,
                                    income_type,weight_kg,mutation,multiplier,
                                    seen_at,first_seen,updated_at,presence_state,checked_at,radar_revision)
                                VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                                ON CONFLICT(server_id,egg_id) DO UPDATE SET
                                    radar_revision=excluded.radar_revision,
                                    place_id=excluded.place_id,
                                    collector_id=excluded.collector_id,
                                    egg_name=excluded.egg_name,
                                    rarity=excluded.rarity,
                                    biome=excluded.biome,
                                    income_per_second=excluded.income_per_second,
                                    income_type=excluded.income_type,
                                    weight_kg=excluded.weight_kg,
                                    mutation=excluded.mutation,
                                    multiplier=COALESCE(excluded.multiplier,detections.multiplier),
                                    seen_at=excluded.seen_at,
                                    updated_at=excluded.updated_at,
                                    presence_state=excluded.presence_state,
                                    checked_at=excluded.checked_at
                                ''',(*record,revision))
                        # Solo snapshots con fuentes completas permiten marcar AUSENTE.
                        absent=0
                        if scopes:
                            previous=DB.execute(
                                'SELECT egg_id,presence_state FROM detections '
                                'WHERE collector_id=? AND server_id=?',
                                (collector['id'],server)).fetchall()
                            for old in previous:
                                egg_id=old['egg_id']
                                source=scope_alias.get(egg_id.split('/',1)[0])
                                if (source in scopes and egg_id not in seen_ids
                                    and old['presence_state']!='AUSENTE_REPORTADO'):
                                    absent+=DB.execute(
                                        "UPDATE detections SET presence_state='AUSENTE_REPORTADO',checked_at=?,radar_revision=? "
                                        "WHERE collector_id=? AND server_id=? AND egg_id=?",
                                        (timestamp,revision,collector['id'],server,egg_id)).rowcount
                        deleted=0
                        DB.execute('UPDATE collectors SET last_seen=? WHERE id=?',
                                   (timestamp,collector['id']))
                        if scopes or records:
                            record_radar_scans(DB,timestamp,[(place_id,server)])
                        if p=='/api/hop/snapshot':
                            hop_coordinator.mark_done(DB,place_id,server,collector['id'],timestamp)
                        DB.execute('COMMIT')
                        radar_changed.notify_all()
                    except Exception:
                        DB.execute('ROLLBACK')
                        raise
                return self.respond(200,{
                    'ok':True,'accepted':len(records),
                    'removed':deleted,'marked_absent':absent,'server_id':server,
                    'snapshot_at':timestamp
                })
            if p in ('/api/collect','/api/collect/batch'):
                collector=self.collector()
                if not collector:return self.respond(401,{'error':'Credencial del recolector invalida'})
                if not check_rate('collector:'+collector['id'],90):return self.respond(429,{'error':'Limite de envios alcanzado'})
                items=data.get('items') if isinstance(data,dict) and isinstance(data.get('items'),list) else [data]
                if not (1<=len(items)<=100):return self.respond(400,{'error':'Numero de detecciones invalido'})
                parsed=[];ignored=0
                scan_time=now()  # Un mismo sello para todos los huevos de este envio.
                for item in items:
                    if not isinstance(item,dict):raise ValueError('Deteccion invalida')
                    server=valid_job_id(item.get('server_id'));eid=strval(item.get('egg_id'),160)
                    place_id=valid_place_id(item.get('place_id'))
                    name=strval(item.get('egg_name') or item.get('name'),100)
                    if not server or not eid or not name:raise ValueError('Falta server_id, egg_id o egg_name')
                    biome=strval(item.get('biome'),70) or None
                    if biome and biome.casefold()=='prehistoric' and name.strip().casefold()!='mosasaurus':ignored+=1;continue
                    rarity=strval(item.get('rarity'),24) or None
                    rarity=rarity or None
                    income=numval(item.get('income_per_second'))
                    weight=numval(item.get('weight_kg'))
                    mult=numval(item.get('multiplier'))
                    kind=strval(item.get('income_type'),24).upper()
                    if kind not in ('DIRECTO','ESTIMADO','DESCONOCIDO'):kind='DESCONOCIDO'
                    if income is None:kind='DESCONOCIDO'
                    if income is not None and kind=='DIRECTO':
                        # The client claims a direct reading; backend cannot independently verify it.
                        kind='DIRECTO'
                    mutation=strval(item.get('mutation'),70) or None
                    parsed.append((uuid.uuid4().hex,server,eid,place_id,collector['id'],name,rarity,biome,income,kind,weight,mutation,mult,scan_time,scan_time,scan_time,'REPORTE_PUNTUAL',scan_time))
                with lock:
                    DB.execute('BEGIN IMMEDIATE')
                    try:
                        revision=advance_radar_revision() if parsed else None
                        for t in parsed:
                            DB.execute('''INSERT INTO detections(id,server_id,egg_id,place_id,collector_id,egg_name,rarity,biome,
                                income_per_second,income_type,weight_kg,mutation,multiplier,seen_at,first_seen,updated_at,presence_state,checked_at,radar_revision)
                                VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                                ON CONFLICT(server_id,egg_id) DO UPDATE SET radar_revision=excluded.radar_revision,place_id=COALESCE(excluded.place_id,detections.place_id),
                                collector_id=excluded.collector_id,
                                egg_name=excluded.egg_name,rarity=excluded.rarity,biome=excluded.biome,
                                income_per_second=excluded.income_per_second,income_type=excluded.income_type,
                                weight_kg=excluded.weight_kg,mutation=excluded.mutation,multiplier=COALESCE(excluded.multiplier,detections.multiplier),
                                seen_at=excluded.seen_at,updated_at=excluded.updated_at,
                                presence_state=excluded.presence_state,checked_at=excluded.checked_at''',(*t,revision))
                        scanned={(t[3],t[1]) for t in parsed if t[3] and valid_job_id(t[1])}
                        if scanned:
                            record_radar_scans(DB,scan_time,scanned)
                        DB.execute('UPDATE collectors SET last_seen=? WHERE id=?',(scan_time,collector['id']))
                        DB.execute('COMMIT')
                        if revision is not None:
                            radar_changed.notify_all()
                    except Exception:
                        DB.execute('ROLLBACK');raise
                return self.respond(200,{'ok':True,'accepted':len(parsed),'ignored':ignored,'unverified_source':True})
            return self.respond(404,{'error':'Ruta no encontrada'})
        except (ValueError,TypeError,json.JSONDecodeError) as exc:
            return self.respond(400,{'error':str(exc)[:160]})
        except Exception as exc:
            print('ERROR',repr(exc))
            return self.respond(500,{'error':'Error interno'})

if __name__=='__main__':
    print(f'PVFINDER: http://{HOST}:{PORT} | db={DATA}')
    print('No expongas el servidor directamente a internet; usa un proxy HTTPS y un entorno seguro.')
    try:ThreadingHTTPServer((HOST,PORT),Handler).serve_forever()
    except KeyboardInterrupt:print('Detenido.')
