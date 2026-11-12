"""Co-owner access, Roblox-user-scoped viewer keys and site branding for PVFinder.
All privileges are checked on the server. Co-owner never receives admin access.
"""
import os, re, json, base64, binascii, hashlib, hmac, secrets, uuid
from urllib.request import Request, urlopen
from urllib.error import URLError
import site_content

MAX_IMAGE_BYTES = 135000
MAX_KEY_HOURS = 3650 * 24

def install(db):
    site_content.install(db)
    db.execute("""CREATE TABLE IF NOT EXISTS coowners (
        id TEXT PRIMARY KEY, label TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL, revoked_at INTEGER
    )""")
    db.execute("""CREATE TABLE IF NOT EXISTS site_branding (
        name TEXT PRIMARY KEY, mime TEXT NOT NULL, data BLOB NOT NULL,
        updated_at INTEGER NOT NULL, updated_by TEXT NOT NULL
    )""")
    fields = {row[1] for row in db.execute("PRAGMA table_info(access_links)")}
    if 'roblox_user_id' not in fields:
        db.execute("ALTER TABLE access_links ADD COLUMN roblox_user_id INTEGER")
    if 'issued_by' not in fields:
        db.execute("ALTER TABLE access_links ADD COLUMN issued_by TEXT")
    if 'roblox_username' not in fields:
        db.execute("ALTER TABLE access_links ADD COLUMN roblox_username TEXT")
    # Deshabilitacion definitiva del rol co-owner; incluso si queda una variable antigua.
    db.execute("UPDATE coowners SET revoked_at=strftime('%s','now') WHERE revoked_at IS NULL")
    db.execute("DELETE FROM sessions WHERE role='coowner'")

def uid(value):
    if isinstance(value, bool) or value is None: raise ValueError("UserId de Roblox inválido")
    if isinstance(value, int): number = value
    elif isinstance(value, str) and value.isascii() and value.isdecimal(): number = int(value)
    else: raise ValueError("UserId de Roblox inválido")
    if number < 1 or number > 9007199254740991:
        raise ValueError("UserId de Roblox fuera de rango")
    return number

def _roblox_request(route, body):
    """Use only Roblox's fixed HTTPS user endpoint, never a caller-supplied URL."""
    req = Request(
        'https://users.roblox.com' + route,
        data=json.dumps(body, separators=(',', ':')).encode('utf-8'),
        headers={'Content-Type': 'application/json', 'Accept': 'application/json'},
        method='POST',
    )
    try:
        with urlopen(req, timeout=4) as response:
            return json.loads(response.read(100000))
    except (URLError, OSError, ValueError):
        return None


def roblox_username(value):
    """Resolve the official Roblox @username to a stable numeric ID internally."""
    if not isinstance(value, str):
        raise ValueError('Escribe el nombre de usuario de Roblox')
    name = value.strip().removeprefix('@')
    if not re.fullmatch(r'[A-Za-z0-9_]{3,20}', name):
        raise ValueError('Usuario de Roblox inválido (3 a 20 caracteres)')
    found = _roblox_request('/v1/usernames/users',
                            {'usernames': [name], 'excludeBannedUsers': False})
    if not isinstance(found, dict):
        raise LookupError('No fue posible consultar Roblox. Intenta de nuevo')
    for item in found.get('data', []):
        if (isinstance(item, dict) and
                str(item.get('name', '')).lower() == name.lower()):
            return uid(item.get('id')), item['name']
    raise ValueError('No existe ese nombre de usuario de Roblox')


def usernames_for_ids(ids):
    """Fill names on old keys without changing the ID-based access checks."""
    names = {}
    for start in range(0, len(ids), 100):
        data = _roblox_request('/v1/users',
                               {'userIds': ids[start:start + 100], 'excludeBannedUsers': False})
        if not isinstance(data, dict):
            break
        for item in data.get('data', []):
            if not isinstance(item, dict) or not isinstance(item.get('name'), str):
                continue
            try:
                names[uid(item.get('id'))] = item['name']
            except ValueError:
                continue
    return names


def player_for_key(data):
    if 'username' in data:
        return roblox_username(data['username'])
    # Backward compatibility for older authorized API clients. Never shown in UI.
    player_id = uid(data.get('user_id'))
    return player_id, usernames_for_ids([player_id]).get(player_id)


def can_manage(handler):
    session = handler.session()
    if not session or session['role'] != 'admin':
        handler.respond(401, {'error':'Acceso de editor requerido'})
        return None
    return session['role']

