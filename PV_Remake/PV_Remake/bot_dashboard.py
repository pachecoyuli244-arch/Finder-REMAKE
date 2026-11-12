"""Read-only, owner-only dashboard data for PVFINDER collectors.

'Activo' is a recent heartbeat/snapshot estimate, not confirmation that the
Roblox process is running. Does not modify any collector, hop, or detection.
"""
from collections import defaultdict

SIGNAL_SECONDS = 90
SCAN_SECONDS = 300
MAX_LISTED_BOTS = 500
CYCLE_SECONDS = 300


def status(row, current):
    signal = row['signal_at'] or 0
    scan = row['last_seen'] or 0
    if signal >= current - SIGNAL_SECONDS and row['phase'] == 'paused':
        return 'paused'
    if signal >= current - SIGNAL_SECONDS and row['phase'] in ('scanning', 'moving'):
        return row['phase']
    if scan >= current - SCAN_SECONDS:
        return 'recent'
    return 'offline'


def snapshot(db, lock, current):
    """Read SQLite data only, using one brief mutex acquisition."""
    cycle = current // CYCLE_SECONDS * CYCLE_SECONDS
    with lock:
        bots = db.execute("""
            SELECT c.id, c.label, c.created_at, c.last_seen, c.revoked_at,
                   a.phase, a.reason, a.signal_at, a.last_pause_reason,
                   a.last_pause_at
            FROM collectors c
            LEFT JOIN collector_activity a ON a.collector_id=c.id
            WHERE c.revoked_at IS NULL
            ORDER BY max(coalesce(a.signal_at,0),coalesce(c.last_seen,0)) DESC,c.id
        """).fetchall()
        all_collectors = db.execute("SELECT COUNT(*) FROM collectors").fetchone()[0]
        revoked = db.execute(
            "SELECT COUNT(*) FROM collectors WHERE revoked_at IS NOT NULL"
        ).fetchone()[0]
        auto_sessions = db.execute("""
            SELECT COUNT(DISTINCT collector_id) FROM auto_collector_sessions
            WHERE expires_at>?""", (current,)).fetchone()[0]
        recent_eggs = db.execute("""
            SELECT collector_id, COUNT(*) AS eggs,
                   COUNT(DISTINCT server_id) AS servers,
                   MAX(updated_at) AS latest
            FROM detections WHERE updated_at>=?
            GROUP BY collector_id""", (current-3600,)).fetchall()
        latest_servers = db.execute("""
            SELECT collector_id, server_id, updated_at FROM detections
            WHERE updated_at>=? ORDER BY updated_at DESC
            LIMIT 10000""", (current-86400,)).fetchall()
        totals = db.execute("""
            SELECT
              COUNT(*) AS all_eggs,
              SUM(CASE WHEN updated_at>=? THEN 1 ELSE 0 END) AS eggs_hour,
              SUM(CASE WHEN updated_at>=? THEN 1 ELSE 0 END) AS eggs_day,
              COUNT(DISTINCT CASE WHEN updated_at>=? THEN server_id END)
                AS servers_hour
            FROM detections""",
            (current-3600,current-86400,current-3600)).fetchone()
        scanned_cycle = db.execute(
            "SELECT COUNT(*) FROM radar_server_scans WHERE cycle_start=?",
            (cycle,)).fetchone()[0]
        hop_counts = db.execute("""
            SELECT state,COUNT(*) AS n FROM pvf_hop_jobs
            GROUP BY state""").fetchall()
        buckets = db.execute("""
            SELECT (updated_at/300)*300 AS tick, COUNT(*) AS n
            FROM detections WHERE updated_at>=? AND updated_at<=?
            GROUP BY tick""", (current-3600,current)).fetchall()
        last_snapshot_at = db.execute(
            "SELECT MAX(last_seen) FROM collectors WHERE revoked_at IS NULL"
        ).fetchone()[0]

    recent_by_id = {r['collector_id']: dict(r) for r in recent_eggs}
    recent_server_by_id = {}
    for rec in latest_servers:
        recent_server_by_id.setdefault(rec['collector_id'], {
            'server_id':rec['server_id'], 'updated_at':rec['updated_at']
        })
    counts = {'scanning':0, 'moving':0, 'recent':0, 'paused':0, 'offline':0}
    listed = []
    for bot in bots:
        state = status(bot, current)
        counts[state] += 1
        if len(listed) >= MAX_LISTED_BOTS:
            continue
        recent = recent_by_id.get(bot['id'], {})
        latest = recent_server_by_id.get(bot['id'], {})
        listed.append({
            'label':bot['label'],
            'short_id':str(bot['id'])[:8],
            'state':state,
            'phase':bot['phase'] if bot['signal_at'] and bot['signal_at']>=current-SIGNAL_SECONDS else None,
            'reason':bot['reason'] if bot['signal_at'] and bot['signal_at']>=current-SIGNAL_SECONDS else None,
            'created_at':bot['created_at'],
            'last_scan_at':bot['last_seen'],
            'last_signal_at':bot['signal_at'],
            'last_pause_reason':bot['last_pause_reason'],
            'last_pause_at':bot['last_pause_at'],
            'eggs_hour':recent.get('eggs',0),
            'servers_with_eggs_hour':recent.get('servers',0),
            'last_reported_server':latest.get('server_id'),
            'last_reported_server_at':latest.get('updated_at'),
        })
    hop = {row['state']:row['n'] for row in hop_counts}
    bmap = {r['tick']:r['n'] for r in buckets}
    start = cycle - CYCLE_SECONDS*11
    activity = [{'start':start+i*CYCLE_SECONDS,
                 'eggs_updated':bmap.get(start+i*CYCLE_SECONDS,0)}
                for i in range(12)]
    return {
        'server_time':current,
        'active_window_seconds':SCAN_SECONDS,
        'signal_window_seconds':SIGNAL_SECONDS,
        'cycle_start':cycle,
        'counts':{
            'registered':all_collectors, 'not_revoked':len(bots),
            'revoked':revoked, 'active_estimate':counts['scanning']+counts['moving']+counts['recent'],
            'scanning':counts['scanning'], 'moving':counts['moving'],
            'recent':counts['recent'], 'paused':counts['paused'],
            'offline':counts['offline'], 'auto_sessions_valid':auto_sessions,
            'servers_current_cycle':scanned_cycle,
            'servers_with_eggs_hour':totals['servers_hour'] or 0,
            'eggs_hour':totals['eggs_hour'] or 0,
            'eggs_day':totals['eggs_day'] or 0,
            'eggs_saved':totals['all_eggs'] or 0,
            'hop_reserved':hop.get('reserved',0),
            'hop_active_recorded':hop.get('active',0),
            'hop_done':hop.get('done',0),
            'last_collector_scan_at':last_snapshot_at,
        },
        'bots':listed,
        'listed_count':len(listed),
        'total_count':len(bots),
        'activity':activity,
        'disclaimer':'Activo = señal reciente (90 s) o escaneo recibido (5 min). No confirma que Roblox esté abierto; sin señal no significa que el bot se cerró. Detecciones son huevos únicos cuyo último reporte se actualizó en el periodo. Los servidores del ciclo son los registrados con escaneo en este bloque de 5 minutos.',
    }
