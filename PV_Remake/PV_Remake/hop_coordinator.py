"""Coordinacion de reservas de servidores para PVFinder.

Un servidor (PlaceId, JobId) puede ser explorado solo por un recolector
a la vez. Los identificadores completados no se vuelven a asignar.
"""
import random

# Reserved targets may take some time to load in Roblox.
# Once a bot actually enters a JobId (active), that JobId is never assigned
# again; the database keeps that history across restarts and deploys.
RESERVATION_SECONDS = 5 * 60
ACTIVE_SCAN_SECONDS = 25 * 60

def install(db):
    db.executescript("""
    CREATE TABLE IF NOT EXISTS pvf_hop_jobs(
        place_id INTEGER NOT NULL,
        server_id TEXT NOT NULL,
        state TEXT NOT NULL CHECK(state IN ('reserved','active','done')),
        collector_id TEXT,
        expires_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(place_id,server_id)
    );
    CREATE INDEX IF NOT EXISTS pvf_hop_jobs_status ON pvf_hop_jobs(state,expires_at);
    """)

def claimed(db, place, server, owner, t):
    row=db.execute(
        "SELECT state,collector_id,expires_at FROM pvf_hop_jobs WHERE place_id=? AND server_id=?",
        (place,server)).fetchone()
    return (row is not None and row['state']=='active'
            and row['collector_id']==owner and row['expires_at']>=t)

def mark_done(db, place, server, owner, t):
    # Llamar dentro de la misma transaccion que guarda los huevos.
    result=db.execute(
        """UPDATE pvf_hop_jobs
           SET state='done',collector_id=NULL,expires_at=0,updated_at=?
           WHERE place_id=? AND server_id=? AND collector_id=?
             AND state='active'""",
        (t,place,server,owner))
    if result.rowcount!=1:
        raise ValueError('Reserva vencida durante el informe')

def has_detections(db, place, server):
    return db.execute(
        'SELECT 1 FROM detections WHERE place_id=? AND server_id=? LIMIT 1',
        (place,server)).fetchone() is not None