def handle_get(handler, path, db, lock, now):
    if path == '/api/site/content':
        return handler.respond(200, site_content.snapshot(db, lock))
    if path == '/api/branding/meta':
        with lock:
            rows = db.execute("SELECT name,updated_at FROM site_branding").fetchall()
        return handler.respond(200, {'images': {r['name']:r['updated_at'] for r in rows}})
    if path in ('/api/branding/logo', '/api/branding/hero'):
        name = path.rsplit('/',1)[1]
        with lock:
            r = db.execute("SELECT mime,data FROM site_branding WHERE name=?", (name,)).fetchone()
        if not r:return handler.respond(404, {'error':'Imagen no configurada'})
        payload = r['data']
        handler.send_response(200)
        handler.send_header('Content-Type', r['mime'])
        handler.send_header('Content-Length', str(len(payload)))
        handler.secure_headers()
        handler.end_headers()
        handler.wfile.write(payload)
        return
    role = can_manage(handler)
    if not role:return
    if path == '/api/editor/site':
        return handler.respond(200, site_content.snapshot(db, lock))
    if path == '/api/editor/site/history':
        return site_content.history(handler, db, lock)
    if path == '/api/editor/keys':
        if role != 'admin':
            return handler.respond(403, {'error':'Solo el dueño puede gestionar llaves'})
        clause = "WHERE issued_by='coowner'" if role == 'coowner' else "WHERE (roblox_user_id IS NOT NULL OR issued_by IN ('admin','coowner'))"
        with lock:
            rec = db.execute("""SELECT id,label,roblox_user_id,roblox_username,issued_by,created_at,
                expires_at,revoked_at,uses FROM access_links """ + clause +
                " ORDER BY created_at DESC LIMIT 250").fetchall()
        records = [dict(r) for r in rec]
        missing = sorted({r['roblox_user_id'] for r in records
                          if r['roblox_user_id'] is not None and not r['roblox_username']})
        resolved = usernames_for_ids(missing) if missing else {}
        if resolved:
            with lock:
                for r in records:
                    name = resolved.get(r['roblox_user_id'])
                    if name and not r['roblox_username']:
                        db.execute("UPDATE access_links SET roblox_username=? WHERE id=?",
                                   (name, r['id']))
                        r['roblox_username'] = name
        return handler.respond(200, {'keys':[r for r in records if r['roblox_user_id'] is not None],
            'web_keys':[r for r in records if r['roblox_user_id'] is None], 'role':role})
    return handler.respond(404, {'error':'Ruta no encontrada'})

def normalized_staff_key(value, prefix):
    if not isinstance(value,str):return None
    value=value.strip().strip('\u200b\ufeff').strip()
    return value if re.fullmatch(re.escape(prefix)+r'[A-Za-z0-9_-]{43}',value) else None