def route(h,p,data,db,lock,valid_place_id,valid_job_id,now,check_rate):
    c=h.collector()
    if not c:
        return h.respond(401,{'error':'Credencial de recolector invalida'})
    if not check_rate('hop:'+c['id'],120,60):
        return h.respond(429,{'error':'Demasiadas peticiones de hop'})
    if not isinstance(data,dict):
        return h.respond(400,{'error':'Solicitud JSON invalida'})

    place=valid_place_id(data.get('place_id'))
    if not place:
        return h.respond(400,{'error':'PlaceId invalido'})
    t=now()

    if p=='/api/hop/start':
        server=valid_job_id(data.get('server_id'))
        if not server:
            return h.respond(400,{'error':'JobId invalido'})
        with lock:
            db.execute('BEGIN IMMEDIATE')
            try:
                row=db.execute('SELECT state,collector_id,expires_at FROM pvf_hop_jobs WHERE place_id=? AND server_id=?',(place,server)).fetchone()
                if has_detections(db,place,server) or (row and row['state']=='done'):
                    db.execute("""INSERT INTO pvf_hop_jobs(place_id,server_id,state,collector_id,expires_at,updated_at)
                                  VALUES(?,?,'done',NULL,0,?)
                                  ON CONFLICT(place_id,server_id) DO UPDATE
                                  SET state='done',collector_id=NULL,expires_at=0,updated_at=excluded.updated_at""",
                               (place,server,t))
                    result={'ok':True,'scan':False,'reason':'already_reported'}
                elif (row and row['collector_id'] != c['id']
                      and (row['state'] == 'active'
                           or (row['state'] == 'reserved' and row['expires_at'] > t))):
                    # Active jobs stay assigned permanently, even after expiry.
                    # This avoids assigning a bot another bot's visited server.
                    result={'ok':True,'scan':False,'reason':'reserved_by_another_bot'}
                else:
                    db.execute("""INSERT INTO pvf_hop_jobs(place_id,server_id,state,collector_id,expires_at,updated_at)
                                  VALUES(?,?,'active',?,?,?)
                                  ON CONFLICT(place_id,server_id) DO UPDATE
                                  SET state='active',collector_id=excluded.collector_id,
                                      expires_at=excluded.expires_at,updated_at=excluded.updated_at""",
                               (place,server,c['id'],t+ACTIVE_SCAN_SECONDS,t))
                    result={'ok':True,'scan':True,'reason':'assigned'}
                db.execute('COMMIT')
            except Exception:
                db.execute('ROLLBACK')
                raise
        return h.respond(200,result)

    if p=='/api/hop/next':
        current=valid_job_id(data.get('current_server'))
        candidates=data.get('candidates')
        if not current or not isinstance(candidates,list) or len(candidates)>100:
            return h.respond(400,{'error':'Candidatos de servidor invalidos'})
        # Aceptar cualquier servidor publico con lugar, incluso 0 o 3+ jugadores.
        # Respetar las reservas, evitar JobIds visitados y priorizar los menos llenos.
        # Clientes antiguos pueden omitir el conteo y quedan al final.
        populations={}
        for candidate in candidates:
            if isinstance(candidate,dict):
                sid=valid_job_id(candidate.get('id'))
                players=candidate.get('playing')
                max_players=candidate.get('maxPlayers')
                if type(players) is not int or not 0 <= players <= 1000:
                    continue
                # Roblox puede devolver una pagina desactualizada; no reservar
                # instancias que ya aparecen llenas en el reporte.
                if max_players is not None and (
                    type(max_players) is not int or not 1 <= max_players <= 1000
                    or players >= max_players
                ):
                    continue
            else:
                sid=valid_job_id(candidate)
                players=1001  # legacy: sin poblacion conocida, prioridad baja
            if sid and sid!=current:
                populations[sid]=min(players,populations.get(sid,players))
        available=list(populations)
        random.SystemRandom().shuffle(available)
        available.sort(key=lambda sid:populations[sid])
        chosen=None
        with lock:
            db.execute('BEGIN IMMEDIATE')
            try:
                for sid in available:
                    row=db.execute('SELECT state,expires_at FROM pvf_hop_jobs WHERE place_id=? AND server_id=?',(place,sid)).fetchone()
                    if row and (row['state'] in ('active', 'done')
                                or (row['state'] == 'reserved' and row['expires_at'] > t)):
                        # Never send a bot to a server already entered by any bot.
                        continue
                    if has_detections(db,place,sid):
                        continue
                    db.execute("""INSERT INTO pvf_hop_jobs(place_id,server_id,state,collector_id,expires_at,updated_at)
                                  VALUES(?,?,'reserved',?,?,?)
                                  ON CONFLICT(place_id,server_id) DO UPDATE
                                  SET state='reserved',collector_id=excluded.collector_id,
                                      expires_at=excluded.expires_at,updated_at=excluded.updated_at""",
                               (place,sid,c['id'],t+RESERVATION_SECONDS,t))
                    chosen=sid
                    break
                db.execute('COMMIT')
            except Exception:
                db.execute('ROLLBACK')
                raise
        return h.respond(200,{'ok':True,'server_id':chosen,
                              'player_count':(populations[chosen] if chosen and populations[chosen]!=1001 else None),
                              'reason':'assigned' if chosen else 'no_unvisited_server'})

    if p=='/api/hop/release':
        server=valid_job_id(data.get('server_id'))
        if not server:
            return h.respond(400,{'error':'JobId invalido'})
        failed=data.get('failed') is True
        with lock:
            if failed:
                # A failed join must not become the next bot's target again.
                # Persist it as visited, without inventing a detection.
                result=db.execute("""UPDATE pvf_hop_jobs
                          SET state='done',collector_id=NULL,expires_at=0,updated_at=?
                          WHERE place_id=? AND server_id=? AND state='reserved' AND collector_id=?""",
                       (t,place,server,c['id']))
            else:
                result=db.execute("""DELETE FROM pvf_hop_jobs
                          WHERE place_id=? AND server_id=? AND state='reserved' AND collector_id=?""",
                       (place,server,c['id']))
        return h.respond(200,{'ok':True,'excluded':failed and result.rowcount==1})
    return h.respond(404,{'error':'Ruta de hop no encontrada'})