def handle_post(handler, path, data, db, lock, now, digest, rate, staff_cookie_max_age):
    if not isinstance(data, dict):
        return handler.respond(400, {'error':'Datos inválidos'})
    if path == '/api/editor/login':
        return handler.respond(403, {'error':'Acceso de co-owner deshabilitado por el propietario'})

    role = can_manage(handler)
    if not role:return
    if path == '/api/editor/site':
        return site_content.handle_write(handler, data, db, lock, now, role, rate)
    if path == '/api/editor/coowner/revoke':
        if role != 'admin':return handler.respond(403, {'error':'Solo administrador'})
        with lock:
            db.execute("UPDATE coowners SET revoked_at=? WHERE id='primary'",(now(),))
            db.execute("DELETE FROM sessions WHERE role='coowner'")
        return handler.respond(200, {'ok':True})
    if path == '/api/editor/coowner/rotate':
        return handler.respond(403, {'error':'Acceso de co-owner deshabilitado por el propietario'})
    if path == '/api/editor/keys':
        if role != 'admin':
            return handler.respond(403, {'error':'Solo el dueño puede gestionar llaves'})
        action = data.get('action')
        if action == 'create':
            kind = data.get('kind', 'universal')
            if kind not in ('universal', 'web', 'roblox'):
                return handler.respond(400, {'error':'Tipo de acceso inválido'})
            try:
                player_id, player_name = player_for_key(data) if kind == 'roblox' else (None, None)
            except (ValueError, LookupError) as exc:
                return handler.respond(400 if isinstance(exc, ValueError) else 503,
                                       {'error': str(exc)})
            if kind in ('universal', 'web') and (data.get('user_id') not in (None, '') or
                                  data.get('username') not in (None, '')):
                return handler.respond(400, {'error':'El usuario de Roblox no corresponde al acceso web'})
            if 'hours' in data and 'days' in data:
                return handler.respond(400, {'error':'Indica una sola unidad de duración'})
            days = data.get('days')
            hours = data.get('hours', days * 24 if type(days) is int else None)
            if type(hours) is not int or not 1 <= hours <= MAX_KEY_HOURS:
                return handler.respond(400, {'error':'Duración válida: 1 hora a 3650 días'})
            if not rate('customer-keys:'+role+':'+handler.client_address[0], 25, 60):
                return handler.respond(429, {'error':'Demasiadas llaves en un minuto. Espera y vuelve a intentar.'})
            label = str(data.get('label') or '').strip()[:60] or (
                'Acceso PVFinder' if player_id is None else 'Roblox '+str(player_id))
            created_at = now()
            expires_at = created_at + hours * 3600
            key = 'pvk_' + secrets.token_urlsafe(32)
            key_id = uuid.uuid4().hex
            actor = 'coowner' if role == 'coowner' else 'admin'
            with lock:
                db.execute("""INSERT INTO access_links
                    (id,label,token_hash,created_at,expires_at,max_uses,roblox_user_id,roblox_username,issued_by)
                    VALUES(?,?,?,?,?,?,?,?,?)""",
                    (key_id,label,digest(key),created_at,expires_at,None,player_id,player_name,actor))
            return handler.respond(201,{'ok':True,'id':key_id,'key':key,
                'roblox_user_id':player_id, 'roblox_username':player_name,
                'expires_in_days':days, 'expires_at':expires_at, 'kind':kind,
                'note':'Copia ahora: esta llave no se vuelve a mostrar.'})
        elif action in ('uid','username','revoke'):
            key_id = data.get('id')
            if not isinstance(key_id,str) or not re.fullmatch(r'[a-f0-9]{32}',key_id):
                return handler.respond(400, {'error':'Identificador inválido'})
            # Resolve external usernames before entering the shared database lock:
            # bot collection must not wait on Roblox network latency.
            if action in ('uid', 'username'):
                try:
                    player_id, player_name = player_for_key(data)
                except (ValueError, LookupError) as exc:
                    return handler.respond(400 if isinstance(exc, ValueError) else 503,
                                           {'error': str(exc)})
            with lock:
                row = db.execute("""SELECT issued_by,revoked_at,roblox_user_id FROM access_links
                    WHERE id=? AND (roblox_user_id IS NOT NULL OR issued_by IN ('admin','coowner'))""",
                    (key_id,)).fetchone()
                if not row or (role=='coowner' and row['issued_by']!='coowner'):
                    return handler.respond(403, {'error':'No puedes cambiar esta llave'})
                if row['revoked_at'] is not None:
                    return handler.respond(409, {'error':'La llave está revocada'})
                if action in ('uid', 'username'):
                    if row['roblox_user_id'] is None:
                        return handler.respond(400, {'error':'Esta llave es de acceso web'})
                    db.execute("UPDATE access_links SET roblox_user_id=?, roblox_username=? WHERE id=?",
                               (player_id, player_name, key_id))
                else:
                    db.execute("UPDATE access_links SET revoked_at=? WHERE id=?", (now(),key_id))
                # Every preexisting session for this key must stop working.
                db.execute("DELETE FROM sessions WHERE link_id=?", (key_id,))
            return handler.respond(200,{'ok':True})
        return handler.respond(400, {'error':'Acción inválida'})
    if path == '/api/editor/branding':
        name = data.get('name')
        mime = data.get('mime')
        raw = data.get('data')
        if name not in ('logo','hero') or mime not in ('image/jpeg','image/png','image/webp'):
            return handler.respond(400,{'error':'Imagen o formato inválido'})
        if not isinstance(raw,str) or len(raw) > MAX_IMAGE_BYTES*2:
            return handler.respond(413,{'error':'Imagen demasiado grande'})
        try:
            binary = base64.b64decode(raw,validate=True)
        except (binascii.Error,ValueError):
            return handler.respond(400, {'error':'Datos de imagen inválidos'})
        if len(binary) < 16 or len(binary) > MAX_IMAGE_BYTES:
            return handler.respond(413, {'error':'Imagen demasiado grande'})
        magic_ok = ((mime=='image/jpeg' and binary.startswith(bytes.fromhex('ffd8ff')))
            or (mime=='image/png' and binary.startswith(bytes.fromhex('89504e470d0a1a0a')))
            or (mime=='image/webp' and binary[0:4]==b'RIFF' and binary[8:12]==b'WEBP'))
        if not magic_ok:
            return handler.respond(400, {'error':'El contenido no coincide con el formato'})
        with lock:
            db.execute("""INSERT INTO site_branding(name,mime,data,updated_at,updated_by)
                VALUES(?,?,?,?,?) ON CONFLICT(name) DO UPDATE SET
                mime=excluded.mime,data=excluded.data,
                updated_at=excluded.updated_at,updated_by=excluded.updated_by""",
                (name,mime,binary,now(),role))
        return handler.respond(200, {'ok':True,'name':name})
    return handler.respond(404, {'error':'Ruta no encontrada'})
